import 'package:shared_preferences/shared_preferences.dart';

import '../common.dart';

// ── SharedPreferences キー ────────────────────────────────────────

class _Keys {
  static const stationCount = 'settings_station_count';
  static const locationInterval = 'settings_location_interval';
  // static const notificationMode = 'settings_notification_mode';
  static const historyEnabled = 'settings_history_enabled';
  static const historyMergeView = 'settings_history_merge_view';
}

// ── 消费者ごとの設定ビュー ─────────────────────────────────────────

/// LocationProcessor が使う設定だけを公開する
typedef ProcessorSettingsManager =
    ({StationCount stationCount, LocationInterval locationInterval});

/// 履歴機能が使う設定だけを公開する
typedef HistorySettingsManager = ({bool historyEnabled, bool historyMergeView});

// ── SettingsManager ───────────────────────────────────────────────────

class SettingsManager {
  StationCount stationCount;
  LocationInterval locationInterval;
  // NotificationMode notificationMode;
  bool historyEnabled;
  bool historyMergeView;

  SettingsManager._({
    this.stationCount = StationCount.game,
    this.locationInterval = LocationInterval.s1,
    // this.notificationMode = NotificationMode.location,
    this.historyEnabled = false,
    this.historyMergeView = false,
  });

  /// LocationProcessor 向けの読み取り専用ビュー
  ProcessorSettingsManager get processorSettingsManager => (
    stationCount: stationCount,
    locationInterval: locationInterval,
  );

  /// 履歴機能向けの読み取り専用ビュー
  HistorySettingsManager get historySettingsManager => (
    historyEnabled: historyEnabled,
    historyMergeView: historyMergeView,
  );

  @override
  String toString() {
    return "station_count: ${stationCount.count}, location_interval: ${locationInterval.milliseconds}, history_enabled: $historyEnabled, history_merge_view: $historyMergeView";
  }

  // 从 SharedPreferences 读取
  static Future<SettingsManager> load() async {
    final prefs = await SharedPreferences.getInstance();

    return SettingsManager.fromTransferable([
      prefs.getInt(_Keys.stationCount) ?? StationCount.game.index,
      prefs.getInt(_Keys.locationInterval) ?? LocationInterval.s1.index,
      // prefs.getInt(_Keys.notificationMode) ?? NotificationMode.location.index,
      prefs.getBool(_Keys.historyEnabled) ?? false,
      prefs.getBool(_Keys.historyMergeView) ?? false,
    ]);
  }

  // 写入 SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_Keys.stationCount, stationCount.index);
    await prefs.setInt(_Keys.locationInterval, locationInterval.index);
    // await prefs.setInt(_Keys.notificationMode, notificationMode.index);
    await prefs.setBool(_Keys.historyEnabled, historyEnabled);
    await prefs.setBool(_Keys.historyMergeView, historyMergeView);
  }

  // 复制（用于弹窗内的临时副本）
  SettingsManager copyWith({
    StationCount? stationCount,
    LocationInterval? locationInterval,
    // NotificationMode? notificationMode,
    bool? historyEnabled,
    bool? historyMergeView,
  }) {
    return SettingsManager.fromTransferable([
      stationCount?.index ?? this.stationCount.index,
      locationInterval?.index ?? this.locationInterval.index,
      // notificationMode?.index ?? this.notificationMode.index,
      historyEnabled ?? this.historyEnabled,
      historyMergeView ?? this.historyMergeView,
    ]);
  }

  // // toTransferable（暂存，未来可能用于持久化，当前无调用）
  // List<int> toTransferable() => [
  //       stationCount.index,
  //       locationInterval.index,
  //       // notificationMode.index,
  //     ];

  // fromTransferable
  factory SettingsManager.fromTransferable(List data) => SettingsManager._(
    stationCount:
        StationCount.values.elementAtOrNull(data[0] as int) ??
        StationCount.game,
    locationInterval:
        LocationInterval.values.elementAtOrNull(data[1] as int) ??
        LocationInterval.s1,
    // notificationMode:
    //     NotificationMode.values.elementAtOrNull(data[2] as int) ??
    //         NotificationMode.location,
    historyEnabled: data.length > 2 && data[2] == true,
    historyMergeView: data.length > 3 && data[3] == true,
  );
}
