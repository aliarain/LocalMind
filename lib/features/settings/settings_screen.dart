import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:raptrai/raptrai.dart';
import '../../core/config/app_config.dart';
import '../../providers/local_llm_provider.dart';
import '../../services/llm/llm_service.dart';
import '../../services/device/device_monitor.dart';
import '../../services/device/optimization_service.dart';

class SettingsScreen extends StatefulWidget {
  final LocalLLMProvider provider;
  final RaptrAIStorage storage;
  final OptimizationService optimizationService;

  const SettingsScreen({
    super.key,
    required this.provider,
    required this.storage,
    required this.optimizationService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late OptimizationMode _optimizationMode;
  final Map<String, CancelToken> _downloadTokens = {};

  @override
  void initState() {
    super.initState();
    _optimizationMode = widget.optimizationService.config.mode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _buildSection(
            title: 'Model',
            children: [
              _buildModelSelector(),
            ],
          ),
          _buildSection(
            title: 'Download Models',
            children: [
              _buildModelDownloadList(),
            ],
          ),
          _buildSection(
            title: 'Optimization',
            children: [
              _buildOptimizationModeSelector(),
              _buildDeviceStats(),
            ],
          ),
          _buildSection(
            title: 'Storage',
            children: [
              _buildStorageInfo(),
              _buildClearDataButton(),
            ],
          ),
          _buildSection(
            title: 'About',
            children: [
              _buildAboutInfo(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }

  Widget _buildModelSelector() {
    final currentModel = widget.provider.currentModelId;
    final readyModels = widget.provider.readyModels;

    return ListTile(
      leading: const Icon(Icons.smart_toy_outlined),
      title: const Text('Active Model'),
      subtitle: Text(
        readyModels.firstWhere(
          (m) => m.id == currentModel,
          orElse: () => readyModels.first,
        ).name,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showModelPicker(readyModels),
    );
  }

  void _showModelPicker(List<ModelInfo> models) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Model',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...models.map((model) => ListTile(
                  leading: model.id == widget.provider.currentModelId
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.circle_outlined),
                  title: Text(model.name),
                  subtitle: Text('${model.sizeFormatted} • ${model.requiredRamMB}MB RAM'),
                  onTap: () async {
                    Navigator.pop(context);
                    if (model.id != widget.provider.currentModelId) {
                      await _loadModel(model.id);
                    }
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _loadModel(String modelId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Loading model...'),
          ],
        ),
      ),
    );

    try {
      await widget.provider.loadModel(modelId);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model loaded successfully')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load model: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Widget _buildModelDownloadList() {
    // Use our ModelInfo for download functionality
    final allModels = _getAllModelsForDownload();

    return StreamBuilder<Map<String, double>>(
      stream: widget.provider.downloadProgress,
      builder: (context, snapshot) {
        final progress = snapshot.data ?? {};

        return Column(
          children: allModels.map((model) {
            final isDownloading = progress.containsKey(model.id);
            final downloadProgress = progress[model.id] ?? 0;
            final isReady = model.isDownloaded || model.isBundled;

            return ListTile(
              leading: Icon(
                isReady
                    ? Icons.check_circle
                    : isDownloading
                        ? Icons.downloading
                        : Icons.cloud_download_outlined,
                color: isReady ? Colors.green : null,
              ),
              title: Text(model.name),
              subtitle: isDownloading
                  ? LinearProgressIndicator(value: downloadProgress)
                  : Text(
                      '${model.sizeFormatted} • ${model.requiredRamMB}MB RAM required',
                    ),
              trailing: isReady
                  ? (model.isBundled
                      ? const Chip(label: Text('Bundled'))
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteModel(model.id),
                        ))
                  : isDownloading
                      ? IconButton(
                          icon: const Icon(Icons.cancel),
                          onPressed: () => _cancelDownload(model.id),
                        )
                      : IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () => _downloadModel(model.id),
                        ),
            );
          }).toList(),
        );
      },
    );
  }

  /// Get all models (both ready and available for download) using our ModelInfo
  List<ModelInfo> _getAllModelsForDownload() {
    // This uses our own ModelInfo type from model_manager.dart
    return widget.provider.readyModels;
  }

  Future<void> _downloadModel(String modelId) async {
    final cancelToken = CancelToken();
    _downloadTokens[modelId] = cancelToken;

    try {
      await widget.provider.downloadModel(
        modelId,
        onProgress: (progress) {
          // Progress is handled by stream
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model downloaded successfully')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted && !cancelToken.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      _downloadTokens.remove(modelId);
    }
  }

  void _cancelDownload(String modelId) {
    final token = _downloadTokens[modelId];
    if (token != null) {
      token.cancel('Cancelled by user');
      _downloadTokens.remove(modelId);
      setState(() {});
    }
  }

  Future<void> _deleteModel(String modelId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model'),
        content: const Text(
          'Are you sure you want to delete this model? You can download it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.provider.deleteModel(modelId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model deleted')),
        );
        setState(() {});
      }
    }
  }

  Widget _buildOptimizationModeSelector() {
    return ListTile(
      leading: const Icon(Icons.speed_outlined),
      title: const Text('Optimization Mode'),
      subtitle: Text(_getModeDescription(_optimizationMode)),
      trailing: DropdownButton<OptimizationMode>(
        value: _optimizationMode,
        underline: const SizedBox(),
        items: OptimizationMode.values.map((mode) {
          return DropdownMenuItem(
            value: mode,
            child: Text(_getModeName(mode)),
          );
        }).toList(),
        onChanged: (mode) {
          if (mode != null) {
            setState(() {
              _optimizationMode = mode;
            });
            widget.optimizationService.updateConfig(
              widget.optimizationService.config.copyWith(mode: mode),
            );
          }
        },
      ),
    );
  }

  String _getModeName(OptimizationMode mode) {
    switch (mode) {
      case OptimizationMode.performance:
        return 'Performance';
      case OptimizationMode.balanced:
        return 'Balanced';
      case OptimizationMode.batterySaver:
        return 'Battery Saver';
      case OptimizationMode.memorySaver:
        return 'Memory Saver';
    }
  }

  String _getModeDescription(OptimizationMode mode) {
    switch (mode) {
      case OptimizationMode.performance:
        return 'Maximum speed, higher battery usage';
      case OptimizationMode.balanced:
        return 'Automatic adjustments based on device state';
      case OptimizationMode.batterySaver:
        return 'Shorter responses, lower battery usage';
      case OptimizationMode.memorySaver:
        return 'Smaller context, less memory usage';
    }
  }

  Widget _buildDeviceStats() {
    return FutureBuilder<DeviceStatus>(
      future: DeviceMonitor().getCurrentStatus(),
      builder: (context, snapshot) {
        final status = snapshot.data;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device Status',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        icon: Icons.memory,
                        label: 'RAM',
                        value: status != null
                            ? '${status.availableRamMB}/${status.totalRamMB} MB'
                            : 'Loading...',
                      ),
                    ),
                    Expanded(
                      child: _StatItem(
                        icon: Icons.battery_std,
                        label: 'Battery',
                        value: status != null
                            ? '${status.batteryLevel}%${status.isCharging ? ' ⚡' : ''}'
                            : 'Loading...',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _StatItem(
                  icon: Icons.smart_toy,
                  label: 'Model Memory',
                  value: '${widget.provider.memoryUsageMB} MB',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStorageInfo() {
    return FutureBuilder<int>(
      future: widget.storage.getConversationCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: const Text('Chat Storage'),
          subtitle: Text('$count conversation${count == 1 ? '' : 's'}'),
        );
      },
    );
  }

  Widget _buildClearDataButton() {
    return ListTile(
      leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
      title: Text(
        'Clear All Chats',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      subtitle: const Text('This cannot be undone'),
      onTap: _confirmClearData,
    );
  }

  Future<void> _confirmClearData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Chats'),
        content: const Text(
          'This will permanently delete all your chat history. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.storage.deleteAllConversations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All chats cleared')),
        );
        setState(() {});
      }
    }
  }

  Widget _buildAboutInfo() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text(AppConfig.appName),
          subtitle: Text('Version ${AppConfig.appVersion}'),
        ),
        const ListTile(
          leading: Icon(Icons.privacy_tip_outlined),
          title: Text('Privacy'),
          subtitle: Text(
            'All AI processing happens on your device. No data is sent to external servers.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open Source Models'),
          subtitle: const Text(
            'Powered by open-source language models (Gemma, Llama, Phi, SmolLM)',
          ),
          onTap: () {
            // Could link to model licenses
          },
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}
