import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common.dart';
import '../l10n.dart';
import '../manager/event_manager.dart';
import '../manager/station_manager.dart';
import '../service/info_import_service.dart';
import 'license_dialog.dart';

// ── Info Dialog ───────────────────────────────────────────────────

class InfoDialog extends StatefulWidget {
  final StationManager stationManager;
  final EventManager eventManager;
  final InfoImportService infoImportService;

  const InfoDialog(
    this.stationManager,
    this.eventManager, {
    super.key,
    required this.infoImportService,
  });

  @override
  State<InfoDialog> createState() => _InfoDialogState();
}

class _InfoDialogState extends State<InfoDialog> {
  late StationManager _stationManager;
  late EventManager _eventManager;

  @override
  void initState() {
    super.initState();
    _stationManager = widget.stationManager;
    _eventManager = widget.eventManager;
    widget.infoImportService.lastResult.addListener(_handleImportResult);
    widget.infoImportService.busy.addListener(_handleBusyChanged);
  }

  @override
  void dispose() {
    widget.infoImportService.lastResult.removeListener(_handleImportResult);
    widget.infoImportService.busy.removeListener(_handleBusyChanged);
    super.dispose();
  }

  void _handleImportResult() {
    final result = widget.infoImportService.lastResult.value;
    if (result == null || !result.succeeded || !mounted) return;

    setState(() {
      if (result.station != null) {
        _stationManager = result.station!;
      }
      if (result.event != null) {
        _eventManager = result.event!;
      }
    });
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // タイトル行
            Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  const Icon(Icons.info, color: Color(0xFF4080FF)),
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
                  // ── 駅情報（ライセンス入口）────────────────────────
                  _SectionLabel(label: l10n.infoTitle),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCECFF),
                      border: Border.all(color: const Color(0xFF60A0FF)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap:
                          () => showDialog<void>(
                            context: context,
                            barrierColor: Colors.transparent,
                            builder:
                                (_) => LicenseListDialog(
                                  _stationManager,
                                  _eventManager,
                                ),
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
                              Icons.description,
                              color: Color(0xFF4080FF),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${l10n.infoStations(_stationManager.count)}'
                                '\n${l10n.infoVersion(_stationManager.date, _stationManager.pdate)}'
                                '\n${l10n.infoSize(_stationManager.size)}'
                                '\n\n${l10n.infoLicense}',
                                style: TextStyle(
                                  color: Colors.grey.shade800,
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
                  // ── 更新案内──────────────────────────────
                  const SizedBox(height: 12),
                  _SectionLabel(label: l10n.infoUpdateTitle),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCECFF),
                      border: Border.all(color: const Color(0xFF4080FF)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap:
                          () => launchUrl(
                            Common.uriInformation,
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
                                  color: Colors.grey.shade800,
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
                        style: TextStyle(
                          color: const Color(0xFF4080FF),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap:
                        widget.infoImportService.busy.value
                            ? null
                            : () => widget.infoImportService.import(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        l10n.infoImport,
                        style: TextStyle(
                          color:
                              widget.infoImportService.busy.value
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

// ── Section label ─────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label, style: TextStyle(color: Colors.grey.shade600));
  }
}
