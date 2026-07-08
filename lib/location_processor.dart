import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'app_settings.dart';
import 'common.dart';
import 'search_engine.dart';

/// 位置処理クラス
/// GPS Stream の購読・漂移フィルタ・SearchEngine 呼び出しを担う
class LocationProcessor {
  AppSettings? _settings;
  SearchEngine? _engine;

  StreamSubscription<Position>? _positionSubscription;

  // 漂移フィルタ用キュー
  static const _queueSize = 3;
  final List<PositionResult> _positionQueue = [];

  // 結果コールバック（NotificationService が登録）
  final void Function(PositionResult, List<StationResult>) onLocated;

  // 前台通知テキスト（NotificationService から注入）
  String foregroundNotificationTitle;
  String foregroundNotificationBody;

  LocationProcessor({
    required this.onLocated,
    required this.foregroundNotificationTitle,
    required this.foregroundNotificationBody,
  });

  // ── 起動・停止 ────────────────────────────────────────────────────

  Future<void> start(AppSettings settings, SearchEngine engine) async {
    _settings = settings;
    _engine = engine;
    _startStream();
  }

  Future<void> stop() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _positionQueue.clear();
    _settings = null;
    _engine = null;
  }

  // ── 設定更新 ──────────────────────────────────────────────────────

  Future<void> changeSettings(AppSettings settings) async {
    final changeInterval = _settings?.locationInterval.milliseconds !=
        settings.locationInterval.milliseconds;
    final changeCount =
        _settings?.stationCount.count != settings.stationCount.count;

    _settings = settings;

    if (changeInterval) _startStream();

    if (changeCount) {
      Geolocator.getCurrentPosition().then(
        (position) => _handlePositionUpdate(position, forceUpdate: true),
      );
    }
  }

  // ── GPS Stream ───────────────────────────────────────────────────

  void _startStream() {
    final distanceFilter = _positionQueue.isNotEmpty
        ? _positionQueue.last.samplingMode.filter
        : SamplingMode.staying.filter;
    final milliseconds = _settings?.locationInterval.milliseconds ??
        LocationInterval.s1.milliseconds;

    final locationSettings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilter,
          intervalDuration: Duration(milliseconds: milliseconds),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: foregroundNotificationTitle,
            notificationText: foregroundNotificationBody,
            notificationIcon: const AndroidResource(
              name: Common.flnNotificationIcon,
              defType: 'drawable',
            ),
            enableWakeLock: true,
          ),
        ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: distanceFilter,
          activityType: ActivityType.otherNavigation,
          showBackgroundLocationIndicator: true,
        ),
      _ => LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilter,
        ),
    };

    _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((position) => _handlePositionUpdate(position));
  }

  // ── 位置更新処理 ──────────────────────────────────────────────────

  void _handlePositionUpdate(Position position, {bool forceUpdate = false}) {
    final userLatitude = position.latitude;
    final userLongitude = position.longitude;
    final userHeading = position.heading;
    final userSpeed = position.speed < 0 ? 0.0 : position.speed;
    var userMode = Common.sampling(userSpeed);

    _positionQueue.add(PositionResult(
      latitude: userLatitude,
      longitude: userLongitude,
      speed: userSpeed,
      accuracy: position.accuracy,
      heading: userHeading,
      timestamp: position.timestamp,
    ));

    if (!forceUpdate) {
      if (_positionQueue.length > 1) {
        final prevPosition = _positionQueue[_positionQueue.length - 2];

        // 方形过滤
        if (Common.near(
          userLatitude,
          userLongitude,
          prevPosition.latitude,
          prevPosition.longitude,
        )) {
          _positionQueue.removeLast();
          return;
        }

        // 観察者モード検出
        final prevMode = Common.sampling(prevPosition.speed);
        var isObserving = _positionQueue.length > 2 &&
            prevMode == SamplingMode.transit &&
            Common.sampling(_positionQueue[_positionQueue.length - 3].speed) !=
                SamplingMode.transit;
        if (_settings?.locationInterval == LocationInterval.s1 && isObserving) {
          if (userMode != SamplingMode.transit) {
            _positionQueue.removeLast();
            _positionQueue.removeLast();
            return;
          }

          final prevHeading = prevPosition.heading;
          final dHeading = userHeading - prevHeading;
          if ((dHeading > 45 && dHeading < 315) ||
              (dHeading < -45 && dHeading > -315)) {
            _positionQueue.removeLast();
            _positionQueue.removeLast();
            return;
          }
        }

        if (userMode != SamplingMode.transit) {
          if (prevMode == SamplingMode.transit) _startStream();
        } else {
          if (isObserving) _startStream();
        }
      }
    }

    while (_positionQueue.length > _queueSize) {
      _positionQueue.removeAt(0);
    }

    final positionResult = _positionQueue.last;
    final stationResults = _engine!
        .locate(
          userLatitude,
          userLongitude,
          _settings?.stationCount.count ?? 0,
          true,
        )
        .toList(growable: false);

    onLocated(positionResult, stationResults);
  }
}
