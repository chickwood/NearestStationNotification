import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'settings.dart';
import 'common.dart';
import 'l10n.dart';
import 'search_engine.dart';
import 'station_manager.dart';

typedef LocationHandler = void Function(
  PositionResult positionResult,
  List<StationResult> stationResults,
);

/// 位置処理クラス
/// GPS Stream の購読・位置ズレフィルタ・SearchEngine 呼び出しを担う
/// 結果は onLocated コールバックで Coordinator へ渡す
class LocationProcessor {
  L10n _l10n;
  bool _active;
  Settings _settings;
  final StationManager _manager;

  late final SearchEngine _engine;

  // 位置ズレフィルタ用キュー
  static const _queueSize = 3;
  final List<PositionResult> _positionQueue = [];

  StreamSubscription<Position>? _positionSubscription;

  // 結果コールバック（Coordinator が登録）
  LocationHandler? _onLocationUpdated;

  LocationProcessor(this._l10n, this._active, this._settings, this._manager) {
    _engine = SearchEngine(_manager);
  }

  void setLocationHandler(LocationHandler handler) {
    _onLocationUpdated = handler;
  }

  // void _notifyLocationUpdated() {
  //   // noop;
  // }

  // ── 起動・停止 ────────────────────────────────────────────────────

  Future<void> start() async {
    _startStream();
  }

  Future<void> stop() async {
    _stopStream();

    _positionQueue.clear();
  }

  // ── 状態の変更 ──────────────────────────────────────────────────────

  /// 設定更新
  Future<void> changeSettings(Settings settings) async {
    final changeInterval = _settings.locationInterval.milliseconds !=
        settings.locationInterval.milliseconds;
    final changeCount =
        _settings.stationCount.count != settings.stationCount.count;

    _settings = settings;

    if (changeInterval) _startStream();

    if (changeCount) {
      Geolocator.getCurrentPosition().then(
        (position) => _handlePositionUpdated(position, forceUpdate: true),
      );
    }
  }

  /// UI 活動状態の変更
  /// active が false → true になった場合は count 分の再検索が必要
  void changeActive(bool value) {
    final changed = _active != value;
    _active = value;

    if (changed && _active) {
      Geolocator.getCurrentPosition().then(
        (position) => _handlePositionUpdated(position, forceUpdate: true),
      );
    }
  }

  /// 系统语言更新
  void changeLocale(L10n l10n) {
    _l10n = l10n;

    // 前台通知テキストを即座反映するため流を再起動
    if (_positionSubscription != null) _startStream();
  }

  // ── GPS Stream ───────────────────────────────────────────────────

  void _startStream() {
    final distanceFilter = _positionQueue.isNotEmpty
        ? _positionQueue.last.samplingMode.filter
        : SamplingMode.staying.filter;
    final milliseconds = _settings.locationInterval.milliseconds;

    final locationSettings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilter,
          intervalDuration: Duration(milliseconds: milliseconds),
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationChannelName: _l10n.fgtChannelName,
            notificationTitle: _l10n.fgtNotificationTitle,
            notificationText: _l10n.fgtNotificationBody,
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
            .listen((position) => _handlePositionUpdated(position));
  }

  void _stopStream() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  // ── 位置更新処理（GPS Stream）────────────────────────────

  void _handlePositionUpdated(Position position, {bool forceUpdate = false}) {
    // 基础数据
    final userLatitude = position.latitude;
    final userLongitude = position.longitude;
    final userHeading = position.heading;
    final userSpeed = position.speed < 0 ? 0.0 : position.speed;
    var userMode = Common.sampling(userSpeed);

    // 重启流时需要队列里的最后一个采样点
    // 为保证 forceUpdate = true 时处理一致
    // 无论是否可信都先加入
    _positionQueue.add(PositionResult(
      latitude: userLatitude,
      longitude: userLongitude,
      speed: userSpeed,
      accuracy: position.accuracy,
      heading: userHeading,
      timestamp: position.timestamp,
    ));

    if (!forceUpdate) {
      // 采样点已有 2 个以上（亦即添加最新的采样点之前已有 1 个以上）
      if (_positionQueue.length > 1) {
        final prevPosition = _positionQueue[_positionQueue.length - 2];

        // 方形过滤
        // 认为是 GPS 漂移
        if (Common.near(
          userLatitude,
          userLongitude,
          prevPosition.latitude,
          prevPosition.longitude,
        )) {
          // 删除最后进入队列的不可信采样点
          _positionQueue.removeLast();
          return;
        }

        // 仅当定位频率为 1s 时
        // 采样点已有 3 个（亦即添加最新的采样点之前已有 2 个）
        // 触发观察者模式检测
        final prevMode = Common.sampling(prevPosition.speed);
        var isObserving = _positionQueue.length > 2 &&
            prevMode == SamplingMode.transit &&
            Common.sampling(_positionQueue[_positionQueue.length - 3].speed) !=
                SamplingMode.transit;
        if (_settings.locationInterval == LocationInterval.s1 && isObserving) {
          // 下一次定位又变为低速或静止
          // 认为是 GPS 漂移
          if (userMode != SamplingMode.transit) {
            // 删除最后进入队列的不可信采样点
            _positionQueue.removeLast();
            // 删除前一个 GPS 漂移的不可信采样点
            _positionQueue.removeLast();
            return;
          }

          // 方向突变判断
          final prevHeading = prevPosition.heading;
          final dHeading = userHeading - prevHeading;
          // 两次采样转向超过 45 度
          // 认为是 GPS 漂移
          if ((dHeading > 45 && dHeading < 315) ||
              (dHeading < -45 && dHeading > -315)) {
            // 删除最后进入队列的不可信采样点
            _positionQueue.removeLast();
            // 删除前一个 GPS 漂移的不可信采样点
            _positionQueue.removeLast();
            return;
          }
        }

        if (userMode != SamplingMode.transit) {
          // 最后进入队列的可信采样点是低速
          // 前一个可信采样点是高速
          if (prevMode == SamplingMode.transit) _startStream(); // 重启流
        } else {
          // 最后进入队列的可信采样点是高速
          // 触发并通过观察者模式检测
          if (isObserving) _startStream(); // 重启流
        }
      }
    }

    while (_positionQueue.length > _queueSize) {
      _positionQueue.removeAt(0);
    }
    final positionResult = _positionQueue.last;
    // 取得车站数全部在 engine 内进行分歧判断
    // 取得最小车站数后再填入其他属性返回最小数据集
    final stationResults = _engine
        .locate(
          userLatitude,
          userLongitude,
          _settings.stationCount.count,
          _active,
        )
        .toList(growable: false);

    // _onLocated?.call 的写法更为简洁直观
    // if case 的写法是为了和 coordinator 中的 _notify 统一
    // _onLocated?.call(positionResult, stationResults);
    if (_onLocationUpdated case final handler?) {
      handler(positionResult, stationResults);
    }
  }
}
