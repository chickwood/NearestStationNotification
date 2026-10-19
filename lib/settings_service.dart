import 'package:flutter/foundation.dart';

import 'settings.dart';

// ── Settings Service ───────────────────────────────────────────────

sealed class SettingsSaveResult {
  const SettingsSaveResult();
}

class SettingsSaved extends SettingsSaveResult {
  final Settings settings;

  const SettingsSaved(this.settings);
}

class SettingsSaveFailed extends SettingsSaveResult {
  final Object error;

  const SettingsSaveFailed(this.error);
}

/// Settings.save() 的异步执行与结果持有者，
/// 生命周期独立于 SettingsDialog。
class SettingsService {
  final ValueNotifier<SettingsSaveResult?> lastResult = ValueNotifier(null);
  final ValueNotifier<bool> busy = ValueNotifier(false);

  Future<void> save(Settings settings) async {
    if (busy.value) return;

    busy.value = true;
    try {
      await settings.save();
      lastResult.value = SettingsSaved(settings);
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      lastResult.value = SettingsSaveFailed(e);
    } finally {
      busy.value = false;
    }
  }

  void dispose() {
    lastResult.dispose();
    busy.dispose();
  }
}
