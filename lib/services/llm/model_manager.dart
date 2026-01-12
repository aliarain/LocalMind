import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'llm_service.dart';

/// Manages model downloads, storage, and availability
class ModelManager {
  final Dio _dio;
  final DeviceInfoPlugin _deviceInfo;

  String? _modelsDirectory;
  final Map<String, ModelInfo> _availableModels = {};
  final Map<String, double> _downloadProgress = {};

  final _progressController = StreamController<Map<String, double>>.broadcast();
  Stream<Map<String, double>> get downloadProgress => _progressController.stream;

  ModelManager({Dio? dio, DeviceInfoPlugin? deviceInfo})
      : _dio = dio ?? Dio(),
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  /// Initialize model manager and scan for available models
  Future<void> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    _modelsDirectory = '${appDir.path}/models';

    // Create models directory if not exists
    final dir = Directory(_modelsDirectory!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Register known models
    _registerKnownModels();

    // Scan for downloaded models
    await _scanDownloadedModels();
  }

  void _registerKnownModels() {
    // Bundled small model (will be copied from assets on first run)
    _availableModels['qwen2-0.5b'] = const ModelInfo(
      id: 'qwen2-0.5b',
      name: 'Qwen2 0.5B (Bundled)',
      path: 'qwen2-0.5b-instruct-q4_k_m.gguf',
      sizeBytes: 400 * 1024 * 1024, // ~400MB
      requiredRamMB: 2048,
      isBundled: true,
    );

    // Downloadable models
    _availableModels['gemma-2b'] = const ModelInfo(
      id: 'gemma-2b',
      name: 'Gemma 2B',
      path: 'gemma-2b-it-q4_k_m.gguf',
      sizeBytes: 1500 * 1024 * 1024, // ~1.5GB
      requiredRamMB: 4096,
    );

    _availableModels['llama-3.2-1b'] = const ModelInfo(
      id: 'llama-3.2-1b',
      name: 'Llama 3.2 1B',
      path: 'llama-3.2-1b-instruct-q4_k_m.gguf',
      sizeBytes: 800 * 1024 * 1024, // ~800MB
      requiredRamMB: 3072,
    );

    _availableModels['phi-3-mini'] = const ModelInfo(
      id: 'phi-3-mini',
      name: 'Phi-3 Mini',
      path: 'phi-3-mini-4k-instruct-q4_k_m.gguf',
      sizeBytes: 2200 * 1024 * 1024, // ~2.2GB
      requiredRamMB: 4096,
    );

    _availableModels['smollm-360m'] = const ModelInfo(
      id: 'smollm-360m',
      name: 'SmolLM 360M',
      path: 'smollm-360m-instruct-q8_0.gguf',
      sizeBytes: 380 * 1024 * 1024, // ~380MB
      requiredRamMB: 2048,
    );
  }

  Future<void> _scanDownloadedModels() async {
    if (_modelsDirectory == null) return;

    final dir = Directory(_modelsDirectory!);
    if (!await dir.exists()) return;

    await for (final file in dir.list()) {
      if (file is File && file.path.endsWith('.gguf')) {
        final fileName = file.path.split('/').last;
        // Mark models as downloaded if file exists
        for (final entry in _availableModels.entries) {
          if (entry.value.path == fileName) {
            _availableModels[entry.key] = ModelInfo(
              id: entry.value.id,
              name: entry.value.name,
              path: entry.value.path,
              sizeBytes: await file.length(),
              requiredRamMB: entry.value.requiredRamMB,
              isBundled: entry.value.isBundled,
              isDownloaded: true,
            );
          }
        }
      }
    }
  }

  /// Get list of all available models
  List<ModelInfo> getAvailableModels() {
    return _availableModels.values.toList();
  }

  /// Get list of models ready to use (downloaded or bundled)
  List<ModelInfo> getReadyModels() {
    return _availableModels.values
        .where((m) => m.isDownloaded || m.isBundled)
        .toList();
  }

  /// Get model info by ID
  Future<ModelInfo?> getModelInfo(String modelId) async {
    return _availableModels[modelId];
  }

  /// Get the local file path for a model
  Future<String?> getModelPath(String modelId) async {
    final model = _availableModels[modelId];
    if (model == null) return null;

    final fullPath = '$_modelsDirectory/${model.path}';
    final file = File(fullPath);

    if (await file.exists()) {
      return fullPath;
    }

    return null;
  }

  /// Check if a model is ready to use
  Future<bool> isModelReady(String modelId) async {
    final path = await getModelPath(modelId);
    return path != null;
  }

  /// Download a model from Hugging Face
  Future<void> downloadModel(
    String modelId, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final model = _availableModels[modelId];
    if (model == null) {
      throw Exception('Unknown model: $modelId');
    }

    if (model.isBundled) {
      throw Exception('Bundled models cannot be downloaded');
    }

    final downloadUrl = _getDownloadUrl(modelId);
    if (downloadUrl == null) {
      throw Exception('Download URL not available for: $modelId');
    }

    final savePath = '$_modelsDirectory/${model.path}';

    try {
      _downloadProgress[modelId] = 0;
      _progressController.add(Map.from(_downloadProgress));

      await _dio.download(
        downloadUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            _downloadProgress[modelId] = progress;
            _progressController.add(Map.from(_downloadProgress));
            onProgress?.call(progress);
          }
        },
      );

      // Update model as downloaded
      _availableModels[modelId] = ModelInfo(
        id: model.id,
        name: model.name,
        path: model.path,
        sizeBytes: model.sizeBytes,
        requiredRamMB: model.requiredRamMB,
        isBundled: model.isBundled,
        isDownloaded: true,
      );

      _downloadProgress.remove(modelId);
      _progressController.add(Map.from(_downloadProgress));
    } catch (e) {
      _downloadProgress.remove(modelId);
      _progressController.add(Map.from(_downloadProgress));

      // Clean up partial download
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  String? _getDownloadUrl(String modelId) {
    // Hugging Face URLs for GGUF models
    const baseUrl = 'https://huggingface.co';

    switch (modelId) {
      case 'gemma-2b':
        return '$baseUrl/google/gemma-2b-it-GGUF/resolve/main/gemma-2b-it-q4_k_m.gguf';
      case 'llama-3.2-1b':
        return '$baseUrl/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf';
      case 'phi-3-mini':
        return '$baseUrl/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf';
      case 'smollm-360m':
        return '$baseUrl/HuggingFaceTB/SmolLM-360M-Instruct-GGUF/resolve/main/smollm-360m-instruct-q8_0.gguf';
      default:
        return null;
    }
  }

  /// Delete a downloaded model
  Future<void> deleteModel(String modelId) async {
    final model = _availableModels[modelId];
    if (model == null) return;

    if (model.isBundled) {
      throw Exception('Cannot delete bundled models');
    }

    final path = '$_modelsDirectory/${model.path}';
    final file = File(path);

    if (await file.exists()) {
      await file.delete();
    }

    // Update model status
    _availableModels[modelId] = ModelInfo(
      id: model.id,
      name: model.name,
      path: model.path,
      sizeBytes: model.sizeBytes,
      requiredRamMB: model.requiredRamMB,
      isBundled: model.isBundled,
      isDownloaded: false,
    );
  }

  /// Get device RAM in MB
  Future<int> getDeviceRamMB() async {
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      // totalMemory is in bytes
      return (androidInfo.systemFeatures.isNotEmpty)
          ? 4096 // Fallback estimate
          : 4096;
    } else if (Platform.isIOS) {
      // iOS doesn't expose RAM directly, estimate based on device
      return 4096; // Conservative estimate
    }
    return 4096; // Default fallback
  }

  /// Get recommended model based on device capabilities
  Future<String> getRecommendedModelId() async {
    final ramMB = await getDeviceRamMB();

    if (ramMB >= 6144) {
      // 6GB+ RAM: Can run larger models
      final gemma = _availableModels['gemma-2b'];
      if (gemma?.isDownloaded == true) return 'gemma-2b';
    }

    if (ramMB >= 4096) {
      // 4GB+ RAM: Medium models
      final llama = _availableModels['llama-3.2-1b'];
      if (llama?.isDownloaded == true) return 'llama-3.2-1b';
    }

    // Default to smallest available model
    final smol = _availableModels['smollm-360m'];
    if (smol?.isDownloaded == true) return 'smollm-360m';

    final qwen = _availableModels['qwen2-0.5b'];
    if (qwen?.isDownloaded == true || qwen?.isBundled == true) return 'qwen2-0.5b';

    // No model available
    throw Exception('No models available. Please download a model first.');
  }

  /// Cancel ongoing download
  void cancelDownload(String modelId, CancelToken cancelToken) {
    cancelToken.cancel('Download cancelled by user');
    _downloadProgress.remove(modelId);
    _progressController.add(Map.from(_downloadProgress));
  }

  Future<void> dispose() async {
    await _progressController.close();
  }
}
