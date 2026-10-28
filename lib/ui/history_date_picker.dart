import 'package:flutter/material.dart';

/// 返回值：
/// - 8 位 `yyyyMMdd`：当前月选择了具体日期
/// - 6 位 `yyyyMM`：往期月份选择了月份
/// - `null`：取消
///
/// [availableMonths] 为扫描到的可查看月份（`yyyyMM`）；
/// 当前月会自动加入，仅这些月份及其所在年份可选择。
Future<int?> showHistoryDatePicker(
  BuildContext context, {
  required Iterable<int> availableMonths,
  int? initialMonth,
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
          currentMonth: currentMonth,
          today: today,
          initialMonth: initial,
        ),
  );
}

bool _isValidMonth(int month) =>
    month >= 100001 && month <= 999912 && month % 100 >= 1 && month % 100 <= 12;

class _HistoryDatePickerDialog extends StatefulWidget {
  const _HistoryDatePickerDialog({
    required this.availableMonths,
    required this.currentMonth,
    required this.today,
    required this.initialMonth,
  });

  final Set<int> availableMonths;
  final int currentMonth;
  final int today;
  final int initialMonth;

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
            for (var month = 1; month <= 12; month++)
              _buildMonthCell(context, month),
          ],
        ),
      ],
    );
  }

  Widget _buildMonthCell(BuildContext context, int month) {
    final key = _year * 100 + month;
    final enabled = widget.availableMonths.contains(key);
    final isCurrent = key == widget.currentMonth;

    return OutlinedButton(
      onPressed: enabled ? () => _selectMonth(key) : null,
      style:
          isCurrent
              ? OutlinedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              )
              : null,
      child: Text(month.toString().padLeft(2, '0')),
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
                enabled: day <= todayDay,
                isToday: day == todayDay,
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
    required bool isToday,
  }) {
    return TextButton(
      onPressed:
          enabled
              ? () => Navigator.of(context).pop(widget.currentMonth * 100 + day)
              : null,
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const CircleBorder(),
        backgroundColor:
            isToday ? Theme.of(context).colorScheme.primaryContainer : null,
      ),
      child: Text('$day'),
    );
  }
}
