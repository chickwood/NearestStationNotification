import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';
import 'event_manager.dart';
import 'l10n.dart';
import 'license_dialog.dart';
import 'station_manager.dart';

// ── Info Dialog ───────────────────────────────────────────────────

class InfoDialog extends StatefulWidget {
  final StationManager manager;
  final ValueChanged<StationManager> onDataChanged;

  const InfoDialog(this.manager, {super.key, required this.onDataChanged});

  @override
  State<InfoDialog> createState() => _InfoDialogState();
}

class _InfoDialogState extends State<InfoDialog> {
  late StationManager _manager;

  String? _status;
  bool _statusError = false;

  @override
  void initState() {
    super.initState();
    _manager = widget.manager;
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // タイトル行
            Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  const Icon(
                    Icons.info,
                    color: Color(0xFF4080FF),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.infoDialogTitle,
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
                  // ── 駅情報（ライセンス入口）────────────────────────
                  _SectionLabel(label: l10n.infoTitle),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF9E0),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFFF0B0)),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showDialog<void>(
                        context: context,
                        barrierColor: Colors.transparent,
                        builder: (_) => LicenseListDialog(_manager),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.info,
                              color: Color(0xFFFFC000),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${l10n.countStations(_manager.count)}\n'
                                '${l10n.infoVersion(_manager.date)}\n'
                                '${l10n.infoSize(_manager.size)}\n'
                                '${l10n.settingsLicense}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── 更新案内──────────────────────────────
                  _SectionLabel(label: l10n.infoUpdateTitle),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F8FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF60A0FF)),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => launchUrl(
                        Uri.parse(Common.dataUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.download,
                              color: Color(0xFF4080FF),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                l10n.infoUpdateNotice,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_status?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 4),
                    // 状態行
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        _status ?? '',
                        style: TextStyle(
                          color: _statusError
                              ? const Color(0xFFFF4030)
                              : Colors.grey.shade800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _DialogButton(
                  label: l10n.settingsCancel,
                  onTap: () => Navigator.of(context).pop(),
                ),
                _DialogButton(
                  label: l10n.infoImport,
                  onTap: _import,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── データ操作 ───────────────────────────────────────────────────
  /// 単一ファイル選択 → 内容で station / event を判定 → 検証 → 原子書込
  Future<void> _import() async {
    setState(() {
      _status = null;
      _statusError = false;
    });

    try {
      const typeGroup = XTypeGroup(
        label: 'data',
        extensions: ['bin', 'json'],
      );
      final file = await openFile(acceptedTypeGroups: const [typeGroup]);
      if (file == null) return; // キャンセル

      final bytes = await File(file.path).readAsBytes();

      // station（BIN）
      if (StationManager.validate(ByteData.sublistView(bytes))) {
        await StationManager.write(bytes);
        final manager = await StationManager.load();
        if (!mounted) return;

        setState(() {
          _manager = manager;
          _status = L10n.of(context).infoImportedStation;
          _statusError = false;
        });
        widget.onDataChanged(manager);
        return;
      }

      // event（JSON）
      if (EventManager.validate(bytes)) {
        await EventManager.write(bytes);
        await EventManager.load();
        if (!mounted) return;

        setState(() {
          _status = L10n.of(context).infoImportedEvent;
          _statusError = false;
        });
        return;
      }

      // どちらでもない
      setState(() {
        _status = L10n.of(context).infoInvalidFile;
        _statusError = true;
      });
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      if (mounted) {
        setState(() {
          _status = L10n.of(context).infoInvalidFile;
          _statusError = true;
        });
      }
    }
  }
}

// ── Dialog button ─────────────────────────────────────────────────

class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _DialogButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: onTap == null
                ? const Color(0xFFA0C0FF)
                : const Color(0xFF4080FF),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
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
