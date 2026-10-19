import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'common.dart';
import 'event_manager.dart';
import 'station_manager.dart';

// ── Info Service ───────────────────────────────────────────────────

sealed class InfoImportResult {
  const InfoImportResult();
}

class InfoImportSucceeded extends InfoImportResult {
  final StationManager? station;
  final EventManager? event;

  const InfoImportSucceeded({this.station, this.event});
}

class InfoImportFailed extends InfoImportResult {
  final Object error;

  const InfoImportFailed(this.error);
}

/// zip 选择 → 解析 → SHA-256 → 写入 → load
/// 异步执行与结果独立于 Dialog 生命周期
class InfoService {
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

      lastResult.value = InfoImportSucceeded(
        station: stationManager,
        event: eventManager,
      );
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      lastResult.value = InfoImportFailed(e);
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
