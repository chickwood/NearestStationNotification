import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../common.dart';
import '../consumer/history_consumer.dart';
import '../l10n.dart';
import '../manager/history_manager.dart';
import '../manager/settings_manager.dart';
import '../manager/station_manager.dart';
import '../service/history_backup_service.dart';
import 'history_date_picker.dart';

enum _HistoryViewMode { day, month }

class HistoryPage extends StatefulWidget {
  final HistoryConsumer historyConsumer;
  final HistoryManager historyManager;
  final HistoryBackupService historyBackupService;
  final StationManager stationManager;
  final HistorySettingsManager settingsManager;
  final Future<bool> Function(bool value) onHistoryMergeViewChanged;
  final int date;

  const HistoryPage(
    this.historyConsumer,
    this.historyManager,
    this.historyBackupService,
    this.stationManager,
    this.settingsManager,
    this.onHistoryMergeViewChanged,
    this.date, {
    super.key,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ResetableState<HistoryPage> {
  _HistoryViewMode _mode = _HistoryViewMode.day;
  late int _selectedDate;
  late int _selectedMonth;

  List<HistoryRecord> _dayRecords = const [];
  _MonthCache? _monthCache;

  final Map<int, List<_HistoryBlock>> _blocksByDay = {};
  List<int> _storedMonths = const [];
  List<int> _availableMonths = const [];
  List<int> _availableDates = const [];

  bool _loading = true;
  int _loadGeneration = 0;
  bool _pickingMonth = false;
  bool _hasHistory = false;
  late bool _mergeView;
  bool _savingMergeView = false;

  bool _backupWasBusy = false;
  HistoryBackupAction? _runningAction;

  @override
  void initState() {
    super.initState();

    _mergeView = widget.settingsManager.historyMergeView;
    _selectedDate = widget.date;
    _selectedMonth = Common.monthDateOf(widget.date);
    _mode =
        _selectedMonth == Common.currentMonth()
            ? _HistoryViewMode.day
            : _HistoryViewMode.month;

    _backupWasBusy = widget.historyBackupService.busy.value;
    widget.historyConsumer.pendingRevision.addListener(_handlePendingChanged);
    widget.historyBackupService.busy.addListener(_handleBackupChanged);
    widget.historyBackupService.progress.addListener(_handleBackupChanged);

    unawaited(_loadAvailableMonths());
    unawaited(_reload());
  }

  @override
  void dispose() {
    widget.historyConsumer.pendingRevision.removeListener(
      _handlePendingChanged,
    );
    widget.historyBackupService.busy.removeListener(_handleBackupChanged);
    widget.historyBackupService.progress.removeListener(_handleBackupChanged);
    super.dispose();
  }

  // ── データ読み込み ────────────────────────────────────────────────

  Future<void> _loadAvailableMonths() async {
    try {
      final stored = await widget.historyManager.listMonths();
      final currentMonthDays = await widget.historyManager.listDays(
        Common.currentMonth(),
      );
      if (!mounted) return;
      _applyAvailableMonths(stored, currentMonthDays);
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    }
  }

  void _applyAvailableMonths(List<int> stored, List<int> currentMonthDays) {
    final currentMonth = Common.currentMonth();
    final months = <int>{...stored, currentMonth};
    final dates = <int>{...currentMonthDays};

    for (final record in widget.historyConsumer.pendingRecords) {
      final date = Common.dateOfEpoch(record.epoch);
      if (Common.monthDateOf(date) == currentMonth) dates.add(date);
      months.add(Common.monthDateOf(date));
    }
    final sorted = months.toList()..sort((a, b) => b.compareTo(a));
    final sortedDates = dates.toList()..sort();

    setState(() {
      _storedMonths = stored;
      _availableMonths = List<int>.unmodifiable(sorted);
      _availableDates = List<int>.unmodifiable(sortedDates);
      _hasHistory =
          stored.isNotEmpty || widget.historyConsumer.pendingRecords.isNotEmpty;
    });
  }

  Future<void> _reload() async {
    final generation = ++_loadGeneration;
    _blocksByDay.clear();

    try {
      if (_mode == _HistoryViewMode.day) {
        final records = await widget.historyManager.readDayFile(_selectedDate);
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _dayRecords = HistoryRecord.mergeDedup([
            ...records,
            ..._pendingForDay(),
          ]);
          _loading = false;
        });
      } else {
        final records = await widget.historyManager.readMonth(_selectedMonth);
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _monthCache = _MonthCache.build(records, _mergeView);
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (_mode == _HistoryViewMode.day) {
          _dayRecords = const [];
        } else {
          _monthCache = _MonthCache.build(const [], _mergeView);
        }
        _loading = false;
      });
    }
  }

  List<HistoryRecord> _pendingForDay([List<HistoryRecord>? pending]) {
    final source = pending ?? widget.historyConsumer.pendingRecords;
    return [
      for (final record in source)
        if (Common.dateOfEpoch(record.epoch) == _selectedDate) record,
    ];
  }

  Future<void> _selectDay(int date) async {
    _loadGeneration++;
    setState(() {
      _mode = _HistoryViewMode.day;
      _selectedDate = date;
      _selectedMonth = Common.monthDateOf(date);
      _dayRecords = const [];
      _monthCache = null;
      _blocksByDay.clear();
      _loading = true;
    });
    await _reload();
  }

  Future<void> _selectMonth(int month) async {
    _loadGeneration++;
    setState(() {
      _mode = _HistoryViewMode.month;
      _selectedMonth = month;
      _dayRecords = const [];
      _monthCache = null;
      _blocksByDay.clear();
      _loading = true;
    });
    await _reload();
  }

  // ── 購読 ────────────────────────────────────────────────────────

  void _handlePendingChanged() {
    if (!mounted) return;

    final pending = widget.historyConsumer.pendingRecords;
    final months = <int>{..._storedMonths, Common.currentMonth()};
    for (final record in pending) {
      months.add(Common.monthDateOf(Common.dateOfEpoch(record.epoch)));
    }
    final sorted = months.toList()..sort((a, b) => b.compareTo(a));

    setState(() {
      _availableMonths = List<int>.unmodifiable(sorted);
      if (pending.isNotEmpty) _hasHistory = true;

      if (_mode == _HistoryViewMode.day && !_loading) {
        _dayRecords = HistoryRecord.mergeDedup([
          ..._dayRecords,
          ..._pendingForDay(pending),
        ]);
        _blocksByDay.remove(_selectedDate);
      }
    });
  }

  void _handleBackupChanged() {
    if (!mounted) return;

    final busy = widget.historyBackupService.busy.value;
    final finished = _backupWasBusy && !busy;
    _backupWasBusy = busy;

    if (finished) {
      unawaited(_refreshAfterBackup());
      return;
    }

    resetState();
  }

  Future<void> _refreshAfterBackup() async {
    await _loadAvailableMonths();
    if (!mounted) return;
    await _reload();
    if (mounted) resetState();
  }

  Future<void> _toggleMergeView() async {
    if (_savingMergeView) return;

    final next = !_mergeView;
    setState(() {
      _savingMergeView = true;
      _mergeView = next;
      _blocksByDay.clear();
      final cache = _monthCache;
      if (cache != null) _monthCache = cache.withMergeView(next);
    });

    final succeeded = await widget.onHistoryMergeViewChanged(next);
    if (!mounted) return;

    setState(() {
      if (!succeeded) {
        _mergeView = !next;
        _blocksByDay.clear();
        final cache = _monthCache;
        if (cache != null) _monthCache = cache.withMergeView(!next);
      }
      _savingMergeView = false;
    });
  }

  // ── カレンダー ──────────────────────────────────────────────────

  Future<void> _pickMonth() async {
    if (_pickingMonth) return;

    _pickingMonth = true;
    try {
      await _loadAvailableMonths();
      if (!mounted) return;

      final picked = await showHistoryDatePicker(
        context,
        availableMonths: _availableMonths,
        availableDates: _availableDates,
        initialMonth: _selectedMonth,
        selectedDate: _mode == _HistoryViewMode.day ? _selectedDate : null,
      );
      if (picked == null || !mounted) return;

      if (picked >= 10000101) {
        await _selectDay(picked);
      } else {
        await _selectMonth(picked);
      }
    } finally {
      _pickingMonth = false;
      if (mounted) resetState();
    }
  }

  // ── バックアップ ────────────────────────────────────────────────

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
            backgroundColor: Theme.of(context).colorScheme.surface,
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

  // ── ブロック ────────────────────────────────────────────────────

  List<_HistoryBlock> _blocksForDay(int date, List<HistoryRecord> records) =>
      _blocksByDay.putIfAbsent(date, () => _buildBlocks(records));

  // ── 描画 ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final backupBusy = widget.historyBackupService.busy.value;
    final calendarDisabled = backupBusy || _pickingMonth;
    final exportDisabled = backupBusy || _runningAction != null || !_hasHistory;
    final importDisabled = backupBusy || _runningAction != null;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4080FF),
        foregroundColor: Colors.white,
        title: Text(l10n.historyTitle),
        actions: [
          AppBarAction(
            onPressed: _savingMergeView ? null : _toggleMergeView,
            icon: Icon(_mergeView ? Icons.view_agenda : Icons.view_list),
            color: _mergeView ? Colors.white : const Color(0xFFA0C0FF),
            disabledColor: _mergeView ? Colors.white : const Color(0xFFA0C0FF),
            tooltip: l10n.historyMergeViewState(_mergeView),
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
          if (backupBusy)
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
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _buildBody(L10n l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_mode == _HistoryViewMode.day) {
      return _buildDayView(l10n);
    }
    return _buildMonthView(l10n);
  }

  Widget _buildDayView(L10n l10n) {
    final records = _dayRecords;
    if (records.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _DayHeader(date: _selectedDate, records: records),
          ),
          Expanded(child: _buildEmpty(l10n.historyDayEmpty)),
        ],
      );
    }

    if (_mergeView) {
      final blocks = _blocksForDay(_selectedDate, records);
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: blocks.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _DayHeader(date: _selectedDate, records: records);
          }
          final block = blocks[index - 1];
          return _HistoryBlockCard(
            key: ValueKey(block.startEpoch),
            stationManager: widget.stationManager,
            records: block.records,
          );
        },
        separatorBuilder:
            (context, index) =>
                index == 0
                    ? const SizedBox(height: 4)
                    : const Divider(height: 16),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: records.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _DayHeader(date: _selectedDate, records: records);
        }
        return _HistoryRecordCard(
          record: records[records.length - index],
          stationManager: widget.stationManager,
        );
      },
      separatorBuilder:
          (context, index) =>
              index == 0
                  ? const SizedBox(height: 4)
                  : const Divider(height: 16),
    );
  }

  Widget _buildMonthView(L10n l10n) {
    final cache = _monthCache;
    final days = cache?.days ?? const <_DayMeta>[];
    if (cache == null || days.isEmpty) {
      return _buildEmpty(l10n.historyDayEmpty);
    }

    final mergeView = cache.mergeView;
    final index = cache.index;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverList.builder(
            itemCount: index.itemCount,
            itemBuilder: (context, itemIndex) {
              final dayIndex = index.dayIndexOf(itemIndex);
              final day = days[dayIndex];
              final offset = itemIndex - index.starts[dayIndex];

              if (offset == 0) {
                return _DayHeader(date: day.date, records: day.records);
              }

              final contentIndex = offset - 1;

              if (mergeView) {
                final blocks = _blocksForDay(day.date, day.records);
                if (contentIndex >= blocks.length) {
                  return const SizedBox.shrink();
                }
                final block = blocks[contentIndex];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HistoryBlockCard(
                      key: ValueKey('${day.date}-${block.startEpoch}'),
                      stationManager: widget.stationManager,
                      records: block.records,
                    ),
                    const Divider(height: 16),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HistoryRecordCard(
                    record: day.records[day.records.length - 1 - contentIndex],
                    stationManager: widget.stationManager,
                  ),
                  const Divider(height: 16),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(String message) => Center(
    child: Text(message, style: TextStyle(color: Colors.grey.shade600)),
  );
}

// ── 月キャッシュ / 日次索引 ────────────────────────────────────────

class _DayMeta {
  final int date;
  final List<HistoryRecord> records;
  final int blockCount;

  const _DayMeta({
    required this.date,
    required this.records,
    required this.blockCount,
  });
}

class _MonthCache {
  final List<_DayMeta> days;
  final _TimelineIndex index;
  final bool mergeView;

  const _MonthCache._(this.days, this.index, this.mergeView);

  factory _MonthCache.build(List<HistoryRecord> records, bool mergeView) {
    final grouped = <int, List<HistoryRecord>>{};
    for (final record in records) {
      (grouped[Common.dateOfEpoch(record.epoch)] ??= <HistoryRecord>[]).add(
        record,
      );
    }

    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final days = <_DayMeta>[
      for (final date in dates)
        _DayMeta(
          date: date,
          records: grouped[date]!,
          blockCount: _countBlocks(grouped[date]!),
        ),
    ];

    return _MonthCache._(
      days,
      _TimelineIndex.build(days, mergeView),
      mergeView,
    );
  }

  _MonthCache withMergeView(bool mergeView) =>
      _MonthCache._(days, _TimelineIndex.build(days, mergeView), mergeView);
}

class _TimelineIndex {
  final List<int> starts;
  final int itemCount;

  const _TimelineIndex._(this.starts, this.itemCount);

  factory _TimelineIndex.build(List<_DayMeta> days, bool mergeView) {
    final starts = List<int>.filled(days.length + 1, 0);
    var total = 0;

    for (var i = 0; i < days.length; i++) {
      starts[i] = total;
      total += 1 + (mergeView ? days[i].blockCount : days[i].records.length);
    }
    starts[days.length] = total;

    return _TimelineIndex._(starts, total);
  }

  int dayIndexOf(int itemIndex) {
    var low = 0;
    var high = starts.length - 2;

    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (starts[mid] <= itemIndex) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}

// ── 日付ヘッダー ──────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  final int date;
  final List<HistoryRecord> records;

  const _DayHeader({required this.date, required this.records});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final dateLabel = date == Common.today() ? 'Today' : _dateLabel(date);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          Text(
            dateLabel,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.historyDayCount(records.length),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── 5分ブロック ───────────────────────────────────────────────────

class _HistoryBlock {
  final int startEpoch;
  final List<HistoryRecord> records;

  _HistoryBlock({required this.startEpoch, required this.records});
}

int _countBlocks(List<HistoryRecord> ascending) {
  final window = Common.historyMergeWindow.inMilliseconds;
  var count = 0;
  int? startEpoch;

  for (final record in ascending) {
    if (startEpoch == null || record.epoch - startEpoch > window) {
      count++;
      startEpoch = record.epoch;
    }
  }

  return count;
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

// ── 表示コンポーネント ────────────────────────────────────────────

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
