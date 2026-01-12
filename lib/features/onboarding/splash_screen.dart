import 'package:flutter/material.dart';
import 'package:raptrai/raptrai.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/local_llm_provider.dart';
import '../../services/llm/model_manager.dart';
import '../../services/llm/flutter_llama_service.dart';
import '../../services/device/device_monitor.dart';
import '../../services/device/optimization_service.dart';
import '../chat/chat_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _statusMessage = 'Initializing...';
  double _progress = 0;
  bool _hasError = false;
  String? _errorMessage;
  bool _showPrivacyNotice = true;
  DeviceStatus? _deviceStatus;

  @override
  void initState() {
    super.initState();
    _checkDevice();
  }

  Future<void> _checkDevice() async {
    setState(() {
      _statusMessage = 'Checking device...';
      _progress = 0.1;
    });

    try {
      final deviceMonitor = DeviceMonitor();
      final status = await deviceMonitor.getCurrentStatus();

      setState(() {
        _deviceStatus = status;
      });

      // Check device compatibility
      if (status.totalRamMB < AppConfig.minRamMB) {
        setState(() {
          _hasError = true;
          _errorMessage =
              'Your device has ${status.totalRamMB}MB RAM. '
              'Local Mind requires at least ${AppConfig.minRamMB}MB RAM for optimal performance.';
        });
        return;
      }

      // Show warning for low RAM devices
      if (status.totalRamMB < AppConfig.recommendedRamMB) {
        // Continue but will use smaller models
      }

      await deviceMonitor.dispose();
    } catch (e) {
      // Continue even if device check fails
    }
  }

  Future<void> _initializeApp() async {
    setState(() {
      _showPrivacyNotice = false;
      _statusMessage = 'Initializing storage...';
      _progress = 0.2;
    });

    try {
      // Initialize storage using RaptrAI's built-in Hive storage
      final chatStorage = RaptrAIHiveStorage();
      await chatStorage.initialize();

      setState(() {
        _statusMessage = 'Loading model manager...';
        _progress = 0.4;
      });

      // Initialize model manager
      final modelManager = ModelManager();
      await modelManager.initialize();

      setState(() {
        _statusMessage = 'Setting up optimization...';
        _progress = 0.5;
      });

      // Initialize device monitoring
      final deviceMonitor = DeviceMonitor();
      final optimizationService = OptimizationService(
        deviceMonitor: deviceMonitor,
      );
      await optimizationService.start();

      setState(() {
        _statusMessage = 'Loading AI model...';
        _progress = 0.6;
      });

      // Initialize LLM service
      final llmService = FlutterLlamaService(
        modelManager: modelManager,
        config: await optimizationService.getRecommendedConfig(),
      );
      await llmService.initialize();

      setState(() {
        _statusMessage = 'Preparing AI assistant...';
        _progress = 0.8;
      });

      // Create provider
      final provider = LocalLLMProvider(
        llmService: llmService,
        modelManager: modelManager,
        systemPrompt: AppConfig.defaultSystemPrompt,
      );

      // Try to load recommended model
      try {
        final recommendedModelId = await modelManager.getRecommendedModelId();
        await provider.loadModel(recommendedModelId);
      } catch (e) {
        // No model available yet - user will need to download
        setState(() {
          _statusMessage = 'No model available. Please download one.';
        });
      }

      setState(() {
        _statusMessage = 'Ready!';
        _progress = 1.0;
      });

      // Navigate to chat screen
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              provider: provider,
              storage: chatStorage,
              optimizationService: optimizationService,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to initialize: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Logo/Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(
                  Icons.psychology_outlined,
                  size: 64,
                  color: AppTheme.primaryColor,
                ),
              ),

              const SizedBox(height: 32),

              // App name
              Text(
                AppConfig.appName,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),

              const SizedBox(height: 8),

              Text(
                AppConfig.appDescription,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),

              const Spacer(),

              if (_showPrivacyNotice) ...[
                // Privacy notice
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.security_outlined,
                            color: AppTheme.successColor,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Private & Offline',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Local Mind runs entirely on your device. Your conversations '
                        'never leave your phone, ensuring complete privacy.',
                      ),
                      const SizedBox(height: 16),
                      if (_deviceStatus != null)
                        Row(
                          children: [
                            _DeviceStatChip(
                              icon: Icons.memory,
                              label: '${_deviceStatus!.totalRamMB} MB RAM',
                            ),
                            const SizedBox(width: 8),
                            _DeviceStatChip(
                              icon: Icons.battery_std,
                              label: '${_deviceStatus!.batteryLevel}%',
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Continue button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _hasError ? null : _initializeApp,
                    child: const Text('Get Started'),
                  ),
                ),
              ] else ...[
                // Loading state
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _statusMessage,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],

              // Error state
              if (_hasError) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: AppTheme.errorColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage ?? 'An error occurred',
                          style: TextStyle(color: AppTheme.errorColor),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _errorMessage = null;
                      _showPrivacyNotice = true;
                    });
                    _checkDevice();
                  },
                  child: const Text('Try Again'),
                ),
              ],

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceStatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DeviceStatChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
