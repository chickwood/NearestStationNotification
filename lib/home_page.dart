import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app_settings.dart';
import 'common.dart';
import 'l10n.dart';
import 'notification_service.dart';
import 'settings_dialog.dart';
import 'station_manager.dart';

class HomePage extends StatefulWidget {
  final NotificationService service;

  const HomePage({
    super.key,
    required this.service,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppSettings? _settings;
  // StatusCard 用
  // BIN ファイル情報
  int _count = 0; // 駅数
  int _date = 0; // タイムスタンプ
  int _size = 0; // データサイズ
  int _positionVisibility = 0; // 坐标显示/关闭
  RunningStatus _runningStatus = RunningStatus.stopped; // 開始フラグ

  List<StationResult>? _stationResults;
  PositionResult? _positionResult;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initialize();
    });
  }

  @override
  void dispose() {
    widget.service.stopLocating();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WithForegroundTask(
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
            if (_runningStatus == RunningStatus.running &&
                _positionResult != null)
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
                onTap: switch (_runningStatus) {
                  RunningStatus.stopped => _start,
                  RunningStatus.running => _stop,
                  _ => null, // starting
                },
                child: Icon(
                  _runningStatus == RunningStatus.running
                      ? Icons.stop_circle
                      : Icons.play_circle_filled, // starting/stopped
                  color: _runningStatus == RunningStatus.starting
                      ? const Color(0xFFA0C0FF)
                      : Colors.white,
                  size: 32,
                ),
              ),
            ),
            // 设置
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: _showSettingsDialog,
                child: const Icon(
                  Icons.settings,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(
              children: [
                if (_runningStatus == RunningStatus.running &&
                    _positionResult != null &&
                    _positionVisibility > 0) ...[
                  _buildPositionCard(l10n), // 上部可隐藏: 位置信息
                  const SizedBox(height: 4),
                ],
                Expanded(
                  child: _buildServiceResultsCard(l10n), // 中部可滚动: 车站列表
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// アプリ起動時に呼び出初期化処理
  Future<void> _initialize() async {
    final l10n = AppLocalizations.of(context);
    try {
      final results = await Future.wait([
        AppSettings.load(),
        StationManager.loadInfo(),
      ]);
      final settings = results[0] as AppSettings;
      final manager = results[1] as StationManager;

      setState(() {
        _settings = settings;
        _count = manager.count;
        _date = manager.date;
        _size = manager.size;
      });

      // await widget.service.initService();
    } catch (e) {
      // 其他错误（文件读取失败等）
      debugPrint(e.toString());
      _showSnackBar(l10n.errorMsg('$e'), isError: true);
    }
  }

  /// 起動ボタン押下時
  /// 権限リクエスト + 定位開始
  Future<void> _start() async {
    if (_settings == null) return;

    debugPrint(DateTime.now().toString());
    debugPrint(Common.event().toString());

    setState(() {
      _runningStatus = RunningStatus.starting;
    });

    await widget.service.startLocating(
      _settings!,
      onLocated: (positionResult, stationResults) {
        setState(() {
          _positionResult = positionResult;
          _stationResults = stationResults;
        });
      },
      onRunningStatusChanged: (runningStatus) {
        setState(() {
          _runningStatus = runningStatus;
        });
      },
    );
  }

  /// 停止ボタン押下時の処理
  Future<void> _stop() async {
    await widget.service.stopLocating();
    // 按钮外观变更
    // 在 service 内部由 startLocating 时传入的 onRunningStatusChanged 触发
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
        info: (
          settings: _settings!,
          count: _count,
          date: _date,
          size: _size,
        ),
        onSave: (settings) async {
          await settings.save();
          setState(() {
            _settings = settings;
          });
          if (_runningStatus == RunningStatus.running) {
            widget.service.changeSettings(settings);
          }
        },
      ),
    );
  }

  // ── Position card ────────────────────────────────────────────────

  Widget _buildPositionCard(AppLocalizations l10n) {
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
                    l10n.currentStatus,
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

  Widget _buildPositionResult(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          if (_positionVisibility == 2) ...[
            Row(
              children: [
                Expanded(
                  child: _PositionRow(
                    label: l10n.latitude,
                    value: _positionResult!.latitude.toStringAsFixed(6),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _PositionRow(
                    label: l10n.longitude,
                    value: _positionResult!.longitude.toStringAsFixed(6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Expanded(
                child: _PositionRow(
                  label: l10n.speed,
                  value: _positionResult!.speedString,
                ),
              ),
              if (_positionVisibility == 1) const SizedBox(width: 16),
              if (_positionVisibility == 2) const SizedBox(width: 24),
              Expanded(
                child: _PositionRow(
                  label: l10n.accuracy,
                  value: _positionResult!.accuracyString,
                ),
              ),
              if (_positionVisibility == 1) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: _PositionRow(
                    label: l10n.heading,
                    value: l10n.direction(_positionResult!.headingIndex),
                  ),
                ),
              ],
            ],
          ),
          if (_positionVisibility == 2) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _PositionRow(
                    label: l10n.heading,
                    value: l10n.direction(_positionResult!.headingIndex),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _PositionRow(
                    label: l10n.timestamp,
                    value: _positionResult!.timestampString,
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

  Widget _buildServiceResultsCard(AppLocalizations l10n) {
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
                    l10n.nearestStations,
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
              child: _buildServiceResultsExpanded(l10n), // リスト部分のみスクロール
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceResultsExpanded(AppLocalizations l10n) {
    if (_count > 0) {
      if (_runningStatus == RunningStatus.stopped) {
        return Align(
          alignment: Alignment.topCenter,
          child: Text(
            l10n.notStarted,
            style: const TextStyle(color: Colors.grey),
          ),
        );
      } else if (_runningStatus == RunningStatus.starting ||
          _positionResult == null ||
          (_stationResults?.isEmpty ?? true)) {
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
          itemCount: _stationResults!.length,
          itemBuilder: (context, index) {
            final stationResult = _stationResults![index];

            return _StationTile(
              index: index,
              name: stationResult.name,
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
              : switch (part) {
                  StationCountPart.friend => Colors.grey.shade300,
                  StationCountPart.event =>
                    const Color(0xFFB8D8FF), // Colors.indigo.shade200
                  StationCountPart.radar =>
                    const Color(0xFFC0E8CC), // Colors.green.shade200
                  StationCountPart.natsume =>
                    const Color(0xFFFFF0B0), // Colors.orange.shade200
                },
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
                  : switch (part) {
                      StationCountPart.friend => Colors.grey.shade100,
                      StationCountPart.event =>
                        const Color(0xFFDCECFF), // Colors.indigo.shade100
                      StationCountPart.radar =>
                        const Color(0xFFE0F4E8), // Colors.green.shade100
                      StationCountPart.natsume =>
                        const Color(0xFFFFF9E0), // Colors.orange.shade100
                    },
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
                  : switch (part) {
                      StationCountPart.friend => Colors.grey.shade100,
                      StationCountPart.event =>
                        const Color(0xFFDCECFF), // Colors.indigo.shade100
                      StationCountPart.radar =>
                        const Color(0xFFE0F4E8), // Colors.green.shade100
                      StationCountPart.natsume =>
                        const Color(0xFFFFF9E0), // Colors.orange.shade100
                    },
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
                  : switch (part) {
                      StationCountPart.friend => Colors.grey.shade100,
                      StationCountPart.event =>
                        const Color(0xFFDCECFF), // Colors.indigo.shade100
                      StationCountPart.radar =>
                        const Color(0xFFE0F4E8), // Colors.green.shade100
                      StationCountPart.natsume =>
                        const Color(0xFFFFF9E0), // Colors.orange.shade100
                    },
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
