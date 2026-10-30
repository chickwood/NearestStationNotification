import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common.dart';
import '../l10n.dart';
import '../manager/event_manager.dart';
import '../manager/station_manager.dart';
import '../service/info_import_service.dart';
import 'license_page.dart';

// ── Info Page ─────────────────────────────────────────────────────

class InfoPage extends StatefulWidget {
  final StationManager stationManager;
  final EventManager eventManager;
  final InfoImportService infoImportService;

  const InfoPage(
    this.stationManager,
    this.eventManager,
    this.infoImportService, {
    super.key,
  });

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends ResetableState<InfoPage> {
  late StationManager _stationManager;
  late EventManager _eventManager;
  bool _picking = false;
  bool get _importBusy => _picking || widget.infoImportService.busy.value;

  @override
  void initState() {
    super.initState();
    _stationManager = widget.stationManager;
    _eventManager = widget.eventManager;
    widget.infoImportService.last.addListener(_handleLastChanged);
    widget.infoImportService.busy.addListener(_handleBusyChanged);
  }

  @override
  void dispose() {
    widget.infoImportService.last.removeListener(_handleLastChanged);
    widget.infoImportService.busy.removeListener(_handleBusyChanged);
    super.dispose();
  }

  void _handleLastChanged() {
    final result = widget.infoImportService.last.value;
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

  void _handleBusyChanged() => resetState();

  Future<void> _import() async {
    if (!mounted || _importBusy) return;

    setState(() => _picking = true);
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (!mounted || picked == null) return;

      final path = picked.path;
      if (path == null) return;

      await widget.infoImportService.import(path);
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    } finally {
      if (!mounted) {
        null;
      } else {
        setState(() => _picking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(l10n.infoPageTitle),
        actions: [
          AppBarAction(
            onPressed: _importBusy ? null : _import,
            icon: const Icon(Icons.file_open),
            tooltip: l10n.infoImport,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 駅情報（ライセンス入口）────────────────────────
              Text(l10n.infoTitle),
              const SizedBox(height: 8),
              GestureDetector(
                // behavior: HitTestBehavior.opaque,
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder:
                            (_) =>
                                LicenseListPage(_stationManager, _eventManager),
                      ),
                    ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCECFF),
                      border: Border.all(color: const Color(0xFF4080FF)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.description, color: Color(0xFF4080FF)),
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
              const Divider(height: 16),
              // ── 更新案内──────────────────────────────
              Text(l10n.infoUpdateTitle),
              const SizedBox(height: 8),
              GestureDetector(
                // behavior: HitTestBehavior.opaque,
                onTap:
                    () => launchUrl(
                      Common.uriInformation,
                      mode: LaunchMode.externalApplication,
                    ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCECFF),
                      border: Border.all(color: const Color(0xFF4080FF)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.download, color: Color(0xFF4080FF)),
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
      ),
    );
  }
}
