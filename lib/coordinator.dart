import 'package:geolocator/geolocator.dart';

import 'common.dart';
import 'consumer/history_consumer.dart';
import 'consumer/notification_consumer.dart';
import 'l10n.dart';
import 'location_processor.dart';
import 'manager/event_manager.dart';
import 'manager/history_manager.dart';
import 'manager/settings_manager.dart';
import 'manager/station_manager.dart';

typedef LocationResultHandler =
    void Function(
      PositionResult? positionResult,
      List<StationResult>? stationResults,
    );
typedef RunningStatusHandler = void Function(RunningStatus runningStatus);

/// アプリ全体を協調する Coordinator
/// - LocationProcessor / 常駐 Consumer の生成と生命周期管理
/// - 権限リクエスト
/// - locate 結果に gcd/name を補完して StationResult を組立
/// - handlers を通じて UI などの消費者へ配信
class Coordinator {
  L10n _l10n;
  bool _active;
  SettingsManager _settingsManager;
  StationManager _stationManager;
  EventManager _eventManager;
  final HistoryManager _historyManager;

  late final LocationProcessor _locationProcessor;
  late final NotificationConsumer _notificationConsumer;
  late final HistoryConsumer _historyConsumer;

  PositionResult? _positionResult;
  List<StationResult>? _stationResults;
  RunningStatus _runningStatus = RunningStatus.stopped;

  // ── 公開 Getter（HomePage はここから直接読む・データを複製しない）───
  PositionResult? get positionResult => _positionResult;
  List<StationResult>? get stationResults => _stationResults;
  RunningStatus get runningStatus => _runningStatus;

  // コールバック
  // home では単に rebuild をトリガーする用途で使う想定
  final Set<LocationResultHandler> _onLocationResultReceived = {};
  final Set<LocationResultHandler> _onLocationResultReceivedActive = {};
  final Set<RunningStatusHandler> _onRunningStatusChanged = {};

  Coordinator(
    this._l10n,
    this._active,
    this._settingsManager,
    this._stationManager,
    this._eventManager,
    this._historyManager,
  ) {
    _notificationConsumer = NotificationConsumer(_l10n);
    _historyConsumer = HistoryConsumer(
      _active,
      _historyManager,
      _settingsManager.historySettingsManager,
    );

    _locationProcessor = LocationProcessor(
      _l10n,
      _active,
      _stationManager,
      _settingsManager.processorSettingsManager,
    );
    _locationProcessor.setLocationHandler(_handleLocationUpdated);

    // NotificationConsumer と HistoryConsumer は常駐 handler
    //（active: false）として登録する。
    // 常駐 handler を active handler（画面）より先に更新する。
    addLocationResultHandler(
      _notificationConsumer.handleLocationResultReceived,
    );
    addLocationResultHandler(_historyConsumer.handleLocationResultReceived);

    // 初期イベント期間判定の注入（起動時に一度）
    StationCount.eventPeriod = () => _eventManager.isEventPeriod;
  }

  // ── イベント購読・コールバック ────────────────────────────────────────────

  void addLocationResultHandler(
    LocationResultHandler handler, {
    bool active = false,
  }) {
    removeLocationResultHandler(handler);

    if (active) {
      _onLocationResultReceivedActive.add(handler);
    } else {
      _onLocationResultReceived.add(handler);
    }
  }

  void removeLocationResultHandler(LocationResultHandler handler) {
    _onLocationResultReceived.remove(handler);
    _onLocationResultReceivedActive.remove(handler);
  }

  void _notifyLocationResultReceived(
    PositionResult? positionResult,
    List<StationResult>? stationResults, {
    bool forceNotify = false,
  }) {
    for (final handler in List<LocationResultHandler>.of(
      _onLocationResultReceived,
    )) {
      handler(positionResult, stationResults);
    }
    if (_active || forceNotify) {
      for (final handler in List<LocationResultHandler>.of(
        _onLocationResultReceivedActive,
      )) {
        handler(positionResult, stationResults);
      }
    }
  }

  void addRunningStatusHandler(RunningStatusHandler handler) {
    _onRunningStatusChanged.add(handler);
  }

  void removeRunningStatusHandler(RunningStatusHandler handler) {
    _onRunningStatusChanged.remove(handler);
  }

  void _notifyRunningStatusChanged(RunningStatus runningStatus) {
    for (final handler in List<RunningStatusHandler>.of(
      _onRunningStatusChanged,
    )) {
      handler(runningStatus);
    }
  }

  // ── 初期化 ──────────────────────────────────────────────────────

  /// HomePage.initState() から呼び出す
  /// FLN など非同期の初期化のみを担う
  Future<void> init() async {
    await _notificationConsumer.init();
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

    // 権限要求中に停止された場合は開始処理を中断する
    if (_runningStatus != RunningStatus.starting) return;

    await _locationProcessor.start();

    // running への遷移は最初の定位結果を受信した時点で
    // _handleLocationUpdated にて行う
  }

  /// 停止ボタン押下時
  Future<void> stop() async {
    await _locationProcessor.stop();

    await _historyConsumer.flush();

    await _notificationConsumer.cancelAll();

    _positionResult = null;
    _stationResults = null;

    _runningStatus = RunningStatus.stopped;
    _notifyRunningStatusChanged(_runningStatus);

    _notifyLocationResultReceived(null, null, forceNotify: true);
  }

  // ── 設定・Locale・Lifecycle・Data ─────────────────────────────────

  Future<void> changeSettings(SettingsManager manager) async {
    _settingsManager = manager;

    await _historyConsumer.changeSettings(manager.historySettingsManager);
    await _locationProcessor.changeSettings(manager.processorSettingsManager);
  }

  void changeLocale(L10n l10n) {
    _l10n = l10n;

    _locationProcessor.changeLocale(l10n);
    _notificationConsumer.changeLocale(l10n);
  }

  /// UI の前台/后台状態が変わった時
  /// LocationProcessor に active を伝え、search 件数を切り替える
  void changeActive(bool active) {
    if (active != _active) {
      _active = active;

      // LocationProcessor へ伝達
      // active=true に戻った場合は count 分の再検索が LocationProcessor 内で走る
      _locationProcessor.changeActive(active);

      // HistoryConsumer へ伝達（非アクティブ期間は画面向け通知を抑制）
      _historyConsumer.changeActive(active);

      // 復帰時は即座に UI を更新
      if (_active) {
        _notifyLocationResultReceived(_positionResult, _stationResults);
      }
    }
  }

  /// 站点数据更新（hot reload）
  /// manager 与 SearchEngine 在 LocationProcessor 内成对替换（同一同步块）
  void changeStationData(StationManager manager) {
    _stationManager = manager;
    _locationProcessor.changeData(manager);
  }

  /// 活动数据更新
  void changeEventData(EventManager manager) {
    _eventManager = manager;
    // StationCount 检索件数所需的事件期间判定器注入（幂等）
    StationCount.eventPeriod = () => manager.isEventPeriod;
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
    await _notificationConsumer.requestPermissions();
    return true;
  }

  // ── LocationProcessor コールバック ────────────────────────────────

  void _handleLocationUpdated(
    PositionResult positionResult,
    List<StationResult> stationResults,
  ) {
    // 停止後に到着した遅延定位結果は破棄する
    if (_runningStatus == RunningStatus.stopped) return;

    _positionResult = positionResult;

    // index → gcd と name を補完して完全な StationResult を組立
    _stationResults = stationResults
        .map((result) {
          final (gcd, name) = _stationManager.getStationName(result.index);
          return StationResult(
            index: result.index,
            gcd: gcd,
            name: name,
            distance: result.distance,
            bearing: result.bearing,
          );
        })
        .toList(growable: false);

    // 最初の定位結果を受信した時点で starting から running へ遷移する
    if (_runningStatus == RunningStatus.starting) {
      _runningStatus = RunningStatus.running;
      _notifyRunningStatusChanged(_runningStatus);
    }

    _notifyLocationResultReceived(_positionResult, _stationResults);
  }

  // ── 历史记录（判定・缓冲・落盘は HistoryConsumer が担う） ──────────

  /// 常驻历史消费者（UI へ直接注入し、履歴ページはこれを参照する）
  HistoryConsumer get historyConsumer => _historyConsumer;
}
