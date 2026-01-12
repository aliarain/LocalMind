import 'package:flutter/material.dart';
import '../../../services/llm/llm_service.dart';
import '../../../services/huggingface/hf_model.dart';
import '../../../services/huggingface/huggingface_api.dart';

/// Card widget for displaying a local/downloaded model
class LocalModelCard extends StatelessWidget {
  final ModelInfo model;
  final int deviceRamMB;
  final VoidCallback onSelect;
  final VoidCallback? onDelete;

  const LocalModelCard({
    super.key,
    required this.model,
    required this.deviceRamMB,
    required this.onSelect,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final compatibility = RAMEstimator.checkCompatibility(
      model.requiredRamMB,
      deviceRamMB,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Model icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.smart_toy,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Model info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _InfoChip(
                              icon: Icons.storage,
                              label: model.sizeFormatted,
                            ),
                            const SizedBox(width: 8),
                            _InfoChip(
                              icon: Icons.memory,
                              label: '${model.requiredRamMB}MB RAM',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Actions
                  Column(
                    children: [
                      _CompatibilityBadge(compatibility: compatibility),
                      if (model.isBundled)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Chip(
                            label: Text('Bundled'),
                            padding: EdgeInsets.zero,
                            labelPadding: EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onDelete != null)
                    TextButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onSelect,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Select'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card widget for displaying a HuggingFace model
class HFModelCard extends StatelessWidget {
  final HFModelWithFiles model;
  final HFModelFile file;
  final int deviceRamMB;
  final double? downloadProgress;
  final bool isDownloading;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;

  const HFModelCard({
    super.key,
    required this.model,
    required this.file,
    required this.deviceRamMB,
    this.downloadProgress,
    this.isDownloading = false,
    required this.onDownload,
    required this.onCancelDownload,
  });

  @override
  Widget build(BuildContext context) {
    final estimatedRam = RAMEstimator.estimateRamMB(
      file.sizeBytes,
      file.quantization,
    );
    final compatibility = RAMEstimator.checkCompatibility(
      estimatedRam,
      deviceRamMB,
    );
    final isCompatible = compatibility != ModelCompatibility.incompatible;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Model icon with HF logo indicator
                Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.cloud_download,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'HF',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),

                // Model info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.model.displayName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        model.model.modelId,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _InfoChip(
                            icon: Icons.storage,
                            label: file.sizeFormatted,
                          ),
                          _InfoChip(
                            icon: Icons.memory,
                            label: '~${estimatedRam}MB RAM',
                          ),
                          if (file.quantization != null)
                            _InfoChip(
                              icon: Icons.compress,
                              label: file.quantization!,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Compatibility badge
                _CompatibilityBadge(compatibility: compatibility),
              ],
            ),

            // Download stats
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.download,
                    size: 14,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDownloads(model.model.downloads),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.favorite,
                    size: 14,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${model.model.likes}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  if (model.ggufFiles.length > 1) ...[
                    const SizedBox(width: 16),
                    Icon(
                      Icons.file_present,
                      size: 14,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${model.ggufFiles.length} variants',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ],
              ),
            ),

            // Download progress or button
            if (isDownloading) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: downloadProgress,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          downloadProgress != null
                              ? '${(downloadProgress! * 100).toStringAsFixed(1)}%'
                              : 'Starting...',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton.outlined(
                    onPressed: onCancelDownload,
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel download',
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isCompatible)
                    Expanded(
                      child: Text(
                        'May not run smoothly on this device',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: isCompatible ? onDownload : null,
                    icon: const Icon(Icons.download, size: 18),
                    label: Text('Download (${file.sizeFormatted})'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDownloads(int downloads) {
    if (downloads >= 1000000) {
      return '${(downloads / 1000000).toStringAsFixed(1)}M';
    } else if (downloads >= 1000) {
      return '${(downloads / 1000).toStringAsFixed(1)}K';
    }
    return '$downloads';
  }
}

/// Small info chip widget
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Compatibility badge widget
class _CompatibilityBadge extends StatelessWidget {
  final ModelCompatibility compatibility;

  const _CompatibilityBadge({required this.compatibility});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (compatibility) {
      ModelCompatibility.compatible => (
          Colors.green,
          Icons.check_circle,
          'Compatible'
        ),
      ModelCompatibility.marginal => (
          Colors.orange,
          Icons.warning,
          'May be slow'
        ),
      ModelCompatibility.incompatible => (
          Colors.red,
          Icons.error,
          'Too large'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
