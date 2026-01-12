import 'dart:async';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'llm_service.dart';
import 'model_manager.dart';

/// Implementation of LLMService using llama_cpp_dart (llama.cpp wrapper)
class FlutterLlamaService implements LLMService {
  final ModelManager _modelManager;

  Llama? _llama;
  LLMStatus _status = LLMStatus.uninitialized;
  ModelInfo? _currentModel;
  LLMConfig _config;
  bool _isGenerating = false;
  bool _shouldStop = false;

  final _statusController = StreamController<LLMStatus>.broadcast();

  FlutterLlamaService({
    required ModelManager modelManager,
    LLMConfig config = const LLMConfig(),
  })  : _modelManager = modelManager,
        _config = config;

  @override
  LLMStatus get status => _status;

  @override
  Stream<LLMStatus> get statusStream => _statusController.stream;

  @override
  ModelInfo? get currentModel => _currentModel;

  @override
  LLMConfig get config => _config;

  void _setStatus(LLMStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  @override
  Future<void> initialize() async {
    if (_status != LLMStatus.uninitialized) return;
    _setStatus(LLMStatus.ready);
  }

  @override
  Future<void> loadModel(String modelId) async {
    if (_status == LLMStatus.loading || _status == LLMStatus.generating) {
      throw StateError('Cannot load model while $status');
    }

    // Unload current model if any
    if (_llama != null) {
      await unloadModel();
    }

    _setStatus(LLMStatus.loading);

    try {
      final modelInfo = await _modelManager.getModelInfo(modelId);
      if (modelInfo == null) {
        throw Exception('Model not found: $modelId');
      }

      final modelPath = await _modelManager.getModelPath(modelId);
      if (modelPath == null) {
        throw Exception('Model file not available: $modelId');
      }

      // Initialize llama_cpp_dart with model
      final modelParams = ModelParams();
      modelParams.nGpuLayers = 0; // CPU only for compatibility

      final contextParams = ContextParams();
      contextParams.nCtx = _config.contextLength;
      contextParams.nBatch = 512;
      contextParams.nPredict = _config.maxTokens;

      _llama = Llama(
        modelPath,
        modelParams: modelParams,
        contextParams: contextParams,
      );

      _currentModel = modelInfo;
      _setStatus(LLMStatus.ready);
    } catch (e) {
      _setStatus(LLMStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> unloadModel() async {
    if (_llama == null) return;

    _setStatus(LLMStatus.unloading);

    try {
      _llama!.dispose();
      _llama = null;
      _currentModel = null;
      _setStatus(LLMStatus.ready);
    } catch (e) {
      _setStatus(LLMStatus.error);
      rethrow;
    }
  }

  @override
  Future<String> generateResponse(String prompt, {String? systemPrompt}) async {
    if (_llama == null) {
      throw StateError('No model loaded');
    }

    if (_isGenerating) {
      throw StateError('Generation already in progress');
    }

    _isGenerating = true;
    _shouldStop = false;
    _setStatus(LLMStatus.generating);

    final fullPrompt = _buildPrompt(prompt, systemPrompt);
    _llama!.setPrompt(fullPrompt);

    try {
      // Use generateCompleteText for full response
      final response = await _llama!.generateCompleteText(maxTokens: _config.maxTokens);
      return response.trim();
    } catch (e) {
      // Fallback to manual generation if generateCompleteText fails
      final buffer = StringBuffer();

      int tokenCount = 0;
      while (tokenCount < _config.maxTokens && !_shouldStop) {
        final (token, isDone) = _llama!.getNext();
        buffer.write(token);
        tokenCount++;
        if (isDone) break;
      }

      return buffer.toString().trim();
    } finally {
      _isGenerating = false;
      _setStatus(LLMStatus.ready);
    }
  }

  @override
  Stream<String> streamResponse(String prompt, {String? systemPrompt}) async* {
    if (_llama == null) {
      throw StateError('No model loaded');
    }

    if (_isGenerating) {
      throw StateError('Generation already in progress');
    }

    _isGenerating = true;
    _shouldStop = false;
    _setStatus(LLMStatus.generating);

    try {
      final fullPrompt = _buildPrompt(prompt, systemPrompt);

      // Set the prompt
      _llama!.setPrompt(fullPrompt);

      // Stream tokens using generateText stream
      await for (final token in _llama!.generateText()) {
        if (_shouldStop) break;
        yield token;
      }
    } finally {
      _isGenerating = false;
      _setStatus(LLMStatus.ready);
    }
  }

  String _buildPrompt(String userPrompt, String? systemPrompt) {
    // Using ChatML format for better compatibility
    final buffer = StringBuffer();

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.writeln('<|im_start|>system');
      buffer.writeln(systemPrompt);
      buffer.writeln('<|im_end|>');
    }

    buffer.writeln('<|im_start|>user');
    buffer.writeln(userPrompt);
    buffer.writeln('<|im_end|>');
    buffer.writeln('<|im_start|>assistant');

    return buffer.toString();
  }

  @override
  Future<void> stopGeneration() async {
    if (_isGenerating) {
      _shouldStop = true;
    }
  }

  @override
  Future<void> updateConfig(LLMConfig config) async {
    final oldContextLength = _config.contextLength;
    _config = config;

    // If context length changed and model is loaded, need to reload
    if (_currentModel != null && config.contextLength != oldContextLength) {
      final modelId = _currentModel!.id;
      await unloadModel();
      await loadModel(modelId);
    }
  }

  @override
  Future<bool> isModelCompatible(ModelInfo model) async {
    final deviceRam = await _modelManager.getDeviceRamMB();
    // Model needs roughly 2x its size in RAM for inference
    return deviceRam >= model.requiredRamMB;
  }

  @override
  int get modelMemoryUsageMB {
    if (_currentModel == null) return 0;
    // Approximate: model size + context buffer
    return (_currentModel!.sizeBytes / (1024 * 1024)).round() +
           (_config.contextLength * 4 / 1024).round(); // ~4 bytes per token
  }

  @override
  Future<void> dispose() async {
    await stopGeneration();
    await unloadModel();
    await _statusController.close();
  }
}
