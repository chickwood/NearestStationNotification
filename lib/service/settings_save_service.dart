import 'package:flutter/foundation.dart';

import '../manager/settings_manager.dart';

// ── Settings Save Service ──────────────────────────────────────────

class SettingsSaveResult {
  final SettingsManager? settings;
  final Object? error;

  const SettingsSaveResult._({this.settings, this.error})
    : assert(
        (settings == null) != (error == null),
        'exactly one of settings / error must be set',
      );

  factory SettingsSaveResult.success(SettingsManager settings) =>
      SettingsSaveResult._(settings: settings);

  factory SettingsSaveResult.failure(Object error) =>
      SettingsSaveResult._(error: error);

  bool get succeeded => error == null;
}

/// SettingsManager.save() 的异步执行与结果持有者，
/// 生命周期独立于 SettingsDialog。
class SettingsSaveService {
  final ValueNotifier<SettingsSaveResult?> lastResult = ValueNotifier(null);
  final ValueNotifier<bool> busy = ValueNotifier(false);

  Future<void> save(SettingsManager settings) async {
    if (busy.value) return;

    busy.value = true;
    try {
      await settings.save();
      lastResult.value = SettingsSaveResult.success(settings);
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      lastResult.value = SettingsSaveResult.failure(e);
    } finally {
      busy.value = false;
    }
  }

  void dispose() {
    lastResult.dispose();
    busy.dispose();
  }
}
