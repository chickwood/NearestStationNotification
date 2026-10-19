import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_styled_toast/flutter_styled_toast.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';
import 'event_manager.dart';
import 'l10n.dart';
import 'license_dialog.dart';
import 'station_manager.dart';

// ── Info Dialog ───────────────────────────────────────────────────

class InfoDialog extends StatefulWidget {
  final StationManager stationManager;
  final EventManager eventManager;

  final ValueChanged<({StationManager? s, EventManager? e})> onImported;

  const InfoDialog(
    this.stationManager,
    this.eventManager, {
    super.key,
    required this.onImported,
  });

  @override
  State<InfoDialog> createState() => _InfoDialogState();
}

class _InfoDialogState extends State<InfoDialog> {
  late StationManager _stationManager;
  late EventManager _eventManager;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _stationManager = widget.stationManager;
    _eventManager = widget.eventManager;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    final content = Padding(
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
                    color: const Color(0xFFFFF9E0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFF0B0)),
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
                          const Icon(Icons.info, color: Color(0xFFFFC000)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${l10n.infoStations(_stationManager.count)}'
                              '\n${l10n.infoVersion(_stationManager.date, _stationManager.pdate)}'
                              '\n${l10n.infoSize(_stationManager.size)}'
                              '\n\n${l10n.infoLicense}',
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
                          const Icon(Icons.download, color: Color(0xFF4080FF)),
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
                onTap: _importing ? null : _import,
              ),
            ],
          ),
        ],
      ),
    );

    return Dialog(
      elevation: 2,
      insetPadding: const EdgeInsets.symmetric(horizontal: 30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: content,
    );
  }

  // ── データ操作 ───────────────────────────────────────────────────
  /// zip 選択 → 展開 → SHA256SUMS 検証 → station 形式検証 → 書込
  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);

    final l10n = L10n.of(context);

    try {
      const typeGroup = XTypeGroup(
        label: 'zip',
        extensions: ['zip'],
        mimeTypes: ['application/zip', 'application/x-zip-compressed'],
        uniformTypeIdentifiers: ['public.zip-archive'],
      );
      final file = await openFile(acceptedTypeGroups: const [typeGroup]);
      if (file == null) return; // キャンセル

      final zipBytes = await File(file.path).readAsBytes();
      final archive = _parseImportArchive(zipBytes);

      final stationBin = archive.stationBin;
      final eventJson = archive.eventJson;

      if (stationBin != null &&
          !StationManager.validate(ByteData.sublistView(stationBin))) {
        throw const _InvalidImportException();
      }
      if (eventJson != null && !EventManager.validate(eventJson)) {
        throw const _InvalidImportException();
      }

      if (stationBin != null) {
        await StationManager.write(stationBin);
      }
      if (eventJson != null) {
        await EventManager.write(eventJson);
      }

      StationManager? stationManager;
      if (stationBin != null) {
        stationManager = await StationManager.load();
      }
      EventManager? eventManager;
      if (eventJson != null) {
        eventManager = await EventManager.load();
      }

      if (!mounted) return;

      setState(() {
        if (stationManager != null) {
          _stationManager = stationManager;
        }
        if (eventManager != null) {
          _eventManager = eventManager;
        }
      });

      widget.onImported((s: stationManager, e: eventManager));

      if (stationBin != null && eventJson != null) {
        _showToast(l10n.infoImportedStationAndEvent);
      } else if (stationBin != null) {
        _showToast(l10n.infoImportedStation);
      } else {
        _showToast(l10n.infoImportedEvent);
      }
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      if (!mounted) return;
      _showToast(l10n.infoInvalidFile, isError: true);
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  void _showToast(String message, {bool isError = false}) {
    showToast(
      message,
      backgroundColor:
          isError
              ? const Color(0xFFFF4030) // Colors.red.shade700
              : const Color(0xFFA0C0FF), // Colors.indigo.shade300
      textStyle: TextStyle(
        color: isError ? Colors.white : Colors.grey.shade800,
      ),
      textPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      textAlign: TextAlign.left,
      borderRadius: BorderRadius.circular(8),
    );
  }
}

// ── Dialog button ─────────────────────────────────────────────────

class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _DialogButton({required this.label, required this.onTap});

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
            color:
                onTap == null
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

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label, style: TextStyle(color: Colors.grey.shade600));
  }
}

// ── Import archive ────────────────────────────────────────────────

class _InvalidImportException implements Exception {
  const _InvalidImportException();
}

class _ImportArchive {
  final Uint8List? stationBin;
  final Uint8List? eventJson;

  const _ImportArchive({this.stationBin, this.eventJson});
}

/// 解压 zip、读取 SHA256SUMS，并校验实际存在的 station / event 文件。
/// 只返回原始字节；格式校验由调用方负责。
/// 允许仅 bin、仅 event 或两者都有；两者都不存在视为不合法。
_ImportArchive _parseImportArchive(Uint8List zipBytes) {
  if (zipBytes.isEmpty || zipBytes.length > Common.maxZipBytes) {
    throw const _InvalidImportException();
  }

  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } catch (_) {
    throw const _InvalidImportException();
  }

  if (archive.files.length > Common.maxZipEntries) {
    throw const _InvalidImportException();
  }

  final entries = <String, List<ArchiveFile>>{};
  var totalSize = 0;

  for (final entry in archive.files) {
    totalSize += entry.size;
    if (totalSize > Common.maxZipTotalUncompressedBytes) {
      throw const _InvalidImportException();
    }
    if (!entry.isFile) continue;

    final name = _basename(entry.name);
    if (name.isEmpty || !_isSafeName(name)) {
      throw const _InvalidImportException();
    }
    entries.putIfAbsent(name, () => []).add(entry);
  }

  final binEntry = _uniqueEntry(entries, Common.binFileName);
  final eventEntry = _uniqueEntry(entries, Common.eventFileName);
  final sumsEntry = _uniqueEntry(entries, 'SHA256SUMS');

  if (sumsEntry == null || (binEntry == null && eventEntry == null)) {
    throw const _InvalidImportException();
  }

  final sumsBytes = _readEntry(sumsEntry, Common.maxSumsBytes);
  final binBytes = _readEntry(binEntry, Common.maxZipEntryBytes);
  final eventBytes = _readEntry(eventEntry, Common.maxZipEntryBytes);

  if (sumsBytes == null || (binBytes == null && eventBytes == null)) {
    throw const _InvalidImportException();
  }

  final manifest = utf8.decode(sumsBytes, allowMalformed: true);

  if (!_verifyChecksum(manifest, Common.binFileName, binBytes) ||
      !_verifyChecksum(manifest, Common.eventFileName, eventBytes)) {
    throw const _InvalidImportException();
  }

  return _ImportArchive(stationBin: binBytes, eventJson: eventBytes);
}

/// 返回唯一同名条目；不存在返回 null，重复则视为不合法。
ArchiveFile? _uniqueEntry(Map<String, List<ArchiveFile>> entries, String name) {
  final list = entries[name];
  if (list == null) return null;
  if (list.length != 1) {
    throw const _InvalidImportException();
  }
  return list.first;
}

/// 读取可选条目；空文件、超限或读取失败均视为不合法。
Uint8List? _readEntry(ArchiveFile? entry, int maxBytes) {
  if (entry == null) return null;
  if (entry.size == 0 || entry.size > maxBytes) {
    throw const _InvalidImportException();
  }

  final bytes = _read(entry);
  if (bytes == null || bytes.isEmpty || bytes.length > maxBytes) {
    throw const _InvalidImportException();
  }
  return bytes;
}

bool _verifyChecksum(String manifest, String target, Uint8List? bytes) {
  if (bytes == null) return true;

  final expected = _lookupChecksum(manifest, target);
  if (expected == null) return false;

  final actual = sha256.convert(bytes).toString();
  return actual.toLowerCase() == expected.toLowerCase();
}

Uint8List? _read(ArchiveFile entry) {
  try {
    return entry.readBytes();
  } catch (_) {
    throw const _InvalidImportException();
  }
}

String _basename(String name) {
  final normalized = name.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

bool _isSafeName(String name) {
  return !name.contains('..') &&
      !name.startsWith('/') &&
      !name.startsWith('\\');
}

/// 从 SHA256SUMS 中查找目标文件的哈希。
/// 支持 `sha256sum` 格式：`<64位hex>  <filename>` 或 `<64位hex> *<filename>`。
String? _lookupChecksum(String manifest, String target) {
  String? found;
  final text = manifest.startsWith('\uFEFF') ? manifest.substring(1) : manifest;

  for (final rawLine in const LineSplitter().convert(text)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final separator = line.indexOf(RegExp(r'\s'));
    if (separator <= 0) continue;

    final hash = line.substring(0, separator);
    var listed = line.substring(separator).trim();
    if (listed.startsWith('*')) listed = listed.substring(1);
    listed = _basename(listed);

    if (listed != target) continue;

    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) {
      throw const _InvalidImportException();
    }
    if (found != null) {
      throw const _InvalidImportException();
    }
    found = hash;
  }

  return found;
}
