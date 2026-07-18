import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'common.dart';
import 'l10n.dart';

/// 業務通知専用サービス（純粋な FLN ラッパー）
/// 状態を持たず、呼び出し側（Coordinator）から渡されたデータで通知を表示する
class NotificationService {
  L10n _l10n;

  late final FlutterLocalNotificationsPlugin _fln;

  bool _isNotificationUpdating = false;
  StationResult? _lastNearestResult; // 最近车站切换检测用
  List<StationResult>? _stationResults;

  NotificationService(this._l10n) {
    _fln = FlutterLocalNotificationsPlugin();
  }

  // ── 初期化 ──────────────────────────────────────────────────────

  Future<void> init() async {
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
    await cancelAll();
  }

  Future<void> cancelAll() async {
    await _fln.cancelAll();

    _isNotificationUpdating = false;
    _lastNearestResult = null;
    _stationResults = null;
  }

  // ── 定位結果イベント ──────────────────────────────────────────────

  void handleLocationResultReceived(
    PositionResult? positionResult,
    List<StationResult>? stationResults,
  ) {
    _stationResults = stationResults;

    if (stationResults == null) {
      unawaited(cancelAll());
      return;
    }

    unawaited(show(stationResults));
  }

  // ── Locale 更新 ──────────────────────────────────────────────────

  /// 系统语言更新
  void changeLocale(L10n l10n) {
    _l10n = l10n;

    if (_stationResults != null) {
      unawaited(show(_stationResults!, forceUpdate: true));
    }
  }

  // ── 権限 ────────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    await _fln
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    return true; // 留给以后对通知的详细判定
  }

  // ── 通知表示（FLN） ────────────────────────────────────────────────

  Future<void> show(
    List<StationResult> stationResults, {
    bool forceUpdate = false,
  }) async {
    if (_isNotificationUpdating) return;

    _isNotificationUpdating = true;
    try {
      if (stationResults case [final first, ...]) {
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
