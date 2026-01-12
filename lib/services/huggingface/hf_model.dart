/// Data models for HuggingFace API responses
library;

/// Represents a model from HuggingFace Hub
class HFModel {
  final String id;
  final String modelId;
  final String? author;
  final int downloads;
  final int likes;
  final DateTime? lastModified;
  final List<String> tags;
  final String? pipelineTag;

  const HFModel({
    required this.id,
    required this.modelId,
    this.author,
    this.downloads = 0,
    this.likes = 0,
    this.lastModified,
    this.tags = const [],
    this.pipelineTag,
  });

  /// Display name (without author prefix)
  String get displayName {
    if (modelId.contains('/')) {
      return modelId.split('/').last;
    }
    return modelId;
  }

  /// Whether this is a GGUF model
  bool get isGGUF => tags.contains('gguf') || modelId.toLowerCase().contains('gguf');

  factory HFModel.fromJson(Map<String, dynamic> json) {
    return HFModel(
      id: json['id'] ?? json['_id'] ?? '',
      modelId: json['modelId'] ?? json['id'] ?? '',
      author: json['author'],
      downloads: json['downloads'] ?? 0,
      likes: json['likes'] ?? 0,
      lastModified: json['lastModified'] != null
          ? DateTime.tryParse(json['lastModified'])
          : null,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      pipelineTag: json['pipeline_tag'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'modelId': modelId,
        'author': author,
        'downloads': downloads,
        'likes': likes,
        'lastModified': lastModified?.toIso8601String(),
        'tags': tags,
        'pipeline_tag': pipelineTag,
      };
}

/// Represents a file within a HuggingFace model repository
class HFModelFile {
  final String fileName;
  final int sizeBytes;
  final String? quantization;
  final String path;

  const HFModelFile({
    required this.fileName,
    required this.sizeBytes,
    this.quantization,
    this.path = '',
  });

  /// Size formatted as human-readable string
  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Extract quantization from filename (e.g., Q4_K_M from "model.Q4_K_M.gguf")
  static String? extractQuantization(String fileName) {
    final patterns = [
      RegExp(r'[._-](Q\d+_K_[SM])', caseSensitive: false),
      RegExp(r'[._-](Q\d+_[0KS])', caseSensitive: false),
      RegExp(r'[._-](Q\d+)', caseSensitive: false),
      RegExp(r'[._-](F16|F32|BF16)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(fileName);
      if (match != null) {
        return match.group(1)?.toUpperCase();
      }
    }
    return null;
  }

  factory HFModelFile.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String? ?? '';
    final fileName = path.split('/').last;

    return HFModelFile(
      fileName: fileName,
      sizeBytes: json['size'] ?? 0,
      quantization: extractQuantization(fileName),
      path: path,
    );
  }
}

/// Model compatibility status based on device RAM
enum ModelCompatibility {
  /// RAM required <= 70% device RAM (safe to run)
  compatible,

  /// RAM required <= 90% device RAM (might work but may be slow)
  marginal,

  /// RAM required > 90% device RAM (likely won't work)
  incompatible,
}

/// Extended model info combining HF data with local status
class HFModelWithFiles {
  final HFModel model;
  final List<HFModelFile> ggufFiles;

  const HFModelWithFiles({
    required this.model,
    required this.ggufFiles,
  });

  /// Get the recommended GGUF file (smallest Q4 variant)
  HFModelFile? get recommendedFile {
    if (ggufFiles.isEmpty) return null;

    // Prefer Q4_K_M or Q4_K_S for balance of quality and size
    final q4km = ggufFiles.where((f) =>
        f.quantization == 'Q4_K_M' || f.quantization == 'Q4_K_S').toList();
    if (q4km.isNotEmpty) {
      q4km.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
      return q4km.first;
    }

    // Fall back to any Q4 variant
    final q4 = ggufFiles.where((f) =>
        f.quantization?.startsWith('Q4') == true).toList();
    if (q4.isNotEmpty) {
      q4.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
      return q4.first;
    }

    // Fall back to smallest file
    final sorted = List<HFModelFile>.from(ggufFiles)
      ..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    return sorted.first;
  }
}
