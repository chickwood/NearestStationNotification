import 'package:flutter/material.dart';

import 'settings.dart';
import 'common.dart';
import 'l10n.dart';
import 'license_dialog.dart';
import 'station_manager.dart';

// ── Settings Dialog ───────────────────────────────────────────────

class SettingsDialog extends StatefulWidget {
  final Settings settings;
  final StationManager manager;
  final Future<void> Function(Settings) onSave;

  const SettingsDialog(
    this.settings,
    this.manager, {
    super.key,
    required this.onSave,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late Settings _draft;

  @override
  void initState() {
    super.initState();

    // 弹窗内操作的临时副本，取消则丢弃
    _draft = widget.settings.copyWith();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Dialog(
      elevation: 2,
      insetPadding: const EdgeInsets.symmetric(horizontal: 30),
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
                  const Icon(
                    Icons.settings,
                    color: Color(0xFF4080FF),
                  ),
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
                    child: Icon(
                      Icons.close,
                      color: Colors.grey.shade600,
                    ),
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
                    values: const [
                      StationCount.game,
                      StationCount.max,
                    ],
                    selected: _draft.stationCount,
                    labelOf: (v) => v.label,
                    onChanged: (v) => setState(
                        () => _draft = _draft.copyWith(stationCount: v)),
                  ),
                  const SizedBox(height: 12),
                  // ── 位置情報取得頻度 ────────────────────────────────────
                  _SectionLabel(label: l10n.settingsLocationInterval),
                  const SizedBox(height: 8),
                  _SegmentedRow<LocationInterval>(
                    values: LocationInterval.values,
                    selected: _draft.locationInterval,
                    labelOf: (v) =>
                        l10n.settingsLocationIntervalLabel(v.seconds),
                    onChanged: (v) => setState(
                        () => _draft = _draft.copyWith(locationInterval: v)),
                  ),
                  const SizedBox(height: 12),
                  // // ── 通知方式 ────────────────────────────────────────────
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
                  // const SizedBox(height: 12),
                  // ── 駅情報 ────────────────────────────────────────────
                  _SectionLabel(label: l10n.settingsInfoTitle),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F8FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF60A0FF)),
                    ),
                    child: TextButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        barrierColor: Colors.transparent,
                        builder: (_) => LicenseListDialog(widget.manager),
                      ),
                      // onPressed: () => showLicensePage(context: context),
                      label: Text(
                        '${widget.manager.count > 0 ? l10n.countStations(widget.manager.count) : l10n.countStations(0)}\n'
                        '${l10n.settingsLicense}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                        softWrap: true,
                      ),
                      icon: const Icon(
                        Icons.info,
                        color: Color(0xFF4080FF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    l10n.settingsCancel,
                    style: const TextStyle(
                      color: Color(0xFF4080FF),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await widget.onSave(_draft);
                  },
                  child: Text(
                    l10n.settingsSave,
                    style: const TextStyle(
                      color: Color(0xFF4080FF),
                    ),
                  ),
                ),
              ],
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
      children: values.map((v) {
        final isSelected = v == selected;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: GestureDetector(
              onTap: () => onChanged(v),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF4080FF) : Colors.white,
                  border: Border.all(
                    color: isSelected
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
                      color: isSelected ? Colors.white : Colors.grey.shade800,
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

  const _SectionLabel({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(color: Colors.grey.shade600),
    );
  }
}
