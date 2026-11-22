import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges to the Android foreground service that keeps photo/video backups
/// alive when the screen is off or the app is in the background.
class BackgroundBackup {
  static const MethodChannel _channel = MethodChannel('fit.flutter.dsm_helper/background_backup');
  static bool _started = false;

  static bool get isStarted => _started;

  static Future<bool> start({String title = '相册备份', String text = '正在后台备份，请勿关闭通知'}) async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      final bool ok = await _channel.invokeMethod('start', {
        'title': title,
        'text': text,
      }) ??
          false;
      _started = ok;
      return ok;
    } catch (e) {
      debugPrint('BackgroundBackup.start failed: $e');
      return false;
    }
  }

  static Future<void> update({String title = '相册备份', String text = '', int progress = -1}) async {
    if (!Platform.isAndroid || !_started) {
      return;
    }
    try {
      await _channel.invokeMethod('update', {
        'title': title,
        'text': text,
        'progress': progress,
      });
    } catch (e) {
      debugPrint('BackgroundBackup.update failed: $e');
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }
    _started = false;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('BackgroundBackup.stop failed: $e');
    }
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      return await _channel.invokeMethod('isIgnoringBatteryOptimizations') ?? false;
    } catch (e) {
      debugPrint('BackgroundBackup.isIgnoringBatteryOptimizations failed: $e');
      return true;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _channel.invokeMethod('requestIgnoreBatteryOptimizations') ?? false;
    } catch (e) {
      debugPrint('BackgroundBackup.requestIgnoreBatteryOptimizations failed: $e');
      return false;
    }
  }
}
