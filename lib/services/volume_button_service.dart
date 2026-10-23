// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'package:flutter/services.dart';
import 'storage_service.dart';
import 'emergency_service.dart';
import 'hardware_service.dart';

class VolumeButtonService {
  static const MethodChannel _channel =
      MethodChannel('com.aprajita.aprajita_app/volume_sos');

  final StorageService _storageService;
  final EmergencyService _emergencyService;
  final HardwareService _hardwareService;

  int _pressCount = 0;
  DateTime? _lastFlutterPressTime;
  Timer? _flutterResetTimer;

  final StreamController<int> _pressCountController =
      StreamController<int>.broadcast();

  Stream<int> get pressCountStream => _pressCountController.stream;
  int get currentPressCount => _pressCount;

  VolumeButtonService({
    required StorageService storageService,
    required EmergencyService emergencyService,
    required HardwareService hardwareService,
  })  : _storageService = storageService,
        _emergencyService = emergencyService,
        _hardwareService = hardwareService {
    _initChannel();
    _initKeyboardListener();
  }

  void _initChannel() {
    _channel.setMethodCallHandler((call) async {
      if (!_storageService.isVolumeSosEnabled()) return;

      switch (call.method) {
        case 'onVolumePressCountChanged':
          final count = (call.arguments as Map?)?['count'] as int? ?? 0;
          _onPressDetected(count);
          break;

        case 'onVolumeSosTriggered':
          _triggerSos();
          break;
      }
    });
  }

  void _onPressDetected(int count) {
    _pressCount = count;
    _pressCountController.add(_pressCount);

    if (count > 0 && count < 4) {
      // Escalating tactile pulses confirm each consecutive hardware click
      if (count == 1) {
        HapticFeedback.lightImpact();
      } else if (count == 2) {
        HapticFeedback.mediumImpact();
      } else if (count == 3) {
        HapticFeedback.heavyImpact();
      }
      _hardwareService.logTerminal(
          '🔊 Physical Volume Up button pressed ($count/4)...');
    }
  }

  void _triggerSos() {
    HapticFeedback.vibrate();
    _pressCount = 0;
    _pressCountController.add(0);

    _hardwareService.logTerminal(
        '🚨 4-CLICK VOLUME UP DETECTED! Automatically triggering Emergency SOS...');

    if (!_emergencyService.isSosActive) {
      _emergencyService.triggerInstantSos(source: 'PHONE_VOLUME_UP_4PRESS');
    }
  }

  // Fallback keyboard listener in Flutter framework
  void _initKeyboardListener() {
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_storageService.isVolumeSosEnabled()) return false;

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
      final now = DateTime.now();

      if (_lastFlutterPressTime == null ||
          now.difference(_lastFlutterPressTime!).inMilliseconds > 3500) {
        _pressCount = 0;
      }

      _lastFlutterPressTime = now;
      _pressCount++;

      _flutterResetTimer?.cancel();
      _flutterResetTimer = Timer(const Duration(milliseconds: 3500), () {
        _pressCount = 0;
        _pressCountController.add(0);
      });

      _onPressDetected(_pressCount);

      if (_pressCount >= 4) {
        _flutterResetTimer?.cancel();
        _triggerSos();
      }
      return true;
    }
    return false;
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _flutterResetTimer?.cancel();
    _pressCountController.close();
  }
}
