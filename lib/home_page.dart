import 'package:flutter/material.dart';

import 'coordinator.dart';
import 'settings.dart';
import 'common.dart';
import 'l10n.dart';
import 'settings_dialog.dart';
import 'station_manager.dart';
import 'background_task.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Settings? _settings;
  StationManager? _manager;

  Coordinator? _coordinator;

  int _positionVisibility = 0; // 坐标显示/关闭

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

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
    if (_coordinator == null || _settings == null || _manager == null) {
      return const Scaffold();
    }

    final l10n = L10n.of(context);
    return BackgroundTask(
      keepBackgroundTask: _coordinator!.runningStatus != RunningStatus.stopped,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: Row(
            children: [
              // Image.asset(
              //   'assets/ic_title.png',
              //   color: Colors.white,
              //   width: 32,
              //   height: 32,
              //   fit: BoxFit.contain,
              // ),
              // const SizedBox(width: 4),
              Text(
                l10n.appTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF4080FF),
          actions: [
            // 定位详细显示切换
            if (_coordinator!.runningStatus == RunningStatus.running)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: _switchPositionVisibility,
                  child: Icon(
                    _positionVisibility == 0
                        ? Icons.visibility_off
                        : Icons.visibility,
                    color: _positionVisibility == 1
                        ? const Color(0xFFA0C0FF)
                        : Colors.white,
                    size: 32,
                  ),
                ),
              ),
            // 开始/停止
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: switch (_coordinator!.runningStatus) {
                  RunningStatus.stopped => _start,
                  // starting でも即時停止できる
                  RunningStatus.running || RunningStatus.starting => _stop,
                },
                child: Icon(
                  _coordinator!.runningStatus == RunningStatus.running
                      ? Icons.stop_circle
                      : Icons.play_circle_filled, // starting/stopped
                  color: _coordinator!.runningStatus == RunningStatus.starting
                      ? const Color(0xFFA0C0FF)
                      : Colors.white,
                  size: 32,
                ),
              ),
            ),
            // 设置（starting 中は無効化）
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: _coordinator!.runningStatus == RunningStatus.starting
                    ? null
                    : _showSettingsDialog,
                child: Icon(
                  Icons.settings,
                  color: _coordinator!.runningStatus == RunningStatus.starting
                      ? const Color(0xFFA0C0FF)
                      : Colors.white,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                if (_coordinator!.runningStatus == RunningStatus.running &&
                    _positionVisibility > 0) ...[
                  _buildPositionCard(l10n), // 上部可隐藏: 位置信息
                  const SizedBox(height: 4),
                ],
                Expanded(
                  child: _buildStationResultsCard(l10n), // 中部可滚动: 车站列表
                ),
              ],
            ),
          ),
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
      final results = await Future.wait([
        Settings.load(),
        StationManager.load(),
      ]);
      final settings = results[0] as Settings;
      final manager = results[1] as StationManager;

      final coordinator = Coordinator(l10n, active, settings, manager);
      _coordinator = coordinator;

      // UI handler 登録
      coordinator.addLocationResultHandler(_handleLocationResultReceived,
          active: true);
      coordinator.addRunningStatusHandler(_handleRunningStatusChanged);

      await coordinator.init();

      if (!mounted) return;
      setState(() {
        _settings = settings;
        _manager = manager;
      });
    } catch (e) {
      // 其他错误（文件读取失败等）
      debugPrint(e.toString());
      _showSnackBar(l10n.errorMsg('$e'), isError: true);
    }
  }

  void _handleLocationResultReceived(
    PositionResult? positionResult,
    List<StationResult>? stationResults,
  ) {
    if (!mounted) return;
    setState(() {});
  }

  void _handleRunningStatusChanged(RunningStatus runningStatus) {
    if (!mounted) return;
    setState(() {});
  }

  // ── ボタンイベント ────────────────────────────────────────────────

  /// 起動ボタン押下時
  /// 権限リクエスト + 定位開始
  Future<void> _start() async {
    if (_settings == null) return;

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

  // void _showEkidataWebsite() {
  //   launchUrl(Common.uriEkidata, mode: LaunchMode.externalApplication);
  // }

  // ── Snack Bar ──────────────────────────────────────────────────

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: isError ? Colors.white : Colors.grey.shade800,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isError
            ? const Color(0xFFFF4030) // Colors.red.shade700
            : const Color(0xFFA0C0FF), // Colors.indigo.shade300
        elevation: 2,
        behavior: SnackBarBehavior.floating,
        // action: SnackBarAction(
        //     label: 'WEBSITE', onPressed: () => _showEkidataWebsite()),
        // showCloseIcon: !isError,
        // closeIconColor: Colors.grey.shade800,
        // persist: true,
      ),
    );
  }

  // ── Settings Dialog ───────────────────────────────────────────────────

  void _showSettingsDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.white.withValues(alpha: 0.5),
      builder: (context) => SettingsDialog(
        _settings!,
        _manager!,
        onSave: (settings) async {
          await settings.save();
          setState(() {
            _settings = settings;
          });
          // 无论运行状态如何都立即反映
          // （LocationProcessor 内部会根据 stream 状态自行判断）
          _coordinator?.changeSettings(settings);
        },
      ),
    );
  }

  // ── Position card ────────────────────────────────────────────────

  Widget _buildPositionCard(L10n l10n) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // タイトル行
            Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Icon(
                    Icons.my_location,
                    color: const Color(0xFF4080FF), // Colors.indigo.shade700
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _positionVisibility == 1
                        ? l10n.currentLocation
                        : l10n.currentLocationStatus,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _buildPositionResult(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionResult(L10n l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _PositionRow(
                  label: l10n.latitude,
                  value:
                      _coordinator!.positionResult!.latitude.toStringAsFixed(6),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _PositionRow(
                  label: l10n.longitude,
                  value: _coordinator!.positionResult!.longitude
                      .toStringAsFixed(6),
                ),
              ),
            ],
          ),
          if (_positionVisibility == 2) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _PositionRow(
                    label: l10n.speed,
                    value: _coordinator!.positionResult!.speedString,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _PositionRow(
                    label: l10n.accuracy,
                    value: _coordinator!.positionResult!.accuracyString,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _PositionRow(
                    label: l10n.heading,
                    value: l10n
                        .direction(_coordinator!.positionResult!.headingIndex),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _PositionRow(
                    label: l10n.timestamp,
                    value: _coordinator!.positionResult!.timestampString,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Service results card ─────────────────────────────────────────

  Widget _buildStationResultsCard(L10n l10n) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // タイトル行
            Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Icon(
                    Icons.radar,
                    color: const Color(0xFFFFC000), // Colors.orange.shade700
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.nearbyStations,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _buildStationResultsExpanded(l10n), // リスト部分のみスクロール
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationResultsExpanded(L10n l10n) {
    if (_manager!.count > 0) {
      if (_coordinator!.runningStatus == RunningStatus.stopped) {
        return Align(
          alignment: Alignment.topCenter,
          child: Text(
            l10n.notStarted,
            style: const TextStyle(color: Colors.grey),
          ),
        );
      } else if (_coordinator!.runningStatus == RunningStatus.starting) {
        return Align(
          alignment: Alignment.topCenter,
          child: Text(
            l10n.waitingForLocation,
            style: const TextStyle(color: Colors.grey),
          ),
        );
      } else {
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
          itemCount: _coordinator!.stationResults!.length,
          itemBuilder: (context, index) {
            final stationResult = _coordinator!.stationResults![index];

            return _StationTile(
              index: index,
              name: stationResult.name ?? '',
              distance: stationResult.distanceInUnit,
              direction: l10n.direction(stationResult.bearingIndex),
              part: _settings!.stationCount.part(index),
            );
          },
        );
      }
    } else {
      return Align(
        alignment: Alignment.topCenter,
        child: Text(
          l10n.countStations(0),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
  }
}

// ── Position row ─────────────────────────────────────────────────

class _PositionRow extends StatelessWidget {
  final String label;
  final String value;

  const _PositionRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: TextStyle(
            color: Colors.grey.shade800,
            // fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
    StationCountPart.friend: Colors.grey.shade100,
    StationCountPart.event: const Color(0xFFDCECFF),
    StationCountPart.radar: const Color(0xFFE0F4E8),
    StationCountPart.natsume: const Color(0xFFFFF9E0),
  };

  @override
  Widget build(BuildContext context) {
    final isNearest = index == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: isNearest ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: isNearest
            ? const Color(0xFFFFF0E0) // Colors.orange.shade50
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isNearest
              ? const Color(0xFFFFC000) // Colors.orange.shade700
              : _partBorderColors[part]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: isNearest
                  ? const Color(0xFFFFC000) // Colors.orange.shade700
                  : _partFillColors[part]!,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: isNearest ? Colors.white : Colors.grey.shade800,
                  fontSize: 12,
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
                fontSize: 12,
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
                  ? const Color(0xFFFFC000) // Colors.orange.shade700
                  : _partFillColors[part]!,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                direction,
                style: TextStyle(
                  color: isNearest ? Colors.white : Colors.grey.shade800,
                  fontSize: 12,
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
                  ? const Color(0xFFFFC000) // Colors.orange.shade700
                  : _partFillColors[part]!,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                distance,
                style: TextStyle(
                  color: isNearest ? Colors.white : Colors.grey.shade800,
                  fontSize: 12,
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
