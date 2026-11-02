import 'package:flutter/material.dart';

/// 返回值：
/// - 8 位 `yyyyMMdd`：当前月选择了具体日期
/// - 6 位 `yyyyMM`：往期月份选择了月份
/// - `null`：取消
///
/// [availableMonths] 为扫描到的可查看月份（`yyyyMM`）；
/// 当前月会自动加入，仅这些月份及其所在年份可选择。
///
/// [availableDates] 为当前月有记录的日期（`yyyyMMdd`）；
/// 当前月的今天始终可选，今天之前的日期只有存在于该集合时才可选。
///
/// [selectedDate] 为当前展示的日期（`yyyyMMdd`），用于高亮；月视图则高亮
/// [initialMonth] 对应的月份。
Future<int?> showHistoryDatePicker(
  BuildContext context, {
  required Iterable<int> availableMonths,
  required Iterable<int> availableDates,
  int? initialMonth,
  int? selectedDate,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final currentMonth = current.year * 100 + current.month;
  final today = current.year * 10000 + current.month * 100 + current.day;

  final months = <int>{
    for (final month in availableMonths)
      if (_isValidMonth(month) && month <= currentMonth) month,
    currentMonth,
  };
  final sorted = months.toList()..sort();

  var initial = initialMonth ?? currentMonth;
  if (!months.contains(initial)) {
    initial = sorted.lastWhere(
      (month) => month <= initial,
      orElse: () => sorted.first,
    );
  }

  return showDialog<int>(
    context: context,
    builder:
        (context) => _HistoryDatePickerDialog(
          availableMonths: months,
          availableDates: availableDates.toSet(),
          currentMonth: currentMonth,
          today: today,
          initialMonth: initial,
          selectedDate: selectedDate,
        ),
  );
}

bool _isValidMonth(int month) =>
    month >= 100001 && month <= 999912 && month % 100 >= 1 && month % 100 <= 12;

class _HistoryDatePickerDialog extends StatefulWidget {
  const _HistoryDatePickerDialog({
    required this.availableMonths,
    required this.availableDates,
    required this.currentMonth,
    required this.today,
    required this.initialMonth,
    required this.selectedDate,
  });

  final Set<int> availableMonths;
  final Set<int> availableDates;
  final int currentMonth;
  final int today;
  final int initialMonth;
  final int? selectedDate;

  @override
  State<_HistoryDatePickerDialog> createState() =>
      _HistoryDatePickerDialogState();
}

class _HistoryDatePickerDialogState extends State<_HistoryDatePickerDialog> {
  late int _year;
  late bool _dayMode;
  late final List<int> _years;

  @override
  void initState() {
    super.initState();
    _year = widget.initialMonth ~/ 100;
    _dayMode = widget.initialMonth == widget.currentMonth;
    _years =
        widget.availableMonths.map((month) => month ~/ 100).toSet().toList()
          ..sort();
    if (!_years.contains(_year)) _year = _years.last;
  }

  int get _yearIndex => _years.indexOf(_year);
  bool get _hasPastMonths =>
      widget.availableMonths.any((month) => month < widget.currentMonth);
  bool get _canPreviousYear => _yearIndex > 0;
  bool get _canNextYear => _yearIndex >= 0 && _yearIndex < _years.length - 1;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dayMode ? _buildDayView(context) : _buildMonthView(context),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _canPreviousYear ? _previousYear : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '$_year',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            IconButton(
              onPressed: _canNextYear ? _nextYear : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var month = 1; month <= 12; month++) _buildMonthCell(month),
          ],
        ),
      ],
    );
  }

  Widget _buildMonthCell(int month) {
    final key = _year * 100 + month;
    final enabled = widget.availableMonths.contains(key);
    final selected = key == widget.initialMonth;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => _selectMonth(key) : null,
      child: Container(
        decoration: _cellDecoration(selected: selected, enabled: enabled),
        child: Center(
          child: Text(
            month.toString().padLeft(2, '0'),
            style: _cellTextStyle(selected: selected, enabled: enabled),
          ),
        ),
      ),
    );
  }

  void _previousYear() {
    final index = _yearIndex;
    if (index <= 0) return;
    setState(() => _year = _years[index - 1]);
  }

  void _nextYear() {
    final index = _yearIndex;
    if (index < 0 || index >= _years.length - 1) return;
    setState(() => _year = _years[index + 1]);
  }

  void _selectMonth(int month) {
    if (month == widget.currentMonth) {
      setState(() => _dayMode = true);
      return;
    }
    Navigator.of(context).pop(month);
  }

  Widget _buildDayView(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final year = widget.currentMonth ~/ 100;
    final month = widget.currentMonth % 100;
    final todayDay = widget.today % 100;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final leadingDays = DateUtils.firstDayOffset(year, month, localizations);
    final firstWeekday = localizations.firstDayOfWeekIndex;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (_hasPastMonths)
              IconButton(
                onPressed: () => setState(() => _dayMode = false),
                icon: const Icon(Icons.chevron_left),
                tooltip: localizations.backButtonTooltip,
              )
            else
              const SizedBox(width: 48),
            Expanded(
              child: Center(
                child: Text(
                  localizations.formatMonthYear(DateTime(year, month)),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    localizations.narrowWeekdays[(firstWeekday + i) % 7],
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          children: [
            for (var i = 0; i < leadingDays; i++) const SizedBox.shrink(),
            for (var day = 1; day <= daysInMonth; day++)
              _buildDayCell(
                context,
                day,
                enabled:
                    day <= todayDay &&
                    (day == todayDay ||
                        widget.availableDates.contains(
                          widget.currentMonth * 100 + day,
                        )),
                selected:
                    widget.selectedDate == widget.currentMonth * 100 + day,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    int day, {
    required bool enabled,
    required bool selected,
  }) {
    final date = widget.currentMonth * 100 + day;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => Navigator.of(context).pop(date) : null,
      child: Container(
        decoration: _cellDecoration(selected: selected, enabled: enabled),
        child: Center(
          child: Text(
            '$day',
            style: _cellTextStyle(selected: selected, enabled: enabled),
          ),
        ),
      ),
    );
  }

  BoxDecoration _cellDecoration({
    required bool selected,
    required bool enabled,
  }) {
    final borderColor =
        selected
            ? const Color(0xFF4080FF)
            : enabled
            ? Colors.grey.shade300
            : Colors.transparent;

    return BoxDecoration(
      color:
          selected
              ? const Color(0xFFDCECFF)
              : enabled
              ? Colors.white
              : Colors.transparent,
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(8),
    );
  }

  TextStyle _cellTextStyle({required bool selected, required bool enabled}) {
    return TextStyle(
      color: enabled ? Colors.grey.shade800 : Colors.grey,
      fontSize: 12,
      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
    );
  }
}
