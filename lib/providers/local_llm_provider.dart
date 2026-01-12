import 'dart:async';
import 'package:raptrai/raptrai.dart';
import '../services/llm/llm_service.dart';
import '../services/llm/flutter_llama_service.dart';
import '../services/llm/model_manager.dart';

/// A RaptrAI-compatible provider that uses local on-device LLMs
/// instead of cloud APIs. This enables offline AI chat functionality.
class LocalLLMProvider extends RaptrAIProvider {
  final FlutterLlamaService _llmService;
  final ModelManager _modelManager;
  final String _systemPrompt;

  String? _currentModelId;
  bool _isInitialized = false;
  bool _isCancelled = false;

  LocalLLMProvider({
    required FlutterLlamaService llmService,
    required ModelManager modelManager,
    String systemPrompt = 'You are a helpful AI assistant.',
  })  : _llmService = llmService,
        _modelManager = modelManager,
        _systemPrompt = systemPrompt;

  /// Create provider with default services
  static Future<LocalLLMProvider> create({
    String? modelId,
    String systemPrompt = 'You are a helpful AI assistant.',
    LLMConfig config = const LLMConfig(),
  }) async {
    final modelManager = ModelManager();
    await modelManager.initialize();

    final llmService = FlutterLlamaService(
      modelManager: modelManager,
      config: config,
    );
    await llmService.initialize();

    final provider = LocalLLMProvider(
      llmService: llmService,
      modelManager: modelManager,
      systemPrompt: systemPrompt,
    );

    // Load model if specified, otherwise use recommended
    try {
      final targetModelId = modelId ?? await modelManager.getRecommendedModelId();
      await provider.loadModel(targetModelId);
    } catch (e) {
      // No model available yet - user will need to download
    }

    return provider;
  }

  @override
  String get name => 'Local LLM';

  @override
  String get id => 'local';

  @override
  String get defaultModel => _currentModelId ?? 'qwen2-0.5b';

  @override
  List<RaptrAIModelInfo> get availableModels {
    return _modelManager.getAvailableModels().map((m) => RaptrAIModelInfo(
      id: m.id,
      name: m.name,
      contextWindow: 2048,
      maxOutputTokens: 512,
    )).toList();
  }

  /// Whether the provider is ready to generate
  bool get isReady => _isInitialized && _llmService.status == LLMStatus.ready;

  /// Whether generation is in progress
  bool get isGenerating => _llmService.status == LLMStatus.generating;

  /// Current model ID
  String? get currentModelId => _currentModelId;

  /// Load a specific model
  Future<void> loadModel(String modelId) async {
    await _llmService.loadModel(modelId);
    _currentModelId = modelId;
    _isInitialized = true;
  }

  /// Unload current model to free memory
  Future<void> unloadModel() async {
    await _llmService.unloadModel();
    _currentModelId = null;
  }

  @override
  Stream<RaptrAIChunk> chat({
    required List<RaptrAIMessage> messages,
    required String model,
    List<RaptrAIToolDefinition>? tools,
    RaptrAIChatConfig config = RaptrAIChatConfig.defaults,
  }) async* {
    if (!isReady) {
      throw StateError('Provider not ready. Load a model first.');
    }

    _isCancelled = false;

    // Build prompt from messages
    final prompt = _buildPromptFromMessages(messages);

    try {
      await for (final token in _llmService.streamResponse(prompt, systemPrompt: _systemPrompt)) {
        if (_isCancelled) break;

        yield RaptrAIChunk(
          content: token,
        );
      }

      // Send final chunk
      yield RaptrAIChunk(
        content: '',
        finishReason: RaptrAIFinishReason.stop,
      );
    } catch (e) {
      yield RaptrAIChunk(
        content: '',
        finishReason: RaptrAIFinishReason.other,
      );
    }
  }

  @override
  void cancel() {
    _isCancelled = true;
    _llmService.stopGeneration();
  }

  @override
  Future<int> countTokens(List<RaptrAIMessage> messages, {String? model}) async {
    // Simple estimation: ~4 characters per token
    final prompt = _buildPromptFromMessages(messages);
    return (prompt.length / 4).ceil();
  }

  @override
  Future<bool> validate() async {
    return isReady;
  }

  /// Build a prompt string from RaptrAI messages
  String _buildPromptFromMessages(List<RaptrAIMessage> messages) {
    final buffer = StringBuffer();

    // Include recent context (last 10 messages for context window efficiency)
    final recentMessages = messages.length > 10
        ? messages.sublist(messages.length - 10)
        : messages;

    for (final message in recentMessages) {
      if (message.role == RaptrAIRole.user) {
        buffer.writeln('User: ${message.content}');
      } else if (message.role == RaptrAIRole.assistant) {
        buffer.writeln('Assistant: ${message.content}');
      } else if (message.role == RaptrAIRole.system) {
        buffer.writeln('System: ${message.content}');
      }
    }

    return buffer.toString().trim();
  }

  /// Update LLM configuration
  Future<void> updateConfig(LLMConfig config) async {
    await _llmService.updateConfig(config);
  }

  /// Get current memory usage in MB
  int get memoryUsageMB => _llmService.modelMemoryUsageMB;

  /// Download a model
  Future<void> downloadModel(
    String modelId, {
    void Function(double progress)? onProgress,
  }) async {
    await _modelManager.downloadModel(modelId, onProgress: onProgress);
  }

  /// Delete a downloaded model
  Future<void> deleteModel(String modelId) async {
    await _modelManager.deleteModel(modelId);
  }

  /// Stream of model download progress
  Stream<Map<String, double>> get downloadProgress =>
      _modelManager.downloadProgress;

  /// Get list of ready-to-use models
  List<ModelInfo> get readyModels => _modelManager.getReadyModels();

  Future<void> dispose() async {
    await _llmService.dispose();
    await _modelManager.dispose();
  }
}
