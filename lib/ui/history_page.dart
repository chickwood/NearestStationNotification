import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nearest_station_notification/service/settings_save_service.dart';

import '../common.dart';
import '../consumer/history_consumer.dart';
import '../l10n.dart';
import '../manager/history_manager.dart';
import '../manager/settings_manager.dart';
import '../manager/station_manager.dart';
import '../service/history_backup_service.dart';
import 'history_date_picker.dart';

class HistoryPage extends StatefulWidget {
  final HistoryConsumer historyConsumer;
  final HistoryManager historyManager;
  final HistoryBackupService historyBackupService;
  final StationManager stationManager;
  final SettingsManager settingsManager;
  final SettingsSaveService settingsSaveService;

  const HistoryPage(
    this.historyConsumer,
    this.historyManager,
    this.historyBackupService,
    this.stationManager,
    this.settingsManager,
    this.settingsSaveService, {
    super.key,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ResetableState<HistoryPage> {
  late int _selectedDateOrMonth;

  _MonthCache? _monthCache;

  final Map<int, List<_HistoryBlock>> _blocksByDay = {};
  late _StationNameCache _nameCache;

  List<int> _availableDates = const [];
  List<int> _availableMonths = const [];
  List<int> _storedMonths = const [];

  bool _loading = true;
  int _loadGeneration = 0;
  bool _showingPicker = false;
  bool _hasHistory = false;
  bool _mergeView = false;
  bool _savingMergeView = false;

  bool _backupWasBusy = false;
  HistoryBackupAction? _runningAction;

  @override
  void initState() {
    super.initState();

    _mergeView = widget.settingsManager.historyMergeView;
    _nameCache = _StationNameCache(widget.stationManager);

    _selectedDateOrMonth = Common.today();

    _backupWasBusy = widget.historyBackupService.busy.value;
    widget.historyConsumer.pendingRevision.addListener(_handlePendingChanged);
    widget.historyBackupService.busy.addListener(_handleBackupChanged);
    widget.historyBackupService.progress.addListener(_handleBackupChanged);

    unawaited(_loadAvailableMonths());
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.stationManager, widget.stationManager)) {
      _nameCache = _StationNameCache(widget.stationManager);
    }
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
    if (!Common.isValidDate(_selectedDateOrMonth) &&
        !Common.isValidMonth(_selectedDateOrMonth)) {
      return;
    }

    final generation = ++_loadGeneration;
    _blocksByDay.clear();
    _nameCache.clear();

    try {
      final stored = Common.isValidDate(_selectedDateOrMonth)
          ? await widget.historyManager.readDayFile(_selectedDateOrMonth)
          : await widget.historyManager.readMonth(_selectedDateOrMonth);
      final records = HistoryRecord.mergeDedup([
        ...stored,
        ..._pendingForScope(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _monthCache = _MonthCache.build(records, _mergeView);
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _monthCache = _MonthCache.build(const [], _mergeView);
        _loading = false;
      });
    }
  }

  List<HistoryRecord> _pendingForScope([List<HistoryRecord>? pending]) {
    if (!Common.isValidDate(_selectedDateOrMonth) &&
        !Common.isValidMonth(_selectedDateOrMonth)) {
      return [];
    }

    return _pendingWhere((record) {
      final recordDate = Common.dateOfEpoch(record.epoch);
      return Common.isValidDate(_selectedDateOrMonth)
          ? recordDate == _selectedDateOrMonth
          : Common.monthDateOf(recordDate) == _selectedDateOrMonth;
    }, pending);
  }

  List<HistoryRecord> _pendingWhere(
    bool Function(HistoryRecord record) test, [
    List<HistoryRecord>? pending,
  ]) {
    final source = pending ?? widget.historyConsumer.pendingRecords;
    return [
      for (final record in source)
        if (test(record)) record,
    ];
  }

  Future<void> _selectDateOrMonth(int picked) async {
    _loadGeneration++;
    setState(() {
      _selectedDateOrMonth = picked;
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
      _mergePendingIntoCache(pending);
    });
  }

  void _mergePendingIntoCache(List<HistoryRecord> pending) {
    final cache = _monthCache;
    if (_loading || cache == null) return;

    final scoped = _pendingForScope(pending);
    if (scoped.isEmpty) return;

    for (final record in scoped) {
      _blocksByDay.remove(Common.dateOfEpoch(record.epoch));
    }

    _monthCache = _MonthCache.build(
      HistoryRecord.mergeDedup([
        for (final dayMeta in cache.dayMetas) ...dayMeta.records,
        ...scoped,
      ]),
      _mergeView,
    );
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
    });
    final succeeded = await _changeHistoryMergeView(next);

    if (!mounted) return;

    setState(() {
      if (succeeded) {
        _mergeView = next;
        _blocksByDay.clear();
        final cache = _monthCache;
        if (cache != null) _monthCache = cache.withMergeView(next);
      }
      _savingMergeView = false;
    });
  }

  // ── Change history merge view ──────────────────────────────────

  Future<bool> _changeHistoryMergeView(bool value) async {
    if (value && !widget.settingsManager.historyEnabled) return false;
    if (_mergeView == value) return true;

    final updated = widget.settingsManager.copyWith(historyMergeView: value);
    return widget.settingsSaveService.save(updated);
  }

  // ── カレンダー ──────────────────────────────────────────────────

  Future<void> _showPicker() async {
    if (_showingPicker) return;

    _showingPicker = true;
    try {
      await _loadAvailableMonths();
      if (!mounted) return;

      final picked = await showHistoryDatePicker(
        context,
        availableMonths: _availableMonths,
        availableDates: _availableDates,
        selectedDateOrMonth: _selectedDateOrMonth,
      );
      if (!mounted || picked == null) return;

      await _selectDateOrMonth(picked);
    } finally {
      _showingPicker = false;
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
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        content: Text(l10n.historyImportConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
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
    final mergeViewDisabled = backupBusy || _savingMergeView;
    final calendarDisabled = backupBusy || _showingPicker;
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
            onPressed: mergeViewDisabled ? null : _toggleMergeView,
            icon: _mergeView
                ? const Icon(Icons.view_list)
                : const Icon(Icons.view_agenda),
            tooltip: l10n.historyMergeViewState(_mergeView),
          ),
          AppBarAction(
            onPressed: calendarDisabled ? null : _showPicker,
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
          if (backupBusy) ...[
            if (_runningAction != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _runningAction == HistoryBackupAction.export
                      ? l10n.historyExporting
                      : l10n.historyImporting,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12.0),
                ),
              ),
            LinearProgressIndicator(
              value: widget.historyBackupService.progress.value > 0
                  ? widget.historyBackupService.progress.value
                  : null,
              color: const Color(0xFF4080FF),
              backgroundColor: const Color(0xFFDCECFF),
            ),
          ],
          Expanded(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildBodyExpanded(l10n), // 车站列表: リスト部分のみスクロール
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyExpanded(L10n l10n) {
    if (_loading) {
      return const Align(
        alignment: Alignment.topCenter,
        child: CircularProgressIndicator(),
      );
    }

    final monthCache = _monthCache;
    final dayMetas = monthCache?.dayMetas ?? const <_DayMeta>[];
    if (monthCache == null || dayMetas.isEmpty) {
      return Expanded(
        child: Column(
          children: [
            if (Common.isValidDate(_selectedDateOrMonth)) ...[
              _DayHeader(date: _selectedDateOrMonth, records: const []),
              const SizedBox(height: 4),
            ],
            Align(
              alignment: Alignment.topCenter,
              child: Text(
                l10n.historyEmpty,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    final mergeView = monthCache.mergeView;
    final timelineIndex = monthCache.timelineIndex;
    return Expanded(
      child: CustomScrollView(
        slivers: [
          SliverList.separated(
            itemCount: timelineIndex.total,
            itemBuilder: (_, index) {
              final dayIndex = timelineIndex.dayIndexOf(index);
              final dayMeta = dayMetas[dayIndex];
              final offset = index - timelineIndex.days[dayIndex];

              if (offset == 0) {
                return Column(
                  children: [
                    _DayHeader(date: _selectedDateOrMonth, records: const []),
                    const SizedBox(height: 4),
                  ],
                );
              }

              final contentIndex = offset - 1;

              if (mergeView) {
                final blocks = _blocksForDay(dayMeta.date, dayMeta.records);
                if (contentIndex >= blocks.length) {
                  return const SizedBox.shrink();
                }
                final block = blocks[contentIndex];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HistoryBlockCard(
                      key: ValueKey(
                        '${dayMeta.date}-${block.gcd}-${block.startEpoch}',
                      ),
                      index: blocks.length - contentIndex,
                      records: block.records,
                      nameCache: _nameCache,
                    ),
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HistoryBlockCard(
                      index: dayMeta.records.length - contentIndex,
                      records: [
                        dayMeta.records[dayMeta.records.length -
                            1 -
                            contentIndex],
                      ],
                      nameCache: _nameCache,
                    ),
                  ],
                );
              }
            },
            separatorBuilder: (_, _) {
              return const SizedBox(height: 4);
            },
          ),
        ],
      ),
    );
  }
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
  final List<_DayMeta> dayMetas;
  final _TimelineIndex timelineIndex;
  final bool mergeView;

  const _MonthCache._(this.dayMetas, this.timelineIndex, this.mergeView);

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

  _MonthCache withMergeView(bool mergeView) => _MonthCache._(
    dayMetas,
    _TimelineIndex.build(dayMetas, mergeView),
    mergeView,
  );
}

class _TimelineIndex {
  final List<int> days;
  final int total;

  const _TimelineIndex._(this.days, this.total);

  factory _TimelineIndex.build(List<_DayMeta> dayMetas, bool mergeView) {
    final days = List<int>.filled(dayMetas.length + 1, 0);
    var total = 0;

    for (var i = 0; i < dayMetas.length; i++) {
      days[i] = total;
      total +=
          1 + (mergeView ? dayMetas[i].blockCount : dayMetas[i].records.length);
    }
    days[dayMetas.length] = total;

    return _TimelineIndex._(days, total);
  }

  int dayIndexOf(int itemIndex) {
    var low = 0;
    var high = days.length - 2;

    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (days[mid] <= itemIndex) {
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
    final dateLabel = date == Common.today()
        ? l10n.historyToday
        : Common.dateString(
            Common.yearOf(date),
            Common.monthOf(date),
            Common.dayOf(date),
          );

    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Text(
            dateLabel,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.historyDayCount(records.length),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.0),
          ),
        ],
      ),
    );
  }
}

// ── 5分ブロック ───────────────────────────────────────────────────

class _HistoryBlock {
  final int gcd;
  final int startEpoch;
  final List<HistoryRecord> records;

  _HistoryBlock({
    required this.gcd,
    required this.startEpoch,
    required this.records,
  });

  int get lastEpoch => records.last.epoch;
}

int _countBlocks(List<HistoryRecord> ascending) {
  final window = Common.historyMergeWindow.inMilliseconds;
  final starts = <int, int>{};
  var count = 0;

  for (final record in ascending) {
    final start = starts[record.gcd];
    if (start == null || record.epoch - start > window) {
      count++;
      starts[record.gcd] = record.epoch;
    }
  }

  return count;
}

List<_HistoryBlock> _buildBlocks(List<HistoryRecord> records) {
  final sorted = [...records]..sort((a, b) => a.epoch.compareTo(b.epoch));
  final currentByStation = <int, _HistoryBlock>{};
  final blocks = <_HistoryBlock>[];

  for (final record in sorted) {
    final current = currentByStation[record.gcd];
    if (current == null ||
        record.epoch - current.startEpoch >
            Common.historyMergeWindow.inMilliseconds) {
      final block = _HistoryBlock(
        gcd: record.gcd,
        startEpoch: record.epoch,
        records: [record],
      );
      currentByStation[record.gcd] = block;
      blocks.add(block);
    } else {
      current.records.add(record);
    }
  }

  blocks.sort((a, b) {
    final byLast = b.lastEpoch.compareTo(a.lastEpoch);
    if (byLast != 0) return byLast;

    final byStart = b.startEpoch.compareTo(a.startEpoch);
    if (byStart != 0) return byStart;

    return a.gcd.compareTo(b.gcd);
  });

  return blocks;
}

// ── 表示コンポーネント ────────────────────────────────────────────

/// 页面级 gcd → name 缓存，随页面生命周期释放
class _StationNameCache {
  final StationManager _stationManager;
  final Map<int, String?> _namesByGcd = {};

  _StationNameCache(this._stationManager);

  String? resolve(int gcd) {
    if (_namesByGcd.containsKey(gcd)) return _namesByGcd[gcd];

    final node = _stationManager.getNodeByGcd(gcd);
    final name = node == null ? null : _stationManager.getGcdName(node).$2;
    _namesByGcd[gcd] = name;
    return name;
  }

  void clear() => _namesByGcd.clear();
}

class _HistoryBlockCard extends StatelessWidget {
  final int index;
  final _StationNameCache nameCache;
  final List<HistoryRecord> records;

  const _HistoryBlockCard({
    super.key,
    required this.index,
    required this.nameCache,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <int, _HistoryStationGroup>{};

    for (final record in records) {
      final group = groups.putIfAbsent(
        record.gcd,
        () => _HistoryStationGroup(
          gcd: record.gcd,
          name: nameCache.resolve(record.gcd),
        ),
      );
      group.records.add(record);
    }

    final children = <Widget>[];
    for (final group in groups.values) {
      children.add(_HistoryStationGroupView(group: group, index: index));
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
  final int index;
  final _HistoryStationGroup group;

  const _HistoryStationGroupView({required this.index, required this.group});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HistoryStationTile(index: index, gcd: group.gcd, name: group.name),
        const SizedBox(height: 2),
        for (final record in group.records.reversed)
          _HistoryRecordRow(record: record),
      ],
    );
  }
}

class _HistoryStationTile extends StatelessWidget {
  final int index;
  final int gcd;
  final String? name;

  const _HistoryStationTile({
    required this.index,
    required this.gcd,
    required this.name,
  });

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
              width: 40,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 12.0,
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
                  l10n.historyGcd(gcd),
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 12.0,
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

  const _HistoryRecordRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final timestamp = DateTime.fromMillisecondsSinceEpoch(record.epoch);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Row(
        children: [
          _HistoryNearestCell(
            label: l10n.timestamp,
            value: Common.timeString(
              timestamp.hour,
              timestamp.minute,
              timestamp.second,
            ),
          ),
          const SizedBox(width: 8),
          _HistoryNearestCell(
            label: l10n.latitude,
            value: record.latitude.toStringAsFixed(6),
          ),
          const SizedBox(width: 8),
          _HistoryNearestCell(
            label: l10n.longitude,
            value: record.longitude.toStringAsFixed(6),
          ),
        ],
      ),
    );
  }
}

class _HistoryNearestCell extends StatelessWidget {
  final String label;
  final String value;

  const _HistoryNearestCell({required this.label, required this.value});

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
