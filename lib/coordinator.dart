import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import 'settings.dart';
import 'common.dart';
import 'l10n.dart';
import 'location_processor.dart';
import 'notification_service.dart';
import 'station_manager.dart';

typedef LocatedHandler = void Function(
  PositionResult? positionResult,
  List<StationResult>? stationResults,
);
typedef RunningStatusHandler = void Function(RunningStatus runningStatus);

/// アプリ全体を協調する Coordinator
/// - LocationProcessor / NotificationService の生成と生命周期管理
/// - 権限リクエスト
/// - locate 結果に gcd/name を補完して StationResult を組立
/// - handlers を通じて UI などの消費者へ配信
class Coordinator {
  L10n _l10n;
  bool _active;
  Settings _settings;
  final StationManager _manager;

  late final LocationProcessor _locationProcessor;
  late final NotificationService _notificationService;

  PositionResult? _positionResult;
  List<StationResult>? _stationResults;
  RunningStatus _runningStatus = RunningStatus.stopped;

  // ── 公開 Getter（HomePage はここから直接読む・データを複製しない）───
  PositionResult? get positionResult => _positionResult;
  List<StationResult>? get stationResults => _stationResults;
  RunningStatus get runningStatus => _runningStatus;

  // コールバック
  // home では単に rebuild をトリガーする用途で使う想定
  // 実データは positionResult / stationResults / runningStatus の getter から取得する
  final List<LocatedHandler> _locatedHandlers = [];
  final List<LocatedHandler> _activeLocatedHandlers = [];
  final List<RunningStatusHandler> _runningStatusHandlers = [];

  Coordinator(this._l10n, this._active, this._settings, this._manager) {
    _notificationService = NotificationService(_l10n);
    addLocatedHandler(_notificationService.onLocated);

    _locationProcessor = LocationProcessor(
      _l10n,
      _active,
      _settings,
      _manager,
      onLocated: _onReceiveLocation,
    );
  }

  // ── イベント購読 ─────────────────────────────────────────────────

  void addLocatedHandler(LocatedHandler handler, {bool activeOnly = false}) {
    if (activeOnly) {
      _activeLocatedHandlers.add(handler);
    } else {
      _locatedHandlers.add(handler);
    }
  }

  void removeLocatedHandler(LocatedHandler handler) {
    _locatedHandlers.remove(handler);
    _activeLocatedHandlers.remove(handler);
  }

  void addRunningStatusHandler(RunningStatusHandler handler) {
    _runningStatusHandlers.add(handler);
  }

  void removeRunningStatusHandler(RunningStatusHandler handler) {
    _runningStatusHandlers.remove(handler);
  }

  // ── 初期化 ──────────────────────────────────────────────────────

  /// HomePage.initState() から呼び出す
  /// FLN など非同期の初期化のみを担う
  Future<void> init() async {
    await _notificationService.init();
  }

  // ── タスク制御 ────────────────────────────────────────────────────

  /// 開始ボタン押下時
  Future<void> start() async {
    _runningStatus = RunningStatus.starting;
    _notifyRunningStatusChanged(_runningStatus);

    if (!await _requestLocationPermissions() ||
        !await _requestNotificationPermissions()) {
      _runningStatus = RunningStatus.stopped;
      _notifyRunningStatusChanged(_runningStatus);
      return;
    }

    await _locationProcessor.start();

    _runningStatus = RunningStatus.running;
    _notifyRunningStatusChanged(_runningStatus);
  }

  /// 停止ボタン押下時
  Future<void> stop() async {
    await _locationProcessor.stop();

    await _notificationService.cancelAll();

    _positionResult = null;
    _stationResults = null;

    _runningStatus = RunningStatus.stopped;
    _notifyRunningStatusChanged(_runningStatus);

    _notifyLocated(null, null, forceActiveHandlers: true);
  }

  // ── 設定・Locale・Lifecycle ───────────────────────────────────────

  Future<void> changeSettings(Settings settings) async {
    _settings = settings;
    await _locationProcessor.changeSettings(settings);
  }

  void changeLocale(L10n l10n) {
    _l10n = l10n;

    _locationProcessor.changeLocale(l10n);
    _notificationService.changeLocale(l10n);

    if (_stationResults != null) {
      unawaited(_notificationService.show(_stationResults!, forceUpdate: true));
    }
  }

  /// UI の前台/后台状態が変わった時
  /// LocationProcessor に active を伝え、search 件数を切り替える
  void changeLifecycleState(AppLifecycleState state) {
    final active = switch (state) {
      AppLifecycleState.paused => false,
      AppLifecycleState.resumed => true,
      _ => _active,
    };

    if (active != _active) {
      _active = active;

      // LocationProcessor へ伝達
      // active=true に戻った場合は count 分の再検索が LocationProcessor 内で走る
      _locationProcessor.changeActive(active);

      // 復帰時は即座に UI を更新
      if (_active) {
        _notifyLocated(_positionResult, _stationResults);
      }
    }
  }

  // ── 権限 ────────────────────────────────────────────────────────

  Future<bool> _requestLocationPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    // 仅接受 whileInUse，严禁引导开启 always
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  Future<bool> _requestNotificationPermissions() async {
    await _notificationService.requestPermissions();
    return true;
  }

  // ── LocationProcessor コールバック ────────────────────────────────

  void _onReceiveLocation(
    PositionResult positionResult,
    List<StationResult> stationResults,
  ) {
    // index → gcd / name を補完して完全な StationResult を組立
    final completedStationResults = stationResults.map((result) {
      final (gcd, name) = _manager.getStationName(result.index);
      return StationResult(
        index: result.index,
        gcd: gcd,
        name: name,
        distance: result.distance,
        bearing: result.bearing,
      );
    }).toList(growable: false);

    _positionResult = positionResult;
    _stationResults = completedStationResults;

    _notifyLocated(positionResult, completedStationResults);
  }

  void _notifyLocated(
      PositionResult? positionResult, List<StationResult>? stationResults,
      {bool forceActiveHandlers = false}) {
    for (final handler in List<LocatedHandler>.of(_locatedHandlers)) {
      handler(positionResult, stationResults);
    }
    if (_active || forceActiveHandlers) {
      for (final handler
          in List<LocatedHandler>.of(_activeLocatedHandlers)) {
        handler(positionResult, stationResults);
      }
    }
  }

  void _notifyRunningStatusChanged(RunningStatus runningStatus) {
    for (final handler
        in List<RunningStatusHandler>.of(_runningStatusHandlers)) {
      handler(runningStatus);
    }
  }
}
