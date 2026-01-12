import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../services/llm/model_manager.dart';
import '../../services/llm/llm_service.dart';
import '../../services/huggingface/hf_model.dart';
import 'widgets/model_card.dart';

/// Track active download info
class _DownloadInfo {
  final String modelName;
  final String fileName;
  final int totalBytes;
  final DateTime startTime;

  _DownloadInfo({
    required this.modelName,
    required this.fileName,
    required this.totalBytes,
    required this.startTime,
  });
}

/// Screen for browsing, downloading, and selecting models
class ModelPickerScreen extends StatefulWidget {
  final ModelManager modelManager;
  final void Function(String modelId)? onModelSelected;
  final bool showBackButton;

  const ModelPickerScreen({
    super.key,
    required this.modelManager,
    this.onModelSelected,
    this.showBackButton = true,
  });

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  int? _deviceRamMB;

  // Downloaded/local models
  List<ModelInfo> _localModels = [];

  // HuggingFace search results
  List<HFModelWithFiles> _searchResults = [];
  List<HFModelWithFiles> _recommendedModels = [];

  // Download tracking
  final Map<String, CancelToken> _downloadTokens = {};
  final Map<String, _DownloadInfo> _activeDownloads = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    // Cancel any ongoing downloads
    for (final token in _downloadTokens.values) {
      token.cancel();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get device RAM
      _deviceRamMB = await widget.modelManager.getCachedDeviceRamMB();

      // Load local models
      _localModels = widget.modelManager.getReadyModels();

      // Load recommended models from HuggingFace
      _recommendedModels = await widget.modelManager.getRecommendedHFModels();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load models: $e';
      });
    }
  }

  Future<void> _searchModels(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await widget.modelManager.searchWithDetails(
        query: query,
        limit: 15,
      );

      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Search failed: $e';
      });
    }
  }

  /// Get the progress key that matches model_manager
  String _getProgressKey(String hfModelId, String fileName) {
    return widget.modelManager.generateModelId(hfModelId, fileName);
  }

  Future<void> _downloadModel(HFModelWithFiles model, HFModelFile file) async {
    final key = _getProgressKey(model.model.modelId, file.fileName);
    final cancelToken = CancelToken();
    _downloadTokens[key] = cancelToken;

    // Track download info
    setState(() {
      _activeDownloads[key] = _DownloadInfo(
        modelName: model.model.displayName,
        fileName: file.fileName,
        totalBytes: file.sizeBytes,
        startTime: DateTime.now(),
      );
    });

    try {
      await widget.modelManager.downloadHFModel(
        model.model.modelId,
        file.fileName,
        cancelToken: cancelToken,
      );

      if (mounted) {
        // Remove from active downloads
        setState(() {
          _activeDownloads.remove(key);
          _localModels = widget.modelManager.getReadyModels();
        });

        // Show completion dialog
        _showDownloadCompleteDialog(model.model.displayName, key);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _activeDownloads.remove(key);
        });

        if (!cancelToken.isCancelled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Download failed: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } finally {
      _downloadTokens.remove(key);
    }
  }

  void _showDownloadCompleteDialog(String modelName, String modelId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Download Complete!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              modelName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Model is ready to use. Would you like to select it now?',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _selectModel(modelId);
            },
            child: const Text('Use Now'),
          ),
        ],
      ),
    );
  }

  void _cancelDownload(String modelId, String fileName) {
    final key = _getProgressKey(modelId, fileName);
    _downloadTokens[key]?.cancel();
    _downloadTokens.remove(key);
    setState(() {
      _activeDownloads.remove(key);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Download cancelled')),
    );
  }

  Future<void> _selectModel(String modelId) async {
    // Save selection
    await widget.modelManager.saveLastSelectedModel(modelId);

    // Notify parent
    widget.onModelSelected?.call(modelId);

    if (mounted && widget.showBackButton) {
      Navigator.of(context).pop(modelId);
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
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.modelManager.deleteModel(modelId);
      if (mounted) {
        setState(() {
          _localModels = widget.modelManager.getReadyModels();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model deleted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Model'),
        automaticallyImplyLeading: widget.showBackButton,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'My Models'),
            Tab(text: 'Recommended'),
            Tab(text: 'Search'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Active downloads banner
          _buildActiveDownloadsBanner(),

          // Device info banner
          if (_deviceRamMB != null && _activeDownloads.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    Icons.memory,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Device RAM: ${_deviceRamMB}MB',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    'Models need ~60% free RAM',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),

          // Error banner
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadInitialData,
                  ),
                ],
              ),
            ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLocalModelsTab(),
                _buildRecommendedTab(),
                _buildSearchTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the active downloads banner
  Widget _buildActiveDownloadsBanner() {
    return StreamBuilder<Map<String, double>>(
      stream: widget.modelManager.downloadProgress,
      builder: (context, snapshot) {
        final progress = snapshot.data ?? {};

        if (_activeDownloads.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Column(
            children: _activeDownloads.entries.map((entry) {
              final key = entry.key;
              final info = entry.value;
              final downloadProgress = progress[key] ?? 0.0;
              final downloadedBytes = (downloadProgress * info.totalBytes).toInt();

              // Calculate speed
              final elapsed = DateTime.now().difference(info.startTime);
              final speedBps = elapsed.inSeconds > 0
                  ? downloadedBytes / elapsed.inSeconds
                  : 0.0;

              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Downloading ${info.modelName}',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_formatBytes(downloadedBytes)} / ${_formatBytes(info.totalBytes)} • ${_formatSpeed(speedBps)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${(downloadProgress * 100).toStringAsFixed(0)}%',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            final parts = key.split('_');
                            if (parts.length >= 2) {
                              // Reconstruct the original model ID and file name
                              // This is a bit hacky but works
                              _downloadTokens[key]?.cancel();
                              _downloadTokens.remove(key);
                              setState(() {
                                _activeDownloads.remove(key);
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Download cancelled')),
                              );
                            }
                          },
                          tooltip: 'Cancel download',
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: downloadProgress,
                        minHeight: 6,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (bytesPerSecond >= 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${bytesPerSecond.toStringAsFixed(0)} B/s';
  }

  Widget _buildLocalModelsTab() {
    if (_localModels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.download_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No models downloaded yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Browse recommended models or search HuggingFace',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _tabController.animateTo(1),
              icon: const Icon(Icons.star_outline),
              label: const Text('View Recommended'),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<Map<String, double>>(
      stream: widget.modelManager.downloadProgress,
      builder: (context, snapshot) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _localModels.length,
          itemBuilder: (context, index) {
            final model = _localModels[index];
            return LocalModelCard(
              model: model,
              deviceRamMB: _deviceRamMB ?? 4096,
              onSelect: () => _selectModel(model.id),
              onDelete: model.isBundled ? null : () => _deleteModel(model.id),
            );
          },
        );
      },
    );
  }

  Widget _buildRecommendedTab() {
    if (_isLoading && _recommendedModels.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_recommendedModels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            const Text('Unable to load recommended models'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadInitialData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<Map<String, double>>(
      stream: widget.modelManager.downloadProgress,
      builder: (context, snapshot) {
        final progress = snapshot.data ?? {};

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _recommendedModels.length,
          itemBuilder: (context, index) {
            final model = _recommendedModels[index];
            final file = model.recommendedFile ?? model.ggufFiles.first;
            final key = _getProgressKey(model.model.modelId, file.fileName);

            return HFModelCard(
              model: model,
              file: file,
              deviceRamMB: _deviceRamMB ?? 4096,
              downloadProgress: progress[key],
              isDownloading: _activeDownloads.containsKey(key),
              onDownload: () => _downloadModel(model, file),
              onCancelDownload: () =>
                  _cancelDownload(model.model.modelId, file.fileName),
            );
          },
        );
      },
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search GGUF models on HuggingFace...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = [];
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: _searchModels,
            textInputAction: TextInputAction.search,
          ),
        ),

        // Search suggestions
        if (_searchResults.isEmpty && _searchController.text.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Try searching for:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildSearchChip('llama'),
                    _buildSearchChip('phi'),
                    _buildSearchChip('gemma'),
                    _buildSearchChip('qwen'),
                    _buildSearchChip('mistral'),
                    _buildSearchChip('tinyllama'),
                  ],
                ),
              ],
            ),
          ),

        // Loading indicator
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),

        // Search results
        if (!_isLoading && _searchResults.isNotEmpty)
          Expanded(
            child: StreamBuilder<Map<String, double>>(
              stream: widget.modelManager.downloadProgress,
              builder: (context, snapshot) {
                final progress = snapshot.data ?? {};

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final model = _searchResults[index];
                    final file = model.recommendedFile ?? model.ggufFiles.first;
                    final key = _getProgressKey(model.model.modelId, file.fileName);

                    return HFModelCard(
                      model: model,
                      file: file,
                      deviceRamMB: _deviceRamMB ?? 4096,
                      downloadProgress: progress[key],
                      isDownloading: _activeDownloads.containsKey(key),
                      onDownload: () => _downloadModel(model, file),
                      onCancelDownload: () =>
                          _cancelDownload(model.model.modelId, file.fileName),
                    );
                  },
                );
              },
            ),
          ),

        // No results
        if (!_isLoading &&
            _searchResults.isEmpty &&
            _searchController.text.isNotEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No GGUF models found for "${_searchController.text}"',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try a different search term',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchChip(String query) {
    return ActionChip(
      label: Text(query),
      onPressed: () {
        _searchController.text = query;
        _searchModels(query);
      },
    );
  }
}
