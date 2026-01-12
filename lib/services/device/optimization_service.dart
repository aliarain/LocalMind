import 'dart:async';
import 'device_monitor.dart';
import '../llm/llm_service.dart';

/// Optimization mode for LLM inference
enum OptimizationMode {
  /// Maximum performance, no restrictions
  performance,

  /// Balanced mode (default)
  balanced,

  /// Battery saver - reduce inference speed
  batterySaver,

  /// Memory saver - use smaller context, more aggressive unloading
  memorySaver,
}

/// Configuration for optimization
class OptimizationConfig {
  final OptimizationMode mode;
  final bool autoUnloadOnLowMemory;
  final bool throttleOnLowBattery;
  final bool pauseOnCriticalBattery;
  final int criticalBatteryLevel;
  final int lowMemoryThresholdMB;

  const OptimizationConfig({
    this.mode = OptimizationMode.balanced,
    this.autoUnloadOnLowMemory = true,
    this.throttleOnLowBattery = true,
    this.pauseOnCriticalBattery = true,
    this.criticalBatteryLevel = 10,
    this.lowMemoryThresholdMB = 500,
  });

  OptimizationConfig copyWith({
    OptimizationMode? mode,
    bool? autoUnloadOnLowMemory,
    bool? throttleOnLowBattery,
    bool? pauseOnCriticalBattery,
    int? criticalBatteryLevel,
    int? lowMemoryThresholdMB,
  }) {
    return OptimizationConfig(
      mode: mode ?? this.mode,
      autoUnloadOnLowMemory: autoUnloadOnLowMemory ?? this.autoUnloadOnLowMemory,
      throttleOnLowBattery: throttleOnLowBattery ?? this.throttleOnLowBattery,
      pauseOnCriticalBattery: pauseOnCriticalBattery ?? this.pauseOnCriticalBattery,
      criticalBatteryLevel: criticalBatteryLevel ?? this.criticalBatteryLevel,
      lowMemoryThresholdMB: lowMemoryThresholdMB ?? this.lowMemoryThresholdMB,
    );
  }
}

/// Optimization event types
enum OptimizationEvent {
  modelUnloadedLowMemory,
  throttlingEnabled,
  throttlingDisabled,
  inferenceBlocked,
  inferenceResumed,
  configRecommendationChanged,
}

/// Service that optimizes LLM operations based on device state
class OptimizationService {
  final DeviceMonitor _deviceMonitor;

  OptimizationConfig _config;
  bool _isThrottling = false;
  bool _isBlocked = false;
  StreamSubscription<DeviceStatus>? _statusSubscription;

  final _eventController = StreamController<OptimizationEvent>.broadcast();
  final _configRecommendationController = StreamController<LLMConfig>.broadcast();

  OptimizationService({
    required DeviceMonitor deviceMonitor,
    OptimizationConfig config = const OptimizationConfig(),
  })  : _deviceMonitor = deviceMonitor,
        _config = config;

  /// Stream of optimization events
  Stream<OptimizationEvent> get events => _eventController.stream;

  /// Stream of recommended LLM config changes
  Stream<LLMConfig> get configRecommendations =>
      _configRecommendationController.stream;

  /// Current configuration
  OptimizationConfig get config => _config;

  /// Whether inference is currently throttled
  bool get isThrottling => _isThrottling;

  /// Whether inference is blocked due to critical resources
  bool get isBlocked => _isBlocked;

  /// Start monitoring and optimizing
  Future<void> start() async {
    await _deviceMonitor.startMonitoring();

    _statusSubscription = _deviceMonitor.statusStream.listen(_handleDeviceStatus);
  }

  /// Stop optimization service
  void stop() {
    _statusSubscription?.cancel();
    _deviceMonitor.stopMonitoring();
  }

  void _handleDeviceStatus(DeviceStatus status) {
    // Check for critical battery
    if (_config.pauseOnCriticalBattery &&
        status.batteryLevel <= _config.criticalBatteryLevel &&
        !status.isCharging) {
      if (!_isBlocked) {
        _isBlocked = true;
        _eventController.add(OptimizationEvent.inferenceBlocked);
      }
    } else if (_isBlocked) {
      _isBlocked = false;
      _eventController.add(OptimizationEvent.inferenceResumed);
    }

    // Check for low battery throttling
    if (_config.throttleOnLowBattery && status.isLowBattery && !status.isCharging) {
      if (!_isThrottling) {
        _isThrottling = true;
        _eventController.add(OptimizationEvent.throttlingEnabled);
        _recommendThrottledConfig();
      }
    } else if (_isThrottling && (!status.isLowBattery || status.isCharging)) {
      _isThrottling = false;
      _eventController.add(OptimizationEvent.throttlingDisabled);
      _recommendNormalConfig();
    }

    // Check for low memory
    if (_config.autoUnloadOnLowMemory && status.isLowMemory) {
      _eventController.add(OptimizationEvent.modelUnloadedLowMemory);
    }
  }

  void _recommendThrottledConfig() {
    // Reduce generation parameters for battery saving
    const throttledConfig = LLMConfig(
      maxTokens: 256, // Reduced from 512
      temperature: 0.7,
      contextLength: 1024, // Reduced from 2048
    );
    _configRecommendationController.add(throttledConfig);
    _eventController.add(OptimizationEvent.configRecommendationChanged);
  }

  void _recommendNormalConfig() {
    const normalConfig = LLMConfig();
    _configRecommendationController.add(normalConfig);
    _eventController.add(OptimizationEvent.configRecommendationChanged);
  }

  /// Update optimization configuration
  void updateConfig(OptimizationConfig config) {
    _config = config;
  }

  /// Get recommended LLM config based on current mode and device state
  Future<LLMConfig> getRecommendedConfig() async {
    final status = await _deviceMonitor.getCurrentStatus();

    switch (_config.mode) {
      case OptimizationMode.performance:
        return const LLMConfig(
          contextLength: 4096,
          maxTokens: 1024,
          temperature: 0.7,
        );

      case OptimizationMode.batterySaver:
        return const LLMConfig(
          contextLength: 1024,
          maxTokens: 256,
          temperature: 0.7,
        );

      case OptimizationMode.memorySaver:
        return const LLMConfig(
          contextLength: 512,
          maxTokens: 256,
          temperature: 0.7,
        );

      case OptimizationMode.balanced:
        // Adjust based on device state
        if (status.isLowBattery && !status.isCharging) {
          return const LLMConfig(
            contextLength: 1024,
            maxTokens: 256,
            temperature: 0.7,
          );
        }
        if (status.isLowMemory) {
          return const LLMConfig(
            contextLength: 1024,
            maxTokens: 256,
            temperature: 0.7,
          );
        }
        return const LLMConfig();
    }
  }

  /// Get recommended quantization level based on device RAM
  Future<String> getRecommendedQuantization() async {
    final status = await _deviceMonitor.getCurrentStatus();

    if (status.totalRamMB < 4096) {
      return 'q4_k_m'; // 4-bit quantization for low RAM
    } else if (status.totalRamMB < 6144) {
      return 'q5_k_m'; // 5-bit for medium RAM
    } else {
      return 'q8_0'; // 8-bit for high RAM devices
    }
  }

  /// Check if inference should proceed
  Future<bool> shouldAllowInference() async {
    if (_isBlocked) return false;

    final status = await _deviceMonitor.getCurrentStatus();

    // Block on critical battery (unless charging)
    if (_config.pauseOnCriticalBattery &&
        status.batteryLevel <= _config.criticalBatteryLevel &&
        !status.isCharging) {
      return false;
    }

    // Allow if low memory but warn (actual unloading handled elsewhere)
    return true;
  }

  /// Get human-readable status message
  Future<String> getStatusMessage() async {
    if (_isBlocked) {
      return 'Inference paused - Battery critically low. Please charge your device.';
    }

    if (_isThrottling) {
      return 'Battery saver active - Responses may be shorter.';
    }

    final status = await _deviceMonitor.getCurrentStatus();
    if (status.isLowMemory) {
      return 'Low memory - Consider closing other apps.';
    }

    return 'Ready';
  }

  Future<void> dispose() async {
    stop();
    await _eventController.close();
    await _configRecommendationController.close();
  }
}
