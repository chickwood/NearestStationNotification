import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import 'app_settings.dart';
import 'common.dart';
import 'l10n.dart';
import 'location_task_handler.dart';

/// 定位服务
/// 主线程空壳
/// FGT の起停・権限・UI コールバックの管理を担う
/// 業務通知は FLN が担う
/// GPS 計算は LocationTaskHandler (Task Isolate) が担う
class NotificationService {
  AppLocalizations _l10n;

  bool _active = true; // 前台=true，后台(paused)=false
  bool _isNotificationUpdating = false;

  PositionResult? _positionResult;
  List<StationResult>? _serviceResults;
  StationResult? _lastNearestResult; // 最近车站切换检测用

  // UI コールバック
  Function(PositionResult?, List<StationResult>?)? _onLocated;
  Function(RunningStatus)? _onRunningStatusChanged;
  // AppSettings? _settings;

  // ── FLN ─────────────────────────────────────────────────────────
  final _fln = FlutterLocalNotificationsPlugin();

  NotificationService(this._l10n);

  // ── 初期化 ──────────────────────────────────────────────────────

  /// アプリ起動時に呼び出初期化処理
  Future<void> initService() async {
    // FGT 初期化
    // channelImportance を HIGH に設定して一回表示で非表示を促す
    // ユーザーはシステム設定からこのチャンネルを非表示にすることができる
    _fgt.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: Common.fgtChannelId,
        channelName: _l10n.fgtChannelName,
        channelDescription: _l10n.fgtChannelDescription,
        channelImportance: NotificationChannelImportance.HIGH,
        playSound: false,
        showBadge: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(), // repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
        stopWithTask: false,
      ),
    );

    // FLN 初期化
    await _fln.initialize(
      settings: InitializationSettings(
        android: AndroidInitializationSettings(
          Common.flnNotificationIcon, // drawable リソース名
        ),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false, // 权限在 startLocating 时请求
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    // 冷启动清理
    // 若 FGT 服务仍在运行则停止
    if (await _fgt.isRunningService) {
      _fgt.removeTaskDataCallback(_onReceiveTaskData);
      await _fgt.stopService();
    }

    // 冷启动清理
    // 取消可能残留的业务通知
    await _fln.cancelAll();
  }

  // ── タスク制御 ────────────────────────────────────────────────────

  /// 开始定位
  Future<void> startLocating(
    AppSettings settings, {
    Function(PositionResult?, List<StationResult>?)? onLocated,
    Function(RunningStatus)? onRunningStatusChanged,
  }) async {
    // 权限
    _onRunningStatusChanged = onRunningStatusChanged;
    if (!await _requestLocationPermissions() ||
        !await _requestNotificationPermissions()) {
      _onRunningStatusChanged?.call(RunningStatus.stopped);
      _onRunningStatusChanged = null;
      return;
    }

    _onLocated = onLocated;
    // _settings = settings;

    if (await _fgt.isRunningService) {
      await _fgt.restartService();
    } else {
      _fgt.addTaskDataCallback(_onReceiveTaskData);

      final payload = {
        'settings': settings.toTransferable(),
      };
      await _fgt.saveData(
        key: payload.keys.first,
        value: jsonEncode(payload.values.first),
      );

      await _fgt.startService(
        serviceId: Common.fgtNotificationId,
        serviceTypes: [ForegroundServiceTypes.location],
        notificationTitle: _l10n.fgtNotificationTitle,
        notificationText: _l10n.fgtNotificationBody,
        notificationIcon: const NotificationIcon(
          metaDataName: Common.fgtNotificationIconMetaDataName,
        ),
        callback: startCallback,
      );
    }

    // _onRunningStatusChanged?.call(RunningStatus.running);
  }

  // 停止定位
  Future<void> stopLocating() async {
    _fgt.removeTaskDataCallback(_onReceiveTaskData);
    await _fgt.stopService();

    await _fln.cancelAll();

    _positionResult = null;
    _serviceResults = null;
    _lastNearestResult = null;

    _onRunningStatusChanged?.call(RunningStatus.stopped);
    _onRunningStatusChanged = null;

    _onLocated?.call(null, null);
    _onLocated = null;

    // _settings = null;
  }

  /// UI 进入后台
  /// 停止向 UI 推送数据
  Future<void> changeAppLifecycleState(AppLifecycleState state) async {
    final active = switch (state) {
      AppLifecycleState.paused => false,
      AppLifecycleState.resumed => true,
      _ => _active,
    };

    if (active != _active) {
      _active = active;

      // 恢复显示时立刻更新列表
      // 避免长期拿不到GPS更新时显示旧数据
      // 即便此时缓存中应该只有通知栏当前 1 条数据
      if (_active) {
        _onLocated?.call(_positionResult, _serviceResults);
      }

      if (await _fgt.isRunningService) {
        final payload = {
          'active': _active,
        };
        _fgt.sendDataToTask(payload);
        // FGT.sendDataToMain 会引发 _updateNotification
        // 不需要明示调用
        // unawaited(_updateNotification());
      }
    }
  }

  // 系统语言更新
  void changeLocale(AppLocalizations l10n) {
    _l10n = l10n;

    unawaited(_updateNotification(forceUpdate: true));
  }

  Future<void> changeSettings(AppSettings settings) async {
    // _settings = settings;

    if (await _fgt.isRunningService) {
      final payload = {
        'settings': settings.toTransferable(),
      };
      await _fgt.saveData(
        key: payload.keys.first,
        value: jsonEncode(payload.values.first),
      );
      _fgt.sendDataToTask(payload);
      // FGT.sendDataToMain 会引发 _updateNotification
      // 不需要明示调用
      // unawaited(_updateNotification());
    }
  }

  // ── 権限 ────────────────────────────────────────────────────────

  Future<bool> _requestLocationPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    // 仅接受 whileInUse，严禁引导开启 always
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  Future<bool> _requestNotificationPermissions() async {
    // FGT 的通知权限
    await _fgt.requestNotificationPermission();

    // FLN 的通知权限
    await _fln
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    return true; // 留给以后对通知的详细判定
  }

  // ── 業務通知（FLN）────────────────────────────────────────────────

  Future<void> _updateNotification({bool forceUpdate = false}) async {
    if (_isNotificationUpdating) return;

    _isNotificationUpdating = true;
    try {
      if (_serviceResults case [final first, ...]) {
        final isStationChanged = _lastNearestResult?.gcd != first.gcd;
        _lastNearestResult = first;

        // 最近车站切换时取消当前通知重新显示
        if (isStationChanged) await _fln.cancelAll();
        // 通知模式是每次定位更新时更新通知内的距离
        // if (forceUpdate ||
        //     isStationChanged ||
        //     _settings?.notificationMode == NotificationMode.location) {
        if (forceUpdate || isStationChanged) {
          await _fln.show(
            id: Common.flnNotificationId,
            title: _l10n.flnNotificationTitle(first.name),
            // body: _settings?.notificationMode == NotificationMode.location
            //     ? _l10n.flnNotificationFull(first.gcd, first.distanceInUnit)
            //     : _l10n.flnNotificationGcd(first.gcd),
            body: _l10n.flnNotificationGcd(first.gcd),
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                Common.flnChannelId, // channelId
                _l10n.flnChannelName, // channelName
                channelDescription: _l10n.flnChannelDescription,
                icon: Common.flnNotificationIcon,
                importance: // isStationChanged ? Importance.high : Importance.low,
                    Importance.high,
                priority: // isStationChanged ? Priority.high : Priority.low,
                    Priority.high,
                showWhen: true,
                playSound: false, // 不发出提示音
                enableVibration: false, // 不振动
                autoCancel: false, // 点击不消失
                // ongoing: false,
                onlyAlertOnce: true, // 更新时不重复提示音/振动
                channelShowBadge: false,
              ),
              iOS: DarwinNotificationDetails(
                categoryIdentifier: Common.flnChannelId,
                // presentAlert: isStationChanged,
                presentSound: false,
                presentBadge: false,
              ),
            ),
          );
        }
      }
    } finally {
      _isNotificationUpdating = false;
    }
  }

  // ── Task Isolate → 主线程 データ受信 ────────────────────────────

  void _onReceiveTaskData(Object data) {
    if (data
        case {
          'ready': 'ready',
        }) {
      _onRunningStatusChanged?.call(RunningStatus.running);
    } else if (data
        case {
          'position_result': final List positionResultData,
          'station_results': final List serviceResultsData,
        }) {
      try {
        _positionResult = PositionResult.fromTransferable(positionResultData);
        _serviceResults = serviceResultsData
            .map((result) => StationResult.fromTransferable(result as List))
            .toList(growable: false);

        // 更新业务通知
        unawaited(_updateNotification());

        // UI 静默时不推送
        // 彻底消除后台 Widget 重绘
        if (_active) {
          _onLocated?.call(_positionResult, _serviceResults);
        }
      } catch (e, st) {
        debugPrint('error: $e\n$st');
      }
    }
  }
}

/// 顶级函数
/// Task Isolate 入口
/// 必须是顶级函数且必须加 @pragma('vm:entry-point')
@pragma('vm:entry-point')
void startCallback() {
  _fgt.setTaskHandler(LocationTaskHandler());
}

// ignore: camel_case_types
typedef _fgt = FlutterForegroundTask;
