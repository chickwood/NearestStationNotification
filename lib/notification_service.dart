import 'dart:async';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import 'app_settings.dart';
import 'common.dart';
import 'l10n.dart';
import 'location_processor.dart';
import 'search_engine.dart';

/// 通知・UI コールバック管理クラス
/// LocationProcessor の結果を受けて FLN 業務通知を発行し UI を更新する
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

  // ── GPS 流处理 ────────────────────────────────────────────────────
  LocationProcessor? _locationProcessor;

  // ── FLN ───────────────────────────────────────────────────────
  final _fln = FlutterLocalNotificationsPlugin();

  NotificationService(this._l10n);

  // ── 初期化 ──────────────────────────────────────────────────────

  /// アプリ起動時に呼び出初期化処理
  Future<void> initService() async {
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
    _onRunningStatusChanged = onRunningStatusChanged;

    // 权限
    if (!await _requestLocationPermissions() ||
        !await _requestNotificationPermissions()) {
      _onRunningStatusChanged?.call(RunningStatus.stopped);
      _onRunningStatusChanged = null;
      return;
    }

    _onLocated = onLocated;
    // _settings = settings;

    final engine = await SearchEngine.load();

    _locationProcessor = LocationProcessor(
      foregroundNotificationTitle: _l10n.fgtNotificationTitle,
      foregroundNotificationBody: _l10n.fgtNotificationBody,
      onLocated: _onReceiveLocation,
    );
    await _locationProcessor!.start(settings, engine);

    _onRunningStatusChanged?.call(RunningStatus.running);
  }

  Future<void> stopLocating() async {
    await _locationProcessor?.stop();
    _locationProcessor = null;

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
    }
  }

  /// 系统语言更新
  void changeLocale(AppLocalizations l10n) {
    _l10n = l10n;

    // 前台通知テキストを更新
    if (_locationProcessor != null) {
      _locationProcessor!.foregroundNotificationTitle =
          _l10n.fgtNotificationTitle;
      _locationProcessor!.foregroundNotificationBody =
          _l10n.fgtNotificationBody;
    }

    unawaited(_updateNotification(forceUpdate: true));
  }

  /// 设置更改
  Future<void> changeSettings(AppSettings settings) async {
    // _settings = settings;
    await _locationProcessor?.changeSettings(settings);
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
    await _fln
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    return true;
  }

  // ── LocationProcessor コールバック ────────────────────────────────

  void _onReceiveLocation(
    PositionResult positionResult,
    List<StationResult> stationResults,
  ) {
    _positionResult = positionResult;
    _serviceResults = stationResults;

    unawaited(_updateNotification());

    // UI 静默时不推送
    if (_active) {
      _onLocated?.call(_positionResult, _serviceResults);
    }
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
}
