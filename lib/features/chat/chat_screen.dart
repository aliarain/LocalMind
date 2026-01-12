import 'package:flutter/material.dart';
import 'package:raptrai/raptrai.dart';
import '../../core/config/app_config.dart';
import '../../providers/local_llm_provider.dart';
import '../../services/device/optimization_service.dart';
import '../settings/settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final LocalLLMProvider provider;
  final RaptrAIStorage storage;
  final OptimizationService optimizationService;

  const ChatScreen({
    super.key,
    required this.provider,
    required this.storage,
    required this.optimizationService,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          // Status indicator
          _StatusIndicator(
            message: _statusMessage,
            isGenerating: widget.provider.isGenerating,
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
