import 'package:flutter/material.dart';
import 'package:raptrai/raptrai.dart';
import '../../core/config/app_config.dart';
import '../../providers/local_llm_provider.dart';
import '../../services/device/optimization_service.dart';
import '../../services/llm/model_manager.dart';
import '../settings/settings_screen.dart';
import '../models/model_picker_screen.dart';

class ChatScreen extends StatefulWidget {
  final LocalLLMProvider provider;
  final RaptrAIStorage storage;
  final OptimizationService optimizationService;
  final ModelManager modelManager;

  const ChatScreen({
    super.key,
    required this.provider,
    required this.storage,
    required this.optimizationService,
    required this.modelManager,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  String _statusMessage = 'Ready';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Listen to optimization events
    widget.optimizationService.events.listen((event) {
      _updateStatusMessage();
    });
  }

  Future<void> _updateStatusMessage() async {
    final message = await widget.optimizationService.getStatusMessage();
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          provider: widget.provider,
          storage: widget.storage,
          optimizationService: widget.optimizationService,
        ),
      ),
    );
  }

  void _openModelPicker() async {
    final selectedModelId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => ModelPickerScreen(
          modelManager: widget.modelManager,
          onModelSelected: (modelId) async {
            await _loadModel(modelId);
          },
        ),
      ),
    );

    if (selectedModelId != null && mounted) {
      setState(() {});
    }
  }

  Future<void> _loadModel(String modelId) async {
    try {
      await widget.provider.loadModel(modelId);
      if (mounted) {
        setState(() {
          _statusMessage = 'Ready';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load model: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if model is ready
    final isModelReady = widget.provider.isReady;

    // If no model is loaded, show model picker
    if (!isModelReady) {
      return _buildNoModelScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          // Status indicator
          _StatusIndicator(
            message: _statusMessage,
            isGenerating: widget.provider.isGenerating,
          ),
          // Model selector button
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: _openModelPicker,
            tooltip: 'Change Model',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: RaptrAIChat(
        provider: widget.provider,
        systemPrompt: AppConfig.defaultSystemPrompt,
        storage: widget.storage,
        welcomeGreeting: 'Hello! I\'m Local Mind',
        welcomeSubtitle: 'Your private, offline AI assistant',
        suggestions: AppConfig.defaultSuggestions
            .map((s) => RaptrAISuggestion(
                  title: s['title']!,
                  subtitle: s['subtitle']!,
                ))
            .toList(),
        onError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        },
      ),
    );
  }

  /// Build the screen shown when no model is loaded
  Widget _buildNoModelScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.smart_toy_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No Model Selected',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Select or download a language model to start chatting. Models run entirely on your device for complete privacy.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _openModelPicker,
                icon: const Icon(Icons.download),
                label: const Text('Browse Models'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'All AI processing happens on-device',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status indicator widget
class _StatusIndicator extends StatelessWidget {
  final String message;
  final bool isGenerating;

  const _StatusIndicator({
    required this.message,
    required this.isGenerating,
  });

  @override
  Widget build(BuildContext context) {
    final isReady = message == 'Ready';
    final color = isReady
        ? Colors.green
        : isGenerating
            ? Theme.of(context).colorScheme.primary
            : Colors.orange;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isGenerating)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            isReady ? 'Ready' : (isGenerating ? 'Thinking...' : message),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}
