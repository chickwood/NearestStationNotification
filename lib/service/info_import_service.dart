import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../common.dart';
import '../manager/event_manager.dart';
import '../manager/station_manager.dart';

// ── Info Import Service ────────────────────────────────────────────

class InfoImportResult {
  final StationManager? station;
  final EventManager? event;
  final Object? error;

  const InfoImportResult._({this.station, this.event, this.error})
    : assert(
        error == null || (station == null && event == null),
        'failure must not carry data',
      ),
      assert(
        error != null || station != null || event != null,
        'success must carry data',
      );

  factory InfoImportResult.success({
    StationManager? station,
    EventManager? event,
  }) => InfoImportResult._(station: station, event: event);

  factory InfoImportResult.failure(Object error) =>
      InfoImportResult._(error: error);

  bool get succeeded => error == null;
}

/// zip 选择 → 解析 → SHA-256 → 写入 → load
/// 异步执行与结果独立于 Dialog 生命周期
class InfoImportService {
  final ValueNotifier<InfoImportResult?> lastResult = ValueNotifier(null);
  final ValueNotifier<bool> busy = ValueNotifier(false);

  Future<void> import() async {
    if (busy.value) return;

    busy.value = true;
    try {
      const typeGroup = XTypeGroup(
        label: 'zip',
        extensions: ['zip'],
        mimeTypes: ['application/zip', 'application/x-zip-compressed'],
        uniformTypeIdentifiers: ['public.zip-archive'],
      );
      final xfile = await openFile(acceptedTypeGroups: const [typeGroup]);
      if (xfile == null) return; // キャンセル

      final archive = await _parseImportArchive(File(xfile.path));
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

      lastResult.value = InfoImportResult.success(
        station: stationManager,
        event: eventManager,
      );
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      lastResult.value = InfoImportResult.failure(e);
    } finally {
      busy.value = false;
    }
  }

  void dispose() {
    lastResult.dispose();
    busy.dispose();
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

/// 解压 zip，读取 SHA256SUMS，并校验实际存在的 station / event 文件。
/// 只返回原始字节；格式校验由调用方负责。
/// 仅匹配压缩包根目录的固定文件名；允许仅 station bin、仅 event json 或两者都有。
Future<_ImportArchive> _parseImportArchive(File file) async {
  final length = await file.length();
  if (length == 0 || length > Common.maxZipSize) {
    throw const _InvalidImportException();
  }

  final zipBytes = await file.readAsBytes();
  if (zipBytes.length != length) {
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

  var totalSize = 0;
  final entries = <String, List<ArchiveFile>>{};
  for (final entry in archive.files) {
    totalSize += entry.size;
    if (totalSize > Common.maxZipTotalUnzipSize) {
      throw const _InvalidImportException();
    }

    if (!entry.isFile) continue;

    entries.putIfAbsent(entry.name, () => []).add(entry);
  }

  final sumsBytes = _readUniqueEntry(entries, Common.sumsFileName);
  final binBytes = _readUniqueEntry(entries, Common.binFileName);
  final eventBytes = _readUniqueEntry(entries, Common.eventFileName);
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

/// 读取唯一同名条目；不存在 / 读取结果为空 / 零字节返回 null；
/// 重复 / 超限 / 读取抛错 / 长度不一致均视为不合法。
Uint8List? _readUniqueEntry(
  Map<String, List<ArchiveFile>> entries,
  String name,
) {
  // 重复判断
  final list = entries[name];
  if (list == null) return null;
  if (list.length != 1) {
    throw const _InvalidImportException();
  }

  // 大小判断
  final entry = list.first;
  // 零字节视为不存在
  if (entry.size == 0) return null;
  if (entry.size > Common.maxZipEntrySize) {
    throw const _InvalidImportException();
  }

  // 读取
  Uint8List? bytes;
  try {
    bytes = entry.readBytes();
  } catch (_) {
    throw const _InvalidImportException();
  }
  // 读取结果不可用视为不存在
  if (bytes == null) return null;

  if (bytes.length != entry.size) {
    throw const _InvalidImportException();
  }
  // 零字节视为不存在
  if (bytes.isEmpty) return null;

  return bytes;
}

bool _verifyChecksum(String manifest, String target, Uint8List? bytes) {
  if (bytes == null) return true;

  final expected = _lookupChecksum(manifest, target);
  if (expected == null) return false;

  final actual = sha256.convert(bytes).toString();
  return actual.toLowerCase() == expected.toLowerCase();
}

/// 从 SHA256SUMS 中查找目标文件的哈希。
/// 清单使用固定文件名；支持 `sha256sum` 格式：`<64位hex>  <filename>` 或 `<64位hex> *<filename>`。
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
