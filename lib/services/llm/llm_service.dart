import 'dart:async';

/// Configuration for LLM inference
class LLMConfig {
  final int contextLength;
  final double temperature;
  final int maxTokens;
  final double topP;
  final int topK;
  final double repeatPenalty;

  const LLMConfig({
    this.contextLength = 2048,
    this.temperature = 0.7,
    this.maxTokens = 512,
    this.topP = 0.9,
    this.topK = 40,
    this.repeatPenalty = 1.1,
  });

  LLMConfig copyWith({
    int? contextLength,
    double? temperature,
    int? maxTokens,
    double? topP,
    int? topK,
    double? repeatPenalty,
  }) {
    return LLMConfig(
      contextLength: contextLength ?? this.contextLength,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
    );
  }
}

/// Model information
class ModelInfo {
  final String id;
  final String name;
  final String path;
  final int sizeBytes;
  final int requiredRamMB;
  final bool isBundled;
  final bool isDownloaded;
  final String? downloadUrl;
  final String? hfModelId;

  const ModelInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.requiredRamMB,
    this.isBundled = false,
    this.isDownloaded = false,
    this.downloadUrl,
    this.hfModelId,
  });

  String get sizeFormatted {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }

  /// Create a copy with updated fields
  ModelInfo copyWith({
    String? id,
    String? name,
    String? path,
    int? sizeBytes,
    int? requiredRamMB,
    bool? isBundled,
    bool? isDownloaded,
    String? downloadUrl,
    String? hfModelId,
  }) {
    return ModelInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      requiredRamMB: requiredRamMB ?? this.requiredRamMB,
      isBundled: isBundled ?? this.isBundled,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      hfModelId: hfModelId ?? this.hfModelId,
    );
  }
}

/// Status of LLM service
enum LLMStatus {
  uninitialized,
  loading,
  ready,
  generating,
  unloading,
  error,
}

/// Abstract interface for LLM operations
abstract class LLMService {
  /// Current status of the service
  LLMStatus get status;

  /// Stream of status changes
  Stream<LLMStatus> get statusStream;

  /// Currently loaded model info (null if none loaded)
  ModelInfo? get currentModel;

  /// Current configuration
  LLMConfig get config;

  /// Initialize the service
  Future<void> initialize();

  /// Load a model by its ID
  Future<void> loadModel(String modelId);

  /// Unload the current model to free memory
  Future<void> unloadModel();

  /// Generate a response for the given prompt
  /// Returns the complete response
  Future<String> generateResponse(String prompt, {String? systemPrompt});

  /// Stream tokens as they are generated
  Stream<String> streamResponse(String prompt, {String? systemPrompt});

  /// Stop any ongoing generation
  Future<void> stopGeneration();

  /// Update configuration (may require model reload)
  Future<void> updateConfig(LLMConfig config);

  /// Check if a model is compatible with current device
  Future<bool> isModelCompatible(ModelInfo model);

  /// Get memory usage of loaded model in MB
  int get modelMemoryUsageMB;

  /// Dispose resources
  Future<void> dispose();
}
