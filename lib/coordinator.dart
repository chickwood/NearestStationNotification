import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import 'settings.dart';
import 'common.dart';
import 'l10n.dart';
import 'location_processor.dart';
import 'notification_service.dart';
import 'search_engine.dart';
import 'station_manager.dart';

typedef LocatedListener = void Function(
  PositionResult? positionResult,
  List<StationResult>? stationResults,
);
typedef RunningStatusListener = void Function(RunningStatus runningStatus);

/// アプリ全体を協調する Coordinator
/// - StationManager / SearchEngine の初期化と保持
/// - LocationProcessor の生命周期管理
/// - 権限リクエスト
/// - locate 結果に gcd/name を補完して StationResult を組立
/// - listeners を通じて UI などの消費者へ配信
class Coordinator {
  L10n _l10n;
  // AppSettings? _settings;
  bool _active = true; // 前台=true，后台(paused)=false

  StationManager? _stationManager;
  SearchEngine? _engine;

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
  final List<LocatedListener> _locatedListeners = [];
  final List<LocatedListener> _activeLocatedListeners = [];
  final List<RunningStatusListener> _runningStatusListeners = [];

  Coordinator(this._l10n) {
    _notificationService = NotificationService(_l10n);
    addLocatedListener(_notificationService.onLocated);

    _locationProcessor = LocationProcessor(
      onLocated: _onReceiveLocation,
      active: _active,
    );
  }

  // ── イベント購読 ─────────────────────────────────────────────────

  void addLocatedListener(LocatedListener listener, {bool activeOnly = false}) {
    if (activeOnly) {
      _activeLocatedListeners.add(listener);
    } else {
      _locatedListeners.add(listener);
    }
  }

  void removeLocatedListener(LocatedListener listener) {
    _locatedListeners.remove(listener);
    _activeLocatedListeners.remove(listener);
  }

  void addRunningStatusListener(RunningStatusListener listener) {
    _runningStatusListeners.add(listener);
  }

  void removeRunningStatusListener(RunningStatusListener listener) {
    _runningStatusListeners.remove(listener);
  }

  // ── 初期化 ──────────────────────────────────────────────────────

  /// HomePage.initState() から呼び出す
  /// StationManager と SearchEngine を一度だけロードする
  /// 返却した StationManager は UI 表示（count/date/size）に使う
  Future<StationManager> init() async {
    await _notificationService.init();

    final manager = await StationManager.load();
    _stationManager = manager;
    _engine = SearchEngine.fromManager(manager);

    return manager;
  }

  // ── タスク制御 ────────────────────────────────────────────────────

  /// 開始ボタン押下時
  Future<void> start(Settings settings) async {
    _runningStatus = RunningStatus.starting;
    _notifyRunningStatusChanged(_runningStatus);

    if (!await _requestLocationPermissions() ||
        !await _requestNotificationPermissions()) {
      _runningStatus = RunningStatus.stopped;
      _notifyRunningStatusChanged(_runningStatus);
      return;
    }

    // _settings = settings;
    await _locationProcessor.start(settings, _engine!);

    _runningStatus = RunningStatus.running;
    _notifyRunningStatusChanged(_runningStatus);
  }

  /// 停止ボタン押下時
  Future<void> stop() async {
    await _locationProcessor.stop();

    await _notificationService.cancelAll();

    _positionResult = null;
    _stationResults = null;
    // _settings = null;

    _runningStatus = RunningStatus.stopped;
    _notifyRunningStatusChanged(_runningStatus);

    _notifyLocated(null, null, forceActiveListeners: true);
  }

  // ── 設定・Locale・Lifecycle ───────────────────────────────────────

  Future<void> changeSettings(Settings settings) async {
    // _settings = settings;
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
      final (gcd, name) = _stationManager!.getStationName(result.index);
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
      {bool forceActiveListeners = false}) {
    for (final listener in List<LocatedListener>.of(_locatedListeners)) {
      listener(positionResult, stationResults);
    }
    if (_active || forceActiveListeners) {
      for (final listener
          in List<LocatedListener>.of(_activeLocatedListeners)) {
        listener(positionResult, stationResults);
      }
    }
  }

  void _notifyRunningStatusChanged(RunningStatus runningStatus) {
    for (final listener
        in List<RunningStatusListener>.of(_runningStatusListeners)) {
      listener(runningStatus);
    }
  }
}
