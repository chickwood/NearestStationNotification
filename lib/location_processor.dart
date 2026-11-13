import 'dart:async';

import 'package:location/location.dart';

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

  StreamSubscription<LocationData>? _positionSubscription;
  LocationData? _pendingPosition;

  bool _running = false;
  bool _restarting = false;
  bool _restartRequested = false;
  bool _draining = false;

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

  Future<void> start() async {
    _running = true;
    await _startStream();
  }

  Future<void> stop() async {
    _running = false;
    _pendingPosition = null;
    await _stopStream();
  }

  // ── 状態の変更 ──────────────────────────────────────────────────────

  /// 設定更新
  Future<void> changeSettings(ProcessorSettingsManager settings) async {
    final intervalChanged =
        _settingsManager.locationInterval.milliseconds !=
        settings.locationInterval.milliseconds;
    final countChanged =
        _settingsManager.stationCount.count != settings.stationCount.count;
    _settingsManager = settings;

    if (_positionSubscription != null) {
      if (intervalChanged) {
        await _startStream();
      }

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
  Future<void> changeLocale(L10n l10n) async {
    _l10n = l10n;

    // 前台通知テキストを即座反映するため流を再起動
    if (_positionSubscription != null) {
      await _startStream();
    }
  }

  /// 站点数据更新（hot reload）
  /// manager 与 SearchEngine 成对替换（同一同步块，不中断流）
  void changeData(StationManager stationManager) {
    _stationManager = stationManager;
    _searchEngine = SearchEngine(stationManager);
  }

  // ── GPS Stream ───────────────────────────────────────────────────
  /// 流启动/重启：等待旧订阅取消完成，并合并并发重启请求
  Future<void> _startStream() async {
    if (!_running) return;
    if (_restarting) {
      _restartRequested = true;
      return;
    }

    _restarting = true;
    try {
      do {
        _restartRequested = false;

        final distanceFilter = _positionQueue.isNotEmpty
            ? _positionQueue.last.samplingMode.filter
            : SamplingMode.staying.filter;
        final milliseconds = _settingsManager.locationInterval.milliseconds;

        // 必须先等待旧订阅取消完成，再建立新订阅
        final previous = _positionSubscription;
        _positionSubscription = null;
        await previous?.cancel();

        if (!_running) return;

        await Location.instance.changeSettings(
          accuracy: LocationAccuracy.high,
          interval: milliseconds,
          distanceFilter: distanceFilter,
          pausesLocationUpdatesAutomatically: false,
          backgroundInterval: milliseconds,
        );

        await Location.instance.changeNotificationOptions(
          channelName: _l10n.fgnChannelName,
          title: _l10n.fgnNotificationTitle,
          description: _l10n.fgnNotificationBody,
          iconName: Common.flnNotificationIcon,
        );

        await Location.instance.enableBackgroundMode(
          enable: true,
          requireBackgroundPermission: false,
        );

        if (!_running) return;

        _positionSubscription = Location.instance.onLocationChanged.listen(
          _onPosition,
        );
      } while (_restartRequested && _running);
    } finally {
      _restarting = false;
    }
  }

  /// 位置事件单飞：只保留最新未处理位置，避免 async 回调并发操作队列
  void _onPosition(LocationData position) {
    _pendingPosition = position;
    if (_draining) return;

    _draining = true;
    unawaited(_drainPositions());
  }

  Future<void> _drainPositions() async {
    try {
      while (_running) {
        final position = _pendingPosition;
        if (position == null) break;
        _pendingPosition = null;

        if (await _handlePositionUpdated(position) case final positionResult?) {
          _updateSearchResult(positionResult);
        }
      }
    } catch (_) {
    } finally {
      _draining = false;
      if (_running && _pendingPosition != null) _onPosition(_pendingPosition!);
    }
  }

  Future<void> _stopStream() async {
    final previous = _positionSubscription;
    _positionSubscription = null;
    try {
      await previous?.cancel();
    } catch (_) {}

    try {
      await Location.instance.enableBackgroundMode(enable: false);
    } catch (_) {}

    _positionQueue.clear();
  }

  // ── 位置更新処理（GPS Stream）────────────────────────────

  Future<PositionResult?> _handlePositionUpdated(LocationData position) async {
    if (!_running) return null;

    // 基础数据
    final userLatitude = position.latitude;
    final userLongitude = position.longitude;
    final userHeading = position.heading ?? 0.0;
    final rawSpeed = position.speed ?? -1.0;
    final userSpeed = rawSpeed < 0.0 ? 0.0 : rawSpeed;
    final userAccuracy = position.accuracy ?? 0.0;
    final rawTimestamp = position.time ?? -1.0;
    final userTimestamp = rawTimestamp < 0.0
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(rawTimestamp.round());
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
        if (isObserving) await _startStream(); // 重启流
      } else {
        // 最新可信采样点是低速
        // 但是前一个可信采样点是高速
        // 视为进入减速状态
        if (prevMode == SamplingMode.transit) await _startStream(); // 重启流
      }

      // 重启流期间可能已被 stop，避免继续使用被清空的队列
      if (!_running) return null;
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
