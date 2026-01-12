import 'dart:async';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Device resource status
class DeviceStatus {
  final int totalRamMB;
  final int availableRamMB;
  final int batteryLevel;
  final BatteryState batteryState;
  final bool isLowMemory;
  final bool isLowBattery;
  final bool isCharging;

  const DeviceStatus({
    required this.totalRamMB,
    required this.availableRamMB,
    required this.batteryLevel,
    required this.batteryState,
    required this.isLowMemory,
    required this.isLowBattery,
    required this.isCharging,
  });

  /// Memory usage percentage
  double get memoryUsagePercent =>
      totalRamMB > 0 ? (1 - (availableRamMB / totalRamMB)) * 100 : 0;

  /// Whether device can handle LLM inference
  bool get canRunInference => !isLowMemory && (!isLowBattery || isCharging);

  @override
  String toString() {
    return 'DeviceStatus(RAM: $availableRamMB/$totalRamMB MB, Battery: $batteryLevel%, '
        'Charging: $isCharging, LowMem: $isLowMemory, LowBat: $isLowBattery)';
  }
}

/// Monitors device resources (RAM, battery) for optimization
class DeviceMonitor {
  final Battery _battery;
  final DeviceInfoPlugin _deviceInfo;

  static const int lowMemoryThresholdMB = 500;
  static const int lowBatteryThreshold = 20;
  static const Duration pollInterval = Duration(seconds: 30);

  Timer? _pollTimer;
  final _statusController = StreamController<DeviceStatus>.broadcast();
  DeviceStatus? _lastStatus;

  DeviceMonitor({Battery? battery, DeviceInfoPlugin? deviceInfo})
      : _battery = battery ?? Battery(),
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  /// Stream of device status updates
  Stream<DeviceStatus> get statusStream => _statusController.stream;

  /// Last known device status
  DeviceStatus? get lastStatus => _lastStatus;

  /// Start monitoring device resources
  Future<void> startMonitoring() async {
    // Get initial status
    await _updateStatus();

    // Start periodic polling
    _pollTimer = Timer.periodic(pollInterval, (_) => _updateStatus());

    // Listen to battery state changes
    _battery.onBatteryStateChanged.listen((state) {
      _updateStatus();
    });
  }

  /// Stop monitoring
  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _updateStatus() async {
    final status = await getCurrentStatus();
    _lastStatus = status;
    _statusController.add(status);
  }

  /// Get current device status
  Future<DeviceStatus> getCurrentStatus() async {
    final batteryLevel = await _battery.batteryLevel;
    final batteryState = await _battery.batteryState;

    int totalRam = 4096; // Default estimate
    int availableRam = 2048;

    if (Platform.isAndroid) {
      // Android doesn't directly expose available RAM through device_info_plus
      // We use a heuristic based on total RAM
      totalRam = 4096; // Default estimate for Android

      // Estimate available RAM as 40-60% of total on average
      availableRam = (totalRam * 0.5).round();
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      // iOS is even more restrictive about RAM info
      totalRam = _estimateIOSRam(iosInfo.utsname.machine);
      availableRam = (totalRam * 0.5).round();
    }

    final isLowMemory = availableRam < lowMemoryThresholdMB;
    final isLowBattery = batteryLevel < lowBatteryThreshold;
    final isCharging = batteryState == BatteryState.charging ||
        batteryState == BatteryState.full;

    return DeviceStatus(
      totalRamMB: totalRam,
      availableRamMB: availableRam,
      batteryLevel: batteryLevel,
      batteryState: batteryState,
      isLowMemory: isLowMemory,
      isLowBattery: isLowBattery,
      isCharging: isCharging,
    );
  }

  int _estimateIOSRam(String machine) {
    // Estimate RAM based on iOS device model
    if (machine.contains('iPhone14') || machine.contains('iPhone15')) {
      return 6144; // 6GB
    } else if (machine.contains('iPhone13') || machine.contains('iPhone12')) {
      return 4096; // 4GB
    } else if (machine.contains('iPad')) {
      return 8192; // 8GB for most iPads
    }
    return 4096; // Default
  }

  /// Get total device RAM in MB
  Future<int> getTotalRamMB() async {
    final status = await getCurrentStatus();
    return status.totalRamMB;
  }

  /// Get current battery level
  Future<int> getBatteryLevel() async {
    return await _battery.batteryLevel;
  }

  /// Check if device is charging
  Future<bool> isCharging() async {
    final state = await _battery.batteryState;
    return state == BatteryState.charging || state == BatteryState.full;
  }

  /// Check if battery is low (< 20%)
  Future<bool> isLowBattery() async {
    final level = await _battery.batteryLevel;
    return level < lowBatteryThreshold;
  }

  Future<void> dispose() async {
    stopMonitoring();
    await _statusController.close();
  }
}
