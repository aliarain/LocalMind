/// HuggingFace API client for searching and downloading GGUF models
library;

import 'package:dio/dio.dart';
import 'hf_model.dart';

/// Service for interacting with HuggingFace Hub API
class HuggingFaceAPI {
  static const String _baseUrl = 'https://huggingface.co/api';
  static const String _downloadBaseUrl = 'https://huggingface.co';

  final Dio _dio;

  HuggingFaceAPI({Dio? dio}) : _dio = dio ?? Dio();

  /// Search for GGUF models on HuggingFace
  ///
  /// [query] - Optional search query (e.g., "llama", "mistral")
  /// [limit] - Maximum number of results (default: 20)
  /// [sortBy] - Sort by: downloads, likes, lastModified (default: downloads)
  Future<List<HFModel>> searchGGUFModels({
    String? query,
    int limit = 20,
    String sortBy = 'downloads',
  }) async {
    try {
      final searchQuery = query?.isNotEmpty == true ? '$query gguf' : 'gguf';

      final response = await _dio.get(
        '$_baseUrl/models',
        queryParameters: {
          'search': searchQuery,
          'filter': 'gguf',
          'sort': sortBy,
          'direction': '-1',
          'limit': limit,
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data
            .map((json) => HFModel.fromJson(json))
            .where((model) => model.isGGUF)
            .toList();
      }

      return [];
    } catch (e) {
      throw HuggingFaceException('Failed to search models: $e');
    }
  }

  /// Get popular/featured GGUF models
  Future<List<HFModel>> getPopularGGUFModels({int limit = 20}) async {
    return searchGGUFModels(limit: limit, sortBy: 'downloads');
  }

  /// Get model details including file listing
  Future<HFModelWithFiles> getModelDetails(String modelId) async {
    try {
      // Get model info
      final modelResponse = await _dio.get('$_baseUrl/models/$modelId');

      if (modelResponse.statusCode != 200) {
        throw HuggingFaceException('Model not found: $modelId');
      }

      final model = HFModel.fromJson(modelResponse.data);

      // Get file tree
      final filesResponse = await _dio.get(
        '$_baseUrl/models/$modelId/tree/main',
      );

      final List<HFModelFile> ggufFiles = [];

      if (filesResponse.statusCode == 200) {
        final List<dynamic> files = filesResponse.data;

        for (final file in files) {
          final path = file['path'] as String? ?? '';
          if (path.toLowerCase().endsWith('.gguf')) {
            ggufFiles.add(HFModelFile.fromJson(file));
          }
        }
      }

      return HFModelWithFiles(model: model, ggufFiles: ggufFiles);
    } catch (e) {
      if (e is HuggingFaceException) rethrow;
      throw HuggingFaceException('Failed to get model details: $e');
    }
  }

  /// Get the direct download URL for a GGUF file
  String getDownloadUrl(String modelId, String fileName) {
    return '$_downloadBaseUrl/$modelId/resolve/main/$fileName';
  }

  /// Search for models by specific criteria
  Future<List<HFModelWithFiles>> searchWithDetails({
    String? query,
    int limit = 10,
    int? maxSizeMB,
  }) async {
    final models = await searchGGUFModels(query: query, limit: limit * 2);
    final results = <HFModelWithFiles>[];

    for (final model in models) {
      if (results.length >= limit) break;

      try {
        final details = await getModelDetails(model.modelId);

        // Filter by size if specified
        if (maxSizeMB != null && details.ggufFiles.isNotEmpty) {
          final hasCompatibleFile = details.ggufFiles.any(
            (f) => f.sizeBytes <= maxSizeMB * 1024 * 1024,
          );
          if (!hasCompatibleFile) continue;
        }

        if (details.ggufFiles.isNotEmpty) {
          results.add(details);
        }
      } catch (e) {
        // Skip models that fail to load details
        continue;
      }
    }

    return results;
  }

  /// Get curated list of recommended small models for mobile
  Future<List<HFModelWithFiles>> getRecommendedMobileModels() async {
    // Curated list of known-good small GGUF models for mobile
    const recommendedIds = [
      'Qwen/Qwen2-0.5B-Instruct-GGUF',
      'HuggingFaceTB/SmolLM-360M-Instruct-GGUF',
      'microsoft/Phi-3-mini-4k-instruct-gguf',
      'bartowski/Llama-3.2-1B-Instruct-GGUF',
      'google/gemma-2b-it-GGUF',
      'TinyLlama/TinyLlama-1.1B-Chat-v1.0-GGUF',
    ];

    final results = <HFModelWithFiles>[];

    for (final modelId in recommendedIds) {
      try {
        final details = await getModelDetails(modelId);
        if (details.ggufFiles.isNotEmpty) {
          results.add(details);
        }
      } catch (e) {
        // Skip models that fail to load
        continue;
      }
    }

    return results;
  }
}

/// Exception thrown by HuggingFace API operations
class HuggingFaceException implements Exception {
  final String message;

  const HuggingFaceException(this.message);

  @override
  String toString() => 'HuggingFaceException: $message';
}

/// RAM estimation utilities
class RAMEstimator {
  /// Estimate RAM needed to run a model based on file size and quantization
  static int estimateRamMB(int fileSizeBytes, String? quantization) {
    final fileSizeMB = fileSizeBytes / (1024 * 1024);

    // RAM multiplier based on quantization level
    final multiplier = switch (quantization?.toUpperCase()) {
      'Q4_K_M' || 'Q4_K_S' || 'Q4_0' || 'Q4_1' => 1.5,
      'Q5_K_M' || 'Q5_K_S' || 'Q5_0' || 'Q5_1' => 1.7,
      'Q6_K' => 1.8,
      'Q8_0' => 2.0,
      'F16' || 'FP16' => 2.5,
      'F32' || 'FP32' => 3.0,
      _ => 1.8, // Default conservative estimate
    };

    return (fileSizeMB * multiplier).ceil();
  }

  /// Check model compatibility with device RAM
  static ModelCompatibility checkCompatibility(int requiredRamMB, int deviceRamMB) {
    final ratio = requiredRamMB / deviceRamMB;

    if (ratio <= 0.6) return ModelCompatibility.compatible;
    if (ratio <= 0.85) return ModelCompatibility.marginal;
    return ModelCompatibility.incompatible;
  }

  /// Get compatibility color for UI
  static String getCompatibilityLabel(ModelCompatibility compatibility) {
    return switch (compatibility) {
      ModelCompatibility.compatible => 'Compatible',
      ModelCompatibility.marginal => 'May be slow',
      ModelCompatibility.incompatible => 'Too large',
    };
  }
}
