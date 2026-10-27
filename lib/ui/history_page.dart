import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nearest_station_notification/manager/settings_manager.dart';

import '../common.dart';
import '../consumer/history_consumer.dart';
import '../l10n.dart';
import '../manager/history_manager.dart';
import '../manager/station_manager.dart';
import '../service/history_backup_service.dart';

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
  late DateTime _selectedMonth;
  late DateTime _earliestMonth;

  List<int> _months = const [];
  List<int> _dates = const [];

  bool _loading = true;
  int _loadId = 0;

  bool _backupWasBusy = false;
  HistoryBackupAction? _runningAction;

  @override
  void initState() {
    super.initState();

    _selectedMonth = _monthOf(DateTime.now());
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
    final month = Common.monthDateOf(Common.dateOf(_selectedMonth));
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

  Future<void> _loadMonths(DateTime month, {bool quiet = false}) async {
    final loadId = ++_loadId;
    if (!quiet) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final storedMonths = await widget.historyManager.listMonths();
      final current = _monthOf(DateTime.now());
      final months = List<int>.of(storedMonths);
      for (final record in widget.historyConsumer.pendingRecords) {
        final monthDate = Common.monthDateOf(Common.dateOfEpoch(record.epoch));
        if (!months.contains(monthDate)) months.add(monthDate);
      }
      months.sort((a, b) => b.compareTo(a));

      var earliest =
          months.isEmpty
              ? current
              : DateTime(months.last ~/ 100, months.last % 100);
      if (earliest.isAfter(current)) earliest = current;

      var target = month;
      if (target.isBefore(earliest)) target = earliest;
      if (target.isAfter(current)) target = current;

      final days = await widget.historyManager.listDays(
        Common.monthDateOf(Common.dateOf(target)),
      );

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

  Future<void> _loadMonth(DateTime month) async {
    final loadId = ++_loadId;
    setState(() {
      _selectedMonth = month;
      _loading = true;
      _dates = const [];
    });

    try {
      final days = await widget.historyManager.listDays(
        Common.monthDateOf(Common.dateOf(month)),
      );
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
    await _loadMonth(DateTime(_selectedMonth.year, _selectedMonth.month - 1));
  }

  Future<void> _nextMonth() async {
    await _loadMonth(DateTime(_selectedMonth.year, _selectedMonth.month + 1));
  }

  Future<void> _pickMonth() async {
    final l10n = L10n.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = _months.isEmpty ? today : _earliestMonth;

    var initial = _selectedMonth;
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(today)) initial = today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: today,
      helpText: l10n.historyJumpMonth,
    );

    if (picked == null || !mounted) return;
    await _loadMonth(_monthOf(picked));
  }

  Future<void> _export() async {
    if (_runningAction != null || widget.historyBackupService.busy.value) {
      return;
    }
    setState(() => _runningAction = HistoryBackupAction.export);
    await widget.historyConsumer.flush();
    await widget.historyBackupService.export(widget.historyManager);
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

    await widget.historyBackupService.import(widget.historyManager);
    if (!mounted) return;
    setState(() => _runningAction = null);
  }

  bool get _canPrevious => _selectedMonth.isAfter(_earliestMonth);

  bool get _canNext => _selectedMonth.isBefore(_monthOf(DateTime.now()));

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final busy = widget.historyBackupService.busy.value;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4080FF),
        foregroundColor: Colors.white,
        title: Text(l10n.historyTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.historyRefresh,
            onPressed: busy ? null : _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: l10n.historyJumpMonth,
            onPressed: busy ? null : _pickMonth,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: l10n.historyExport,
            onPressed:
                busy || _runningAction != null || !_hasHistory ? null : _export,
          ),
          IconButton(
            icon: const Icon(Icons.file_open),
            tooltip: l10n.historyImport,
            onPressed: busy || _runningAction != null ? null : _import,
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
            icon: const Icon(Icons.chevron_left),
            tooltip: l10n.historyPrevMonth,
            color: const Color(0xFF4080FF),
            disabledColor: Colors.grey.shade300,
            onPressed: _canPrevious ? _previousMonth : null,
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
            icon: const Icon(Icons.chevron_right),
            tooltip: l10n.historyNextMonth,
            color: const Color(0xFF4080FF),
            disabledColor: Colors.grey.shade300,
            onPressed: _canNext ? _nextMonth : null,
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: GestureDetector(
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
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

class _HistoryDayPageState extends State<HistoryDayPage> {
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
            icon: const Icon(Icons.refresh),
            tooltip: l10n.historyRefresh,
            onPressed: _load,
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
          return const Divider(height: 8, indent: 8, endIndent: 8);
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
        return const Divider(height: 8, indent: 8, endIndent: 8);
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

DateTime _monthOf(DateTime time) => DateTime(time.year, time.month);

String _monthLabel(DateTime time) =>
    '${time.year.toString().padLeft(4, '0')}-${_two(time.month)}';

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
