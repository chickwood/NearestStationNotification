import 'package:flutter/material.dart';

import '../common.dart';
import '../l10n.dart';
import '../manager/settings_manager.dart';
import '../service/settings_save_service.dart';

// ── Settings Page ─────────────────────────────────────────────────

class SettingsPage extends StatefulWidget {
  final SettingsManager settingsManager;
  final SettingsSaveService settingsSaveService;

  const SettingsPage(
    this.settingsManager,
    this.settingsSaveService, {
    super.key,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ResetableState<SettingsPage> {
  late SettingsManager _draft;

  @override
  void initState() {
    super.initState();

    // ページ内操作的临时副本，离开则丢弃
    _draft = widget.settingsManager.copyWith();
    widget.settingsSaveService.last.addListener(_handleLastChanged);
    widget.settingsSaveService.busy.addListener(_handleBusyChanged);
  }

  @override
  void dispose() {
    widget.settingsSaveService.last.removeListener(_handleLastChanged);
    widget.settingsSaveService.busy.removeListener(_handleBusyChanged);
    super.dispose();
  }

  void _handleLastChanged() => resetState();
  void _handleBusyChanged() => resetState();

  Future<void> _save() async {
    await widget.settingsSaveService.save(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final busy = widget.settingsSaveService.busy.value;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(l10n.settingsPageTitle),
        actions: [
          AppBarAction(
            onPressed: busy ? null : _save,
            icon: const Icon(Icons.save),
            tooltip: l10n.settingsSave,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 検出駅数 ────────────────────────────────────────────
              Text(l10n.settingsStationCount),
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
              const Divider(height: 16),
              // ── 位置情報取得頻度 ────────────────────────────────────
              Text(l10n.settingsLocationInterval),
              const SizedBox(height: 8),
              _SegmentedRow<LocationInterval>(
                values: LocationInterval.values,
                selected: _draft.locationInterval,
                labelOf: (v) => l10n.settingsLocationIntervalLabel(v.seconds),
                onChanged:
                    (v) => setState(
                      () => _draft = _draft.copyWith(locationInterval: v),
                    ),
              ),
              const Divider(height: 16),
              // ── 历史记录开关 ────────────────────────────────────
              Text(l10n.settingsHistory),
              const SizedBox(height: 8),
              _CheckboxRow(
                label: l10n.settingsHistoryEnabled,
                value: _draft.historyEnabled,
                onChanged:
                    (v) => setState(
                      () => _draft = _draft.copyWith(historyEnabled: v),
                    ),
              ),
            ],
          ),
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
              child: GestureDetector(
                onTap: () => onChanged(v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color:
                                isSelected
                                    ? const Color(0xFF4080FF)
                                    : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
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
                        ],
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

class _CheckboxRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CheckboxRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: value ? const Color(0xFFDCECFF) : Colors.white,
            border: Border.all(
              color: value ? const Color(0xFF4080FF) : Colors.grey.shade200,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                value ? Icons.check : Icons.check_box_outline_blank,
                color: value ? const Color(0xFF4080FF) : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
