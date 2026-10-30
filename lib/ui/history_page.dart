import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nearest_station_notification/manager/settings_manager.dart';

import '../common.dart';
import '../consumer/history_consumer.dart';
import '../l10n.dart';
import '../manager/history_manager.dart';
import '../manager/station_manager.dart';
import '../service/history_backup_service.dart';
import 'history_date_picker.dart';

class HistoryPage extends StatefulWidget {
  final HistoryManager historyManager;
  final HistoryBackupService historyBackupService;
  final StationManager stationManager;
  final HistorySettingsManager settingsManager;
  final HistoryConsumer historyConsumer;

  const HistoryPage(
    this.historyManager,
    this.historyBackupService,
    this.stationManager,
    this.settingsManager,
    this.historyConsumer, {
    super.key,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ResetableState<HistoryPage> {
  late int _selectedMonth;
  late int _earliestMonth;

  List<int> _months = const [];
  List<int> _dates = const [];

  bool _loading = true;
  int _loadId = 0;

  bool _backupWasBusy = false;
  HistoryBackupAction? _runningAction;

  @override
  void initState() {
    super.initState();

    _selectedMonth = Common.currentMonth();
    _earliestMonth = _selectedMonth;

    _backupWasBusy = widget.historyBackupService.busy.value;
    widget.historyBackupService.busy.addListener(_handleBackupChanged);
    widget.historyBackupService.progress.addListener(_handleBackupChanged);
    widget.historyConsumer.pendingRevision.addListener(_handlePendingChanged);
    widget.historyConsumer.flushCount.addListener(_handleFlushChanged);

    unawaited(_loadMonths(_selectedMonth));
  }

  @override
  void dispose() {
    widget.historyBackupService.busy.removeListener(_handleBackupChanged);
    widget.historyBackupService.progress.removeListener(_handleBackupChanged);
    widget.historyConsumer.pendingRevision.removeListener(
      _handlePendingChanged,
    );
    widget.historyConsumer.flushCount.removeListener(_handleFlushChanged);
    super.dispose();
  }

  void _handlePendingChanged() => resetState();

  void _handleFlushChanged() {
    if (!mounted) return;
    unawaited(_loadMonths(_selectedMonth, quiet: true));
  }

  void _handleBackupChanged() {
    if (!mounted) return;

    final busy = widget.historyBackupService.busy.value;
    final finished = _backupWasBusy && !busy;
    _backupWasBusy = busy;

    if (finished) {
      unawaited(_refresh());
      return;
    }

    resetState();
  }

  List<int> get _visibleDates {
    final dates = List<int>.of(_dates);
    final month = _selectedMonth;
    for (final record in widget.historyConsumer.pendingRecords) {
      final date = Common.dateOfEpoch(record.epoch);
      if (Common.monthDateOf(date) != month) continue;
      if (!dates.contains(date)) dates.add(date);
    }
    dates.sort((a, b) => b.compareTo(a));
    return dates;
  }

  bool get _hasHistory =>
      _months.isNotEmpty || widget.historyConsumer.pendingRecords.isNotEmpty;

  Future<void> _loadMonths(int month, {bool quiet = false}) async {
    final loadId = ++_loadId;
    if (!quiet) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final storedMonths = await widget.historyManager.listMonths();
      final current = Common.currentMonth();
      final months = List<int>.of(storedMonths);
      for (final record in widget.historyConsumer.pendingRecords) {
        final monthDate = Common.monthDateOf(Common.dateOfEpoch(record.epoch));
        if (!months.contains(monthDate)) months.add(monthDate);
      }
      months.sort((a, b) => b.compareTo(a));

      var earliest = months.isEmpty ? current : months.last;
      if (earliest > current) earliest = current;

      var target = month;
      if (target < earliest) target = earliest;
      if (target > current) target = current;

      final days = await widget.historyManager.listDays(target);

      if (!mounted || loadId != _loadId) return;
      setState(() {
        _months = months;
        _earliestMonth = earliest;
        _selectedMonth = target;
        _dates = days;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      if (!mounted || loadId != _loadId) return;
      if (quiet) return;
      setState(() {
        _dates = const [];
        _loading = false;
      });
    }
  }

  Future<void> _loadMonth(int month) async {
    final loadId = ++_loadId;
    setState(() {
      _selectedMonth = month;
      _loading = true;
      _dates = const [];
    });

    try {
      final days = await widget.historyManager.listDays(month);
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _dates = days;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _dates = const [];
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _loadMonths(_selectedMonth);
  }

  Future<void> _previousMonth() async {
    await _loadMonth(Common.addMonths(_selectedMonth, -1));
  }

  Future<void> _nextMonth() async {
    await _loadMonth(Common.addMonths(_selectedMonth, 1));
  }

  Future<void> _pickMonth() async {
    if (_loading) return;

    final availableMonths = <int>{
      ..._months,
      for (final record in widget.historyConsumer.pendingRecords)
        Common.monthDateOf(Common.dateOfEpoch(record.epoch)),
    };

    final picked = await showHistoryDatePicker(
      context,
      availableMonths: availableMonths,
      initialMonth: _selectedMonth,
    );
    if (picked == null || !mounted) return;

    if (picked >= 10000101) {
      final month = Common.monthDateOf(picked);
      if (month != _selectedMonth) {
        await _loadMonth(month);
        if (!mounted) return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => HistoryDayPage(
                widget.historyConsumer,
                widget.historyManager,
                widget.stationManager,
                widget.settingsManager,
                picked,
              ),
        ),
      );
    } else {
      await _loadMonth(picked);
    }
  }

  Future<void> _export() async {
    if (_runningAction != null || widget.historyBackupService.busy.value) {
      return;
    }
    setState(() => _runningAction = HistoryBackupAction.export);
    await widget.historyConsumer.flush();
    if (!mounted) return;

    final payload = await widget.historyBackupService.createExport(
      widget.historyManager,
    );
    if (payload == null) {
      if (mounted) setState(() => _runningAction = null);
      return;
    }

    if (!mounted) {
      widget.historyBackupService.finishExport();
      return;
    }

    try {
      final savedUri = await FilePicker.saveFile(
        fileName: payload.fileName,
        bytes: payload.bytes,
        mimeType: 'application/zip',
      );
      widget.historyBackupService.finishExport(savedPath: savedUri?.toString());
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      widget.historyBackupService.finishExport(error: e);
    }

    if (!mounted) return;
    setState(() => _runningAction = null);
  }

  Future<void> _import() async {
    final l10n = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            content: Text(l10n.historyImportConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
              ),
            ],
          ),
    );

    if (!mounted ||
        confirmed != true ||
        _runningAction != null ||
        widget.historyBackupService.busy.value) {
      return;
    }

    setState(() => _runningAction = HistoryBackupAction.import);

    // 未落盘记录を先に書き切り、导入合并时の取りこぼしを防ぐ
    await widget.historyConsumer.flush();
    if (!mounted) return;

    String? path;
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      path = picked?.path;
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      if (mounted) setState(() => _runningAction = null);
      return;
    }

    if (path == null) {
      if (mounted) setState(() => _runningAction = null);
      return;
    }

    await widget.historyBackupService.import(widget.historyManager, path);
    if (!mounted) return;
    setState(() => _runningAction = null);
  }

  bool get _canPrevious => _selectedMonth > _earliestMonth;

  bool get _canNext => _selectedMonth < Common.currentMonth();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final busy = widget.historyBackupService.busy.value;
    final calendarDisabled = busy || _loading;
    final exportDisabled = busy || _runningAction != null || !_hasHistory;
    final importDisabled = busy || _runningAction != null;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          AppBarAction(
            onPressed: busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.historyRefresh,
          ),
          AppBarAction(
            onPressed: calendarDisabled ? null : _pickMonth,
            icon: const Icon(Icons.calendar_month),
            tooltip: l10n.historyJumpMonth,
          ),
          AppBarAction(
            onPressed: exportDisabled ? null : _export,
            icon: const Icon(Icons.save_alt),
            tooltip: l10n.historyExport,
          ),
          AppBarAction(
            onPressed: importDisabled ? null : _import,
            icon: const Icon(Icons.file_open),
            tooltip: l10n.historyImport,
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy)
            Column(
              children: [
                if (_runningAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _runningAction == HistoryBackupAction.export
                          ? l10n.historyExporting
                          : l10n.historyImporting,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                LinearProgressIndicator(
                  value:
                      widget.historyBackupService.progress.value > 0
                          ? widget.historyBackupService.progress.value
                          : null,
                  color: const Color(0xFF4080FF),
                  backgroundColor: const Color(0xFFDCECFF),
                ),
              ],
            ),
          _buildMonthNavigator(l10n),
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _buildMonthNavigator(L10n l10n) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            onPressed: _canPrevious ? _previousMonth : null,
            icon: const Icon(Icons.chevron_left),
            tooltip: l10n.historyPrevMonth,
            color: const Color(0xFF4080FF),
            disabledColor: Colors.grey.shade300,
          ),
          Expanded(
            child: Center(
              child: Text(
                _monthLabel(_selectedMonth),
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _canNext ? _nextMonth : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: l10n.historyNextMonth,
            color: const Color(0xFF4080FF),
            disabledColor: Colors.grey.shade300,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(L10n l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final dates = _visibleDates;
    if (dates.isEmpty) {
      return Center(
        child: Text(
          l10n.historyMonthEmpty,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: dates.length,
      itemBuilder: (context, index) => _buildDateRow(dates[index]),
      separatorBuilder: (context, index) => const SizedBox(height: 4),
    );
  }

  Widget _buildDateRow(int date) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap:
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder:
                  (_) => HistoryDayPage(
                    widget.historyConsumer,
                    widget.historyManager,
                    widget.stationManager,
                    widget.settingsManager,
                    date,
                  ),
            ),
          ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text(
                  _dateLabel(date),
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade600, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class HistoryDayPage extends StatefulWidget {
  final HistoryConsumer historyConsumer;
  final HistoryManager historyManager;
  final StationManager stationManager;
  final HistorySettingsManager settingsManager;
  final int date;

  const HistoryDayPage(
    this.historyConsumer,
    this.historyManager,
    this.stationManager,
    this.settingsManager,
    this.date, {
    super.key,
  });

  @override
  State<HistoryDayPage> createState() => _HistoryDayPageState();
}

class _HistoryDayPageState extends ResetableState<HistoryDayPage> {
  List<HistoryRecord>? _records;
  List<HistoryRecord> _diskRecords = const [];
  int _loadId = 0;
  bool _syncingFlush = false;

  @override
  void initState() {
    super.initState();
    widget.historyConsumer.pendingRevision.addListener(_handlePendingChanged);
    widget.historyConsumer.flushCount.addListener(_handleHistoryFlushChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.historyConsumer.pendingRevision.removeListener(
      _handlePendingChanged,
    );
    widget.historyConsumer.flushCount.removeListener(
      _handleHistoryFlushChanged,
    );
    super.dispose();
  }

  List<HistoryRecord> _pendingRecords() => widget.historyConsumer.pendingRecords
      .where((record) => Common.dateOfEpoch(record.epoch) == widget.date)
      .toList(growable: false);

  List<HistoryRecord> _mergeRecords() =>
      HistoryRecord.mergeDedup([..._diskRecords, ..._pendingRecords()]);

  void _handlePendingChanged() {
    if (!mounted) return;
    if (_records == null || _syncingFlush) return;
    setState(() {
      _records = _mergeRecords();
    });
  }

  void _handleHistoryFlushChanged() {
    if (!mounted) return;
    _syncingFlush = true;
    unawaited(_reloadFromDisk());
  }

  Future<void> _reloadFromDisk() async {
    final loadId = ++_loadId;
    try {
      final records = await widget.historyManager.readDay(widget.date);
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _diskRecords = records;
        _records = _mergeRecords();
      });
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    } finally {
      if (loadId == _loadId) _syncingFlush = false;
    }
  }

  Future<void> _load() async {
    final loadId = ++_loadId;
    setState(() {
      _records = null;
    });
    _syncingFlush = false;

    try {
      final records = await widget.historyManager.readDay(widget.date);
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _diskRecords = records;
        _records = _mergeRecords();
      });
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _records = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4080FF),
        foregroundColor: Colors.white,
        title: Text(_dateLabel(widget.date)),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.historyRefresh,
          ),
        ],
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(L10n l10n) {
    final records = _records;
    if (records == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (records.isEmpty) {
      return Center(
        child: Text(
          l10n.historyDayEmpty,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    final count = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        l10n.historyDayCount(records.length),
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      ),
    );

    if (widget.settingsManager.historyMergeView) {
      final blocks = _buildBlocks(records);
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: blocks.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return count;
          final block = blocks[index - 1];
          return _HistoryBlockCard(
            key: ValueKey(block.startEpoch),
            stationManager: widget.stationManager,
            records: block.records,
          );
        },
        separatorBuilder: (context, index) {
          if (index == 0) return const SizedBox(height: 4);
          return const Divider(height: 16);
        },
      );
    }

    final sorted = [...records]..sort((a, b) => b.epoch.compareTo(a.epoch));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return count;
        return _HistoryRecordCard(
          record: sorted[index - 1],
          stationManager: widget.stationManager,
        );
      },
      separatorBuilder: (context, index) {
        if (index == 0) return const SizedBox(height: 4);
        return const Divider(height: 16);
      },
    );
  }
}

class _HistoryBlock {
  final int startEpoch;
  final List<HistoryRecord> records;

  _HistoryBlock({required this.startEpoch, required this.records});
}

List<_HistoryBlock> _buildBlocks(List<HistoryRecord> records) {
  final sorted = [...records]..sort((a, b) => a.epoch.compareTo(b.epoch));
  final blocks = <_HistoryBlock>[];

  for (final record in sorted) {
    if (blocks.isEmpty ||
        record.epoch - blocks.last.startEpoch >
            Common.historyMergeWindow.inMilliseconds) {
      blocks.add(_HistoryBlock(startEpoch: record.epoch, records: [record]));
    } else {
      blocks.last.records.add(record);
    }
  }

  return blocks..sort((a, b) => b.startEpoch.compareTo(a.startEpoch));
}

class _HistoryBlockCard extends StatefulWidget {
  final StationManager stationManager;
  final List<HistoryRecord> records;

  const _HistoryBlockCard({
    super.key,
    required this.stationManager,
    required this.records,
  });

  @override
  State<_HistoryBlockCard> createState() => _HistoryBlockCardState();
}

class _HistoryBlockCardState extends State<_HistoryBlockCard> {
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final groups = <int, _HistoryStationGroup>{};

    for (final record in widget.records) {
      final group = groups.putIfAbsent(
        record.gcd,
        () => _HistoryStationGroup(
          gcd: record.gcd,
          name: widget.stationManager.getStationNameByGcd(record.gcd),
        ),
      );
      group.records.add(record);
    }

    final children = <Widget>[];
    for (final group in groups.values) {
      children.add(
        _HistoryStationGroupView(
          group: group,
          expanded: _expanded.contains(group.gcd),
          onToggle: () {
            setState(() {
              if (!_expanded.add(group.gcd)) {
                _expanded.remove(group.gcd);
              }
            });
          },
        ),
      );
      children.add(const SizedBox(height: 4));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _HistoryStationGroup {
  final int gcd;
  final String? name;
  final List<HistoryRecord> records = [];

  _HistoryStationGroup({required this.gcd, this.name});
}

class _HistoryStationGroupView extends StatelessWidget {
  final _HistoryStationGroup group;
  final bool expanded;
  final VoidCallback onToggle;

  const _HistoryStationGroupView({
    required this.group,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final hasMore = group.records.length > Common.historyBlockRowLimit;
    final visibleCount =
        expanded ? group.records.length : Common.historyBlockRowLimit;
    final count =
        visibleCount < group.records.length
            ? visibleCount
            : group.records.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HistoryStationTile(gcd: group.gcd, name: group.name),
        const SizedBox(height: 2),
        for (var i = 0; i < count; i++)
          _HistoryRecordRow(
            record: group.records[i],
            trailing:
                hasMore && i == Common.historyBlockRowLimit - 1
                    ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onToggle,
                      child: Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 18,
                        color: Colors.grey.shade600,
                      ),
                    )
                    : null,
          ),
      ],
    );
  }
}

class _HistoryRecordCard extends StatelessWidget {
  final HistoryRecord record;
  final StationManager stationManager;

  const _HistoryRecordCard({
    required this.record,
    required this.stationManager,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HistoryStationTile(
          gcd: record.gcd,
          name: stationManager.getStationNameByGcd(record.gcd),
        ),
        const SizedBox(height: 2),
        _HistoryRecordRow(record: record),
      ],
    );
  }
}

class _HistoryStationTile extends StatelessWidget {
  final int gcd;
  final String? name;

  const _HistoryStationTile({required this.gcd, required this.name});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final displayName = name == null || name!.isEmpty ? '--' : name!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.train, size: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  l10n.historyStationId(gcd),
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRecordRow extends StatelessWidget {
  final HistoryRecord record;
  final Widget? trailing;

  const _HistoryRecordRow({required this.record, this.trailing});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final labelStyle = TextStyle(color: Colors.grey.shade600, fontSize: 11);
    final valueStyle = TextStyle(
      color: Colors.grey.shade800,
      fontSize: 11,
      fontWeight: FontWeight.bold,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Row(
        children: [
          Text(l10n.historyTime, style: labelStyle),
          const SizedBox(width: 4),
          Text(_timeLabel(record.epoch), style: valueStyle),
          const SizedBox(width: 10),
          Text(l10n.historyCoordinates, style: labelStyle),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _coordinateLabel(record),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: valueStyle,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 2), trailing!],
        ],
      ),
    );
  }
}

String _monthLabel(int month) =>
    '${(month ~/ 100).toString().padLeft(4, '0')}-${_two(month % 100)}';

String _dateLabel(int date) =>
    '${Common.yearOf(date).toString().padLeft(4, '0')}'
    '-${_two(Common.monthOf(date))}-${_two(Common.dayOf(date))}';

String _two(int value) => value.toString().padLeft(2, '0');

String _timeLabel(int epoch) {
  final time = DateTime.fromMillisecondsSinceEpoch(epoch);
  String two(int value) => value.toString().padLeft(2, '0');
  String three(int value) => value.toString().padLeft(3, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
      '${three(time.millisecond)}';
}

String _coordinateLabel(HistoryRecord record) =>
    '${record.latitude.toStringAsFixed(6)}, '
    '${record.longitude.toStringAsFixed(6)}';
