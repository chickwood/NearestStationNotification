import 'package:flutter/material.dart';

import '../common.dart';
import '../l10n.dart';
import '../manager/settings_manager.dart';
import '../service/settings_save_service.dart';

// ── Settings Dialog ───────────────────────────────────────────────

class SettingsDialog extends StatefulWidget {
  final SettingsManager settings;
  final SettingsSaveService settingsSaveService;

  const SettingsDialog(
    this.settings, {
    super.key,
    required this.settingsSaveService,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsManager _draft;

  @override
  void initState() {
    super.initState();

    // 弹窗内操作的临时副本，关闭则丢弃
    _draft = widget.settings.copyWith();
    widget.settingsSaveService.lastResult.addListener(_handleResult);
    widget.settingsSaveService.busy.addListener(_handleBusyChanged);
  }

  @override
  void dispose() {
    widget.settingsSaveService.lastResult.removeListener(_handleResult);
    widget.settingsSaveService.busy.removeListener(_handleBusyChanged);
    super.dispose();
  }

  void _handleResult() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleBusyChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Dialog(
      elevation: 2,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // タイトル行
            Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  const Icon(Icons.settings, color: Color(0xFF4080FF)),
                  const SizedBox(width: 4),
                  Text(
                    l10n.settingsDialogTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 検出駅数 ────────────────────────────────────────────
                  _SectionLabel(label: l10n.settingsStationCount),
                  const SizedBox(height: 8),
                  _SegmentedRow<StationCount>(
                    values: const [StationCount.game, StationCount.max],
                    selected: _draft.stationCount,
                    labelOf: (v) => v.label,
                    onChanged:
                        (v) => setState(
                          () => _draft = _draft.copyWith(stationCount: v),
                        ),
                  ),
                  // ── 位置情報取得頻度 ────────────────────────────────────
                  const SizedBox(height: 12),
                  _SectionLabel(label: l10n.settingsLocationInterval),
                  const SizedBox(height: 8),
                  _SegmentedRow<LocationInterval>(
                    values: LocationInterval.values,
                    selected: _draft.locationInterval,
                    labelOf:
                        (v) => l10n.settingsLocationIntervalLabel(v.seconds),
                    onChanged:
                        (v) => setState(
                          () => _draft = _draft.copyWith(locationInterval: v),
                        ),
                  ),
                  // // ── 通知方式 ────────────────────────────────────────────
                  // const SizedBox(height: 12),
                  // _SectionLabel(label: l10n.settingsNotificationMode),
                  // const SizedBox(height: 8),
                  // _SegmentedRow<NotificationMode>(
                  //   values: NotificationMode.values,
                  //   selected: _draft.notificationMode,
                  //   labelOf: (v) => v == NotificationMode.location
                  //       ? l10n.settingsNotificationModeLocation
                  //       : l10n.settingsNotificationModeStation,
                  //   onChanged: (v) =>
                  //       setState(() => _draft = _draft.copyWith(notificationMode: v)),
                  // ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        l10n.dialogClose,
                        style: const TextStyle(
                          color: Color(0xFF4080FF),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap:
                        widget.settingsSaveService.busy.value
                            ? null
                            : () => widget.settingsSaveService.save(_draft),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        l10n.settingsSave,
                        style: TextStyle(
                          color:
                              widget.settingsSaveService.busy.value
                                  ? const Color(0xFFA0C0FF)
                                  : const Color(0xFF4080FF),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Segmented row（汎用）─────────────────────────────────────────

class _SegmentedRow<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  const _SegmentedRow({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children:
          values.map((v) {
            final isSelected = v == selected;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: GestureDetector(
                  onTap: () => onChanged(v),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          isSelected ? const Color(0xFFDCECFF) : Colors.white,
                      border: Border.all(
                        color:
                            isSelected
                                ? const Color(0xFF4080FF)
                                : Colors.grey.shade200,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        labelOf(v),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label, style: TextStyle(color: Colors.grey.shade600));
  }
}
