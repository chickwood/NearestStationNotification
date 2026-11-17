import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'common.dart';
import 'l10n.dart';
import 'manager/settings_manager.dart';
import 'manager/station_manager.dart';
import 'search_engine.dart';

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
  StationManager _stationManager;
  ProcessorSettingsManager _settingsManager;

  late SearchEngine _searchEngine;

  // 位置ズレフィルタ用キュー
  static const _queueSize = 3;
  final List<PositionResult> _positionQueue = [];

  StreamSubscription<Position>? _positionSubscription;

  // 前台通知配置：仅语言变化时重建，其他流重启复用
  ForegroundNotificationConfig? _foregroundNotificationConfig;

  // 結果コールバック（Coordinator が登録）
  LocationHandler? _onLocationUpdated;

  LocationProcessor(
    this._l10n,
    this._active,
    this._stationManager,
    this._settingsManager,
  ) {
    _searchEngine = SearchEngine(_stationManager);
  }

  void setLocationHandler(LocationHandler handler) {
    _onLocationUpdated = handler;
  }

  // ── 起動・停止 ────────────────────────────────────────────────────

  void start() {
    _startStream();
  }

  void stop() {
    _stopStream();
  }

  // ── 状態の変更 ──────────────────────────────────────────────────────

  /// 設定更新
  void changeSettings(ProcessorSettingsManager settings) {
    final intervalChanged =
        _settingsManager.locationInterval.milliseconds !=
        settings.locationInterval.milliseconds;
    final countChanged =
        _settingsManager.stationCount.count != settings.stationCount.count;
    _settingsManager = settings;

    if (_positionSubscription != null) {
      if (intervalChanged) _startStream();

      if (countChanged) {
        if (_positionQueue case [..., final last]) {
          _updateSearchResult(last);
        }
      }
    }
  }

  /// UI 活動状態の変更
  /// active が false → true になった場合は count 分の再検索が必要
  void changeActive(bool active) {
    final activeChanged = _active != active;
    _active = active;

    if (_positionSubscription != null) {
      if (activeChanged && _active) {
        if (_positionQueue case [..., final last]) {
          _updateSearchResult(last);
        }
      }
    }
  }

  /// 系统语言更新
  void changeLocale(L10n l10n) {
    _l10n = l10n;
    _foregroundNotificationConfig = _buildForegroundNotificationConfig();

    if (_positionSubscription == null) return;

    // 新的通知配置を反映するため一度だけ流を再起動する
    _startStream();
  }

  /// 站点数据更新（hot reload）
  /// manager 与 SearchEngine 成对替换（同一同步块，不中断流）
  void changeData(StationManager stationManager) {
    _stationManager = stationManager;
    _searchEngine = SearchEngine(stationManager);
  }

  // ── GPS Stream ───────────────────────────────────────────────────
  ForegroundNotificationConfig _buildForegroundNotificationConfig() {
    return ForegroundNotificationConfig(
      notificationChannelName: _l10n.fgnChannelName,
      notificationTitle: _l10n.fgnNotificationTitle,
      notificationText: _l10n.fgnNotificationBody,
      notificationIcon: const AndroidResource(
        name: Common.flnNotificationIcon,
        defType: 'drawable',
      ),
      enableWakeLock: true,
    );
  }

  LocationSettings _buildLocationSettings(
    int milliseconds,
    int distanceFilter,
  ) {
    final foregroundNotificationConfig = _foregroundNotificationConfig ??=
        _buildForegroundNotificationConfig();

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        intervalDuration: Duration(milliseconds: milliseconds),
        foregroundNotificationConfig: foregroundNotificationConfig,
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
  }

  void _clearStream() {
    try {
      final previous = _positionSubscription;
      _positionSubscription = null;
      unawaited(previous?.cancel().catchError((_) {}));
    } catch (_) {}
  }

  /// 流启动/重启：丢弃旧订阅后立即建立新订阅
  void _startStream() {
    final distanceFilter = _positionQueue.isNotEmpty
        ? _positionQueue.last.samplingMode.filter
        : SamplingMode.staying.filter;
    final milliseconds = _settingsManager.locationInterval.milliseconds;

    _clearStream();

    try {
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: _buildLocationSettings(milliseconds, distanceFilter),
      ).listen(_onPosition, onError: (_) => _clearStream());
    } catch (_) {}
  }

  void _stopStream() {
    _clearStream();
    _positionQueue.clear();
  }

  /// 位置イベント：処理は同期のみなので、その場で完結させる
  /// 例外で流れが止まらないよう境界で握りつぶす
  void _onPosition(Position position) {
    try {
      if (_handlePositionUpdated(position) case final result?) {
        _updateSearchResult(result);
      }
    } catch (_) {}
  }

  // ── 位置更新処理（GPS Stream）────────────────────────────

  /// 同期処理に限定する
  PositionResult? _handlePositionUpdated(Position position) {
    // 基础数据
    final userLatitude = position.latitude;
    final userLongitude = position.longitude;
    final userHeading = position.heading;
    final userSpeed = position.speed < 0.0 ? 0.0 : position.speed;
    final userAccuracy = position.accuracy;
    final userTimestamp = position.timestamp;

    var userMode = Common.sampling(userSpeed);

    // 最新采样点先进入队列
    // 再进行可信性判断
    _positionQueue.add(
      PositionResult(
        latitude: userLatitude,
        longitude: userLongitude,
        speed: userSpeed,
        accuracy: userAccuracy,
        heading: userHeading,
        timestamp: userTimestamp,
      ),
    );

    // 采样点已有 2 个以上（亦即添加最新采样点之前已有 1 个以上）
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
        return null;
      }

      // 仅当定位频率为 1s 时
      // 采样点已有 3 个（亦即添加最新采样点之前已有 2 个）
      // 触发观察者模式检测
      final prevMode = Common.sampling(prevPosition.speed);
      var isObserving =
          _positionQueue.length > 2 &&
          prevMode == SamplingMode.transit &&
          Common.sampling(_positionQueue[_positionQueue.length - 3].speed) !=
              SamplingMode.transit;
      if (_settingsManager.locationInterval == LocationInterval.s1 &&
          isObserving) {
        // 下一次定位又变为低速或静止
        // 认为是 GPS 漂移
        if (userMode != SamplingMode.transit) {
          // 删除最后进入队列的不可信采样点
          _positionQueue.removeLast();
          // 删除前一个 GPS 漂移的不可信采样点
          _positionQueue.removeLast();
          return null;
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
          return null;
        }
      }

      if (userMode == SamplingMode.transit) {
        // 最新可信采样点是高速
        // 并且当前处于观察者模式
        // 视为进入加速状态或者高速稳定状态
        if (isObserving) _startStream(); // 重启流
      } else {
        // 最新可信采样点是低速
        // 但是前一个可信采样点是高速
        // 视为进入减速状态
        if (prevMode == SamplingMode.transit) _startStream(); // 重启流
      }
    }

    while (_positionQueue.length > _queueSize) {
      _positionQueue.removeAt(0);
    }

    if (_positionQueue.isEmpty) return null;
    return _positionQueue.last;
  }

  void _updateSearchResult(PositionResult positionResult) {
    // 取得车站数全部在 engine 内进行分歧判断
    // 取得最小车站数后再填入其他属性返回最小数据集
    final stationResults = _searchEngine
        .locate(
          positionResult.latitude,
          positionResult.longitude,
          _settingsManager.stationCount.count,
          _active,
        )
        .toList(growable: false);

    if (_onLocationUpdated case final handler?) {
      handler(positionResult, stationResults);
    }
  }
}
