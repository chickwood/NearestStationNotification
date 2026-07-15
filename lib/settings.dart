import 'package:shared_preferences/shared_preferences.dart';

import 'common.dart';

// ── SharedPreferences キー ────────────────────────────────────────

class _Keys {
  static const stationCount = 'settings_station_count';
  static const locationInterval = 'settings_location_interval';
  // static const notificationMode = 'settings_notification_mode';
}

// ── AppSettings ───────────────────────────────────────────────────

class Settings {
  StationCount stationCount;
  LocationInterval locationInterval;
  // NotificationMode notificationMode;

  Settings._({
    this.stationCount = StationCount.game,
    this.locationInterval = LocationInterval.s1,
    // this.notificationMode = NotificationMode.location,
  });

  @override
  String toString() {
    return "station_count: ${stationCount.count}, location_interval: ${locationInterval.milliseconds}";
  }

  // 从 SharedPreferences 读取
  static Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();

    return Settings.fromTransferable([
      prefs.getInt(_Keys.stationCount) ?? StationCount.game.index,
      prefs.getInt(_Keys.locationInterval) ?? LocationInterval.s1.index,
      // prefs.getInt(_Keys.notificationMode) ?? NotificationMode.location.index,
    ]);
  }

  // 写入 SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_Keys.stationCount, stationCount.index);
    await prefs.setInt(_Keys.locationInterval, locationInterval.index);
    // await prefs.setInt(_Keys.notificationMode, notificationMode.index);
  }

  // 复制（用于弹窗内的临时副本）
  Settings copyWith({
    StationCount? stationCount,
    LocationInterval? locationInterval,
    // NotificationMode? notificationMode,
  }) {
    return Settings.fromTransferable([
      stationCount?.index ?? this.stationCount.index,
      locationInterval?.index ?? this.locationInterval.index,
      // notificationMode?.index ?? this.notificationMode.index,
    ]);
  }

  // toTransferable
  List<int> toTransferable() => [
        stationCount.index,
        locationInterval.index,
        // notificationMode.index,
      ];

  // fromTransferable
  factory Settings.fromTransferable(List data) => Settings._(
        stationCount: StationCount.values.elementAtOrNull(data[0] as int) ??
            StationCount.game,
        locationInterval:
            LocationInterval.values.elementAtOrNull(data[1] as int) ??
                LocationInterval.s1,
        // notificationMode:
        //     NotificationMode.values.elementAtOrNull(data[2] as int) ??
        //         NotificationMode.location,
      );
}
