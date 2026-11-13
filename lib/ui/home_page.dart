import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_styled_toast/flutter_styled_toast.dart';
import 'package:material_ui/material_ui.dart';

import '../common.dart';
import '../coordinator.dart';
import '../l10n.dart';
import '../manager/event_manager.dart';
import '../manager/history_manager.dart';
import '../manager/settings_manager.dart';
import '../manager/station_manager.dart';
import '../service/history_archive_service.dart';
import '../service/history_backup_service.dart';
import '../service/info_import_service.dart';
import '../service/settings_save_service.dart';
import 'history_page.dart';
import 'info_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ResetableState<HomePage>
    with WidgetsBindingObserver {
  SettingsManager? _settingsManager;
  StationManager? _stationManager;
  EventManager? _eventManager;
  HistoryManager? _historyManager;

  Coordinator? _coordinator;

  late final InfoImportService _infoImportService;
  late final SettingsSaveService _settingsSaveService;
  late final HistoryBackupService _historyBackupService;
  late final HistoryArchiveService _historyArchiveService;

  int _positionVisibility = 0; // 坐标显示/关闭

  @override
  void initState() {
    super.initState();

    _infoImportService = InfoImportService();
    _settingsSaveService = SettingsSaveService();
    _historyBackupService = HistoryBackupService();
    _historyArchiveService = HistoryArchiveService();
    _infoImportService.last.addListener(_handleInfoImportResultNotified);
    _settingsSaveService.last.addListener(_handleSettingsSaveResultNotified);
    _historyBackupService.last.addListener(_handleHistoryBackupResultNotified);
    _historyArchiveService.last.addListener(
      _handleHistoryArchiveResultNotified,
    );
    _historyArchiveService.busy.addListener(_handleHistoryArchiveChanged);
    _historyArchiveService.progress.addListener(_handleHistoryArchiveChanged);

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _infoImportService.last.removeListener(_handleInfoImportResultNotified);
    _settingsSaveService.last.removeListener(_handleSettingsSaveResultNotified);
    _historyBackupService.last.removeListener(
      _handleHistoryBackupResultNotified,
    );
    _historyArchiveService.last.removeListener(
      _handleHistoryArchiveResultNotified,
    );
    _historyArchiveService.busy.removeListener(_handleHistoryArchiveChanged);
    _historyArchiveService.progress.removeListener(
      _handleHistoryArchiveChanged,
    );
    _historyArchiveService.cancel();
    _infoImportService.dispose();
    _settingsSaveService.dispose();
    _historyBackupService.dispose();
    _historyArchiveService.dispose();

    _coordinator?.removeLocationResultHandler(_handleLocationResultReceived);
    _coordinator?.removeRunningStatusHandler(_handleRunningStatusChanged);
    _coordinator?.stop();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // inactive などの過渡状態は無視し、paused / resumed のみ伝達する
    switch (state) {
      case AppLifecycleState.paused:
        _coordinator?.changeActive(false);
      case AppLifecycleState.resumed:
        _coordinator?.changeActive(true);
      default:
        break;
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    super.didChangeLocales(locales);

    // 厳格な locale 解析（MaterialApp と同一の L10n.resolve を使用）
    _coordinator?.changeLocale(L10n(L10n.resolve(locales)));
  }

  @override
  Widget build(BuildContext context) {
    if (_coordinator == null ||
        _settingsManager == null ||
        _stationManager == null ||
        _eventManager == null ||
        _historyManager == null) {
      return const Scaffold();
    }

    final l10n = L10n.of(context);
    return BackgroundTask(
      keepBackgroundTask: _coordinator!.runningStatus != RunningStatus.stopped,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          titleSpacing: 16,
          // title: Row(
          //   children: [
          //     // Image.asset(
          //     //   'assets/ic_title.png',
          //     //   color: Colors.white,
          //     //   width: 32,
          //     //   height: 32,
          //     //   fit: BoxFit.contain,
          //     // ),
          //     // const SizedBox(width: 4),
          //     Flexible(child: Text(l10n.appTitle)),
          //   ],
          // ),
          title: Text(l10n.appTitle),
          actions: [
            // 定位详细显示切换
            if (_coordinator!.runningStatus == RunningStatus.running)
              AppBarAction(
                onPressed: _switchPositionVisibility,
                icon: _positionVisibility > 0
                    ? const Icon(Icons.near_me)
                    : const Icon(Icons.near_me_disabled),
                color: _positionVisibility == 1
                    ? const Color(0xFFA0C0FF)
                    : Colors.white,
              ),
            // 开始/停止
            AppBarAction(
              onPressed: _handlePlay,
              icon: _coordinator!.runningStatus == RunningStatus.running
                  ? const Icon(Icons.stop)
                  : const Icon(Icons.play_arrow),
              color: _coordinator!.runningStatus == RunningStatus.starting
                  ? const Color(0xFFA0C0FF)
                  : Colors.white,
            ),
            // 设置 / 信息菜单（starting 中・アーカイブ中は無効化）
            AppBarMenu<HomeMenuAction>(
              enabled:
                  !_historyArchiveService.busy.value &&
                  _coordinator!.runningStatus != RunningStatus.starting,
              position: PopupMenuPosition.under,
              icon: const Icon(Icons.more_vert),
              iconColor:
                  _historyArchiveService.busy.value ||
                      _coordinator!.runningStatus == RunningStatus.starting
                  ? const Color(0xFFA0C0FF)
                  : Colors.white,
              onSelected: (action) {
                switch (action) {
                  case HomeMenuAction.settings:
                    _showSettingsPage();
                    break;
                  case HomeMenuAction.history:
                    if (_settingsManager!.historyEnabled) {
                      _showHistoryPage();
                    }
                    break;
                  case HomeMenuAction.info:
                    _showInfoPage();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: HomeMenuAction.settings,
                  child: Text(l10n.settingsPageTitle),
                ),
                PopupMenuItem(
                  value: HomeMenuAction.history,
                  enabled: _settingsManager!.historyEnabled,
                  child: Text(
                    l10n.historyTitle,
                    style: _settingsManager!.historyEnabled
                        ? null
                        : const TextStyle(color: Colors.grey),
                  ),
                ),
                PopupMenuItem(
                  value: HomeMenuAction.info,
                  child: Text(l10n.infoPageTitle),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (_historyArchiveService.busy.value)
              LinearProgressIndicator(
                value: _historyArchiveService.progress.value > 0
                    ? _historyArchiveService.progress.value
                    : null,
                color: const Color(0xFF4080FF),
                backgroundColor: const Color(0xFFDCECFF),
              ),
            Expanded(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_coordinator!.runningStatus ==
                              RunningStatus.running &&
                          _positionVisibility > 0)
                        ..._buildPositionResult(l10n), // 位置信息: リストの上、可隐藏
                      _buildStationResultsExpanded(l10n), // 车站列表: リスト部分のみスクロール
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 初期化 ──────────────────────────────────────────────────────

  /// アプリ起動時に呼び出初期化処理
  Future<void> _initialize() async {
    final l10n = L10n.of(context);
    final active = true; // 应用启动时 active 必然为 true

    try {
      late SettingsManager settingsManager;
      late StationManager stationManager;
      late EventManager eventManager;
      late HistoryManager historyManager;
      await Future.wait([
        SettingsManager.load().then((value) => settingsManager = value),
        StationManager.load().then((value) => stationManager = value),
        EventManager.load().then((value) => eventManager = value),
        HistoryManager.load().then((value) => historyManager = value),
      ]);

      final coordinator = Coordinator(
        l10n,
        active,
        settingsManager,
        stationManager,
        eventManager,
        historyManager,
      );
      _coordinator = coordinator;

      // UI handler 登録
      coordinator.addLocationResultHandler(
        _handleLocationResultReceived,
        active: true,
      );
      coordinator.addRunningStatusHandler(_handleRunningStatusChanged);

      await coordinator.init();

      if (!mounted) return;
      setState(() {
        _settingsManager = settingsManager;
        _stationManager = stationManager;
        _eventManager = eventManager;
        _historyManager = historyManager;
      });

      unawaited(_historyArchiveService.start(historyManager));
    } catch (e) {
      // 其他错误（文件读取失败等）
      debugPrint(e.toString());
      _showToast(l10n.errorMsg('$e'), isError: true);
    }
  }

  // ── ボタンイベント ────────────────────────────────────────────────

  /// アーカイブ中はキャンセルのみ、それ以外は開始 / 停止
  Future<void> _handlePlay() async {
    if (_historyArchiveService.busy.value) {
      _historyArchiveService.cancel();
      return;
    }

    if (_coordinator!.runningStatus == RunningStatus.stopped) {
      await _start();
    } else {
      await _stop();
    }
  }

  /// 起動ボタン押下時
  /// 権限リクエスト + 定位開始
  Future<void> _start() async {
    if (_settingsManager == null) return;

    await _coordinator?.start();
    // 按钮外观变更
    // 在 service 内部由 init 绑定的 onRunningStatusChanged 触发
    // setState(() {
    //   _runningStatus = runningStatus;
    // });
  }

  Future<void> _stop() async {
    await _coordinator?.stop();
    // 按钮外观变更
    // 在 service 内部由 init 绑定的 onRunningStatusChanged 触发
    // setState(() {
    //   _runningStatus = runningStatus;
    // });
  }

  void _switchPositionVisibility() {
    setState(() {
      _positionVisibility = (_positionVisibility + 1) % 3;
    });
  }

  // ── Toast ──────────────────────────────────────────────────────

  void _showToast(String message, {bool isError = false}) {
    showToast(
      message,
      backgroundColor: isError
          ? const Color(0xFFFF4030) // Colors.red.shade700
          : const Color(0xFFDCECFF), // Colors.indigo.shade300
      textStyle: TextStyle(
        color: isError ? Colors.white : Colors.grey.shade800,
      ),
      textPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      textAlign: TextAlign.left,
      borderRadius: BorderRadius.circular(8),
    );
  }

  // ── Handler ──────────────────────────────────────────────

  void _handleLocationResultReceived(_, _) => resetState();
  void _handleRunningStatusChanged(_) => resetState();
  void _handleHistoryArchiveChanged() => resetState();

  // ── Service results ──────────────────────────────────────────────

  void _handleInfoImportResultNotified() {
    final result = _infoImportService.last.value;
    if (!mounted || result == null) return;

    final l10n = L10n.of(context);
    if (!result.succeeded) {
      _showToast(l10n.infoInvalidFile, isError: true);
      return;
    }

    final station = result.station;
    final event = result.event;

    if (station != null) {
      _coordinator?.changeStationData(station);
    }
    if (event != null) {
      _coordinator?.changeEventData(event);
    }
    setState(() {
      if (station != null) {
        _stationManager = station;
      }
      if (event != null) {
        _eventManager = event;
      }
    });

    if (station != null && event != null) {
      _showToast(l10n.infoImportedStationAndEvent);
    } else if (station != null) {
      _showToast(l10n.infoImportedStation);
    } else {
      _showToast(l10n.infoImportedEvent);
    }
  }

  void _handleSettingsSaveResultNotified() {
    final result = _settingsSaveService.last.value;
    if (!mounted || result == null) return;

    final l10n = L10n.of(context);
    if (!result.succeeded) {
      _showToast(l10n.settingsSaveFailed, isError: true);
      return;
    }

    final settings = result.settings!;
    setState(() {
      _settingsManager = settings;
    });
    // 无论运行状态如何都立即反映
    // （LocationProcessor 内部会根据 stream 状态自行判断）
    _coordinator?.changeSettings(settings);
    _showToast(l10n.settingsSaveSucceeded);
  }

  void _handleHistoryBackupResultNotified() {
    final result = _historyBackupService.last.value;
    if (!mounted || result == null || result.cancelled) return;

    final l10n = L10n.of(context);
    if (!result.succeeded) {
      _showToast(l10n.historyBackupFailed, isError: true);
      return;
    }

    if (result.action == HistoryBackupAction.export) {
      _showToast(l10n.historyExportSucceeded);
    } else {
      _showToast(l10n.historyImportSucceeded);
    }
  }

  void _handleHistoryArchiveResultNotified() {
    final result = _historyArchiveService.last.value;
    if (!mounted || result == null || result.cancelled) return;

    final l10n = L10n.of(context);
    if (!result.succeeded) {
      _showToast(l10n.historyArchiveFailed, isError: true);
      return;
    }

    _showToast(l10n.historyArchiveSucceeded);
  }

  // ── Settings Page ─────────────────────────────────────────────────────

  void _showSettingsPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(_settingsManager!, _settingsSaveService),
      ),
    );
  }

  // ── History Page ───────────────────────────────────────────────────

  void _showHistoryPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryPage(
          _coordinator!.historyConsumer,
          _historyManager!,
          _historyBackupService,
          _stationManager!,
          _settingsManager!,
          _settingsSaveService,
        ),
      ),
    );
  }

  // ── Info Page ───────────────────────────────────────────────────────

  void _showInfoPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            InfoPage(_stationManager!, _eventManager!, _infoImportService),
      ),
    );
  }

  // ── Station results (expanded) ────────────────────────────────────────────────

  Widget _buildStationResultsExpanded(L10n l10n) {
    if (_historyArchiveService.busy.value) {
      return Align(
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.historyArchiving,
              style: const TextStyle(color: Colors.grey),
            ),
            Text(
              l10n.historyArchivingForLongtime,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_stationManager!.count <= 0) {
      return Align(
        alignment: Alignment.topCenter,
        child: Text(
          l10n.countStations(0),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_coordinator!.runningStatus == RunningStatus.stopped) {
      return Align(
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.notStarted, style: const TextStyle(color: Colors.grey)),
            Text(l10n.tapToStart, style: const TextStyle(color: Colors.grey)),
            if (_stationManager!.isSampleData) ...[
              const SizedBox(height: 4),
              Text(
                l10n.sampleDataGuide,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ],
        ),
      );
    }

    if (_coordinator!.runningStatus == RunningStatus.starting) {
      return Align(
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.waitingForLocation,
              style: const TextStyle(color: Colors.grey),
            ),
            Text(
              l10n.waitingForLongtime,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.nearbyStations,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ListView.separated(
                itemCount: _coordinator!.stationResults!.length,
                itemBuilder: (_, index) {
                  final stationResult = _coordinator!.stationResults![index];

                  return _StationTile(
                    index: index,
                    name: stationResult.name ?? '',
                    distance: stationResult.distanceInUnit,
                    direction: l10n.direction(stationResult.bearingIndex),
                    part: _settingsManager!.stationCount.part(index),
                  );
                },
                separatorBuilder: (_, _) {
                  return const SizedBox(height: 4);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Position result ────────────────────────────────────────────────

  List<Widget> _buildPositionResult(L10n l10n) {
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _positionVisibility == 1
                ? l10n.currentLocation
                : l10n.currentLocationStatus,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _PositionRow(
            labelL: l10n.latitude,
            valueL: _coordinator!.positionResult!.latitude.toStringAsFixed(6),
            labelR: l10n.longitude,
            valueR: _coordinator!.positionResult!.longitude.toStringAsFixed(6),
          ),
          if (_positionVisibility == 2) ...[
            const SizedBox(height: 4),
            _PositionRow(
              labelL: l10n.speed,
              valueL: _coordinator!.positionResult!.speedString,
              labelR: l10n.accuracy,
              valueR: _coordinator!.positionResult!.accuracyString,
            ),
            const SizedBox(height: 4),
            _PositionRow(
              labelL: l10n.heading,
              valueL: l10n.direction(
                _coordinator!.positionResult!.headingIndex,
              ),
              labelR: l10n.timestamp,
              valueR: _coordinator!.positionResult!.timeString,
            ),
          ],
        ],
      ),
      const Divider(height: 16),
    ];
  }
}

// ── Position row ─────────────────────────────────────────────────
class _PositionRow extends StatelessWidget {
  final String labelL;
  final String valueL;
  final String labelR;
  final String valueR;

  const _PositionRow({
    required this.labelL,
    required this.valueL,
    required this.labelR,
    required this.valueR,
  });

  @override
  Widget build(Object context) {
    return Row(
      children: [
        _PositionCell(label: labelL, value: valueL),
        const SizedBox(width: 4),
        _PositionCell(label: labelR, value: valueR),
      ],
    );
  }
}

// ── Position cell ─────────────────────────────────────────────────

class _PositionCell extends StatelessWidget {
  final String label;
  final String value;

  const _PositionCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.0),
            ),
            Text(
              value,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 12.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Station tile ─────────────────────────────────────────────────

class _StationTile extends StatelessWidget {
  final int index;
  final String name;
  final String distance;
  final String direction;
  final StationCountPart part;

  const _StationTile({
    required this.index,
    required this.name,
    required this.distance,
    required this.direction,
    required this.part,
  });

  // part → 配色（边框深一档 / 填充浅一档）
  static final _partBorderColors = <StationCountPart, Color>{
    StationCountPart.friend: Colors.grey.shade300,
    StationCountPart.event: const Color(0xFFB8D8FF),
    StationCountPart.radar: const Color(0xFFC0E8CC),
    StationCountPart.natsume: const Color(0xFFFFF0B0),
  };
  static final _partFillColors = <StationCountPart, Color>{
    StationCountPart.friend: Colors.grey.shade200,
    StationCountPart.event: const Color(0xFFDCECFF),
    StationCountPart.radar: const Color(0xFFE0F4E8),
    StationCountPart.natsume: const Color(0xFFFFF9E0),
  };

  @override
  Widget build(BuildContext context) {
    final isNearest = index == 0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: isNearest ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: isNearest ? const Color(0xFFDCECFF) : Colors.white,
        border: Border.all(
          color: isNearest ? const Color(0xFF4080FF) : _partBorderColors[part]!,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: isNearest
                  ? const Color(0xFF4080FF)
                  : _partFillColors[part]!,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: isNearest ? Colors.white : Colors.grey.shade800,
                  fontSize: 12.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 12.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Container(
            height: 20,
            width: 40,
            // padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: isNearest
                  ? const Color(0xFF4080FF)
                  : _partFillColors[part]!,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                direction,
                style: TextStyle(
                  color: isNearest ? Colors.white : Colors.grey.shade800,
                  fontSize: 12.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isNearest
                  ? const Color(0xFF4080FF)
                  : _partFillColors[part]!,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                distance,
                style: TextStyle(
                  color: isNearest ? Colors.white : Colors.grey.shade800,
                  fontSize: 12.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Background task ──────────────────────────────────────────────

class BackgroundTask extends StatelessWidget {
  static const _channel = MethodChannel(
    'name.w57.nearest_station_notification/background_task',
  );

  final bool keepBackgroundTask;
  final Widget child;

  const BackgroundTask({
    super.key,
    required this.keepBackgroundTask,
    required this.child,
  });

  static bool get _isNativeAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _moveTaskToBack() async {
    await _channel.invokeMethod<void>('moveTaskToBack');
  }

  @override
  Widget build(BuildContext context) {
    if (!_isNativeAndroid) return child;

    return PopScope(
      canPop: !keepBackgroundTask,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && keepBackgroundTask) {
          unawaited(_moveTaskToBack());
        }
      },
      child: child,
    );
  }
}
