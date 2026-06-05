import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'app_settings.dart';
import 'common.dart';
import 'search_engine.dart';

/// Task Isolate 処理器
/// GPS Stream → Engine → Manager → sendDataToMain
class LocationTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _positionSubscription;

  // ── 字段区 ───────────────────────────────────────────────────────

  static const _queueSize = 3;
  final List<PositionResult> _positionQueue = [];
  // PositionResult? get _lastPosition =>
  //     _positionQueue.isEmpty ? null : _positionQueue.last;

  bool? _active;
  AppSettings? _settings;
  SearchEngine? _engine;

  // ── TaskHandler overrides ────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      _active = true;

      // getData
      _settings =
          switch (await FlutterForegroundTask.getData(key: 'settings')) {
        final raw? => AppSettings.fromTransferable(jsonDecode(raw) as List),
        _ => await AppSettings.load(),
      };

      _engine = await SearchEngine.load();

      _startStream();

      // 回传主线程
      // 告诉主线程 Task 已就绪
      FlutterForegroundTask.sendDataToMain({
        'ready': 'ready',
      });
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _active = null;
    _settings = null;
    _engine = null;

    _positionQueue.clear();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // GPS Stream・Timer 自驱动
    // 心跳无需额外操作
  }

  @override
  void onReceiveData(Object data) async {
    // super.onReceiveData(data);

    try {
      var change = false;

      switch (data) {
        case {'active': final bool active}:
          final changeActive = _active != active;
          _active = active;

          // active 变为 true 时需要按 count 重新搜索
          change = changeActive && _active!;
          break;
        case {'settings': final List settingsData}:
          final settings = AppSettings.fromTransferable(settingsData);

          final changeInterval = _settings?.locationInterval.milliseconds !=
              settings.locationInterval.milliseconds;
          final changeCount =
              _settings?.stationCount.count != settings.stationCount.count;
          _settings = settings;

          // Interval 更新时重启流
          if (changeInterval) _startStream();

          // Count 更新时重新定位和搜索
          change = changeCount;
          break;
      }

      if (change) {
        Geolocator.getCurrentPosition()
            .then((position) => _handlePositionUpdate(
                  position,
                  forceUpdate: true,
                ));
      }
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    }
  }

  // ── GPS Stream ───────────────────────────────────────────────────

  void _startStream() {
    final distanceFilter = _positionQueue.isNotEmpty
        ? _positionQueue.last.samplingMode.filter
        : SamplingMode.staying.filter;
    final milliseconds = _settings?.locationInterval.milliseconds ??
        LocationInterval.s5.milliseconds;
    var locationSettings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilter,
          intervalDuration: Duration(milliseconds: milliseconds),
        ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: distanceFilter,
          activityType: ActivityType.otherNavigation,
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

  // ── 位置更新処理（GPS Stream）────────────────────────────

  void _handlePositionUpdate(Position position, {bool forceUpdate = false}) {
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
        if (_settings?.locationInterval == LocationInterval.s1 && isObserving) {
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
    final positionResult = _positionQueue.last.toTransferable();

    // 取得车站数全部在 engine 内进行分歧判断
    // 取得最小车站数后再填入其他属性返回最小数据集
    final stationResults = _engine!
        .locate(
          userLatitude,
          userLongitude,
          _settings?.stationCount.count ?? 0,
          _active ?? false,
        )
        .map((result) => result.toTransferable())
        .toList(growable: false);

    final payload = {
      'position_result': positionResult,
      'station_results': stationResults,
    };

    // 回传主线程
    // 通知栏更新由主线程 NotificationService 负责
    FlutterForegroundTask.sendDataToMain(payload);
  }
}
