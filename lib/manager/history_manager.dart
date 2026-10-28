import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../common.dart';

class HistoryManager {
  static const _backupChannel = MethodChannel(
    'name.w57.nearest_station_notification/backup',
  );

  static const _maxBackupEntries = 5000;
  static const _maxBackupEntrySize = 64 * 1024 * 1024;
  static const _maxBackupTotalSize = 1024 * 1024 * 1024;
  static const _maxMonthNdjsonSize = 64 * 1024 * 1024;
  static const _maxSumsSize = 1024 * 1024;

  static final _monthZipPattern = RegExp(r'^(\d{6})\.zip$');
  static final _dayFilePattern = RegExp(r'^(\d{8})\.ndjson$');
  static final _monthPattern = RegExp(r'^\d{6}$');
  static final _backupEntryPattern = RegExp(
    r'^(?:\d{6}\.zip|\d{8}\.ndjson|MANIFEST|SHA256SUMS)$',
  );
  static final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

  final Directory? _directory;
  final Random _random = Random();

  Future<void> _lock = Future<void>.value();

  HistoryManager._({required Directory? directory}) : _directory = directory;

  bool get isAvailable => _directory != null;

  static Future<HistoryManager> load() async {
    Directory? directory;

    try {
      final base = await getApplicationDocumentsDirectory();
      final history = Directory('${base.path}/${Common.historyDirName}');
      await history.create(recursive: true);
      directory = history;

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          await _backupChannel.invokeMethod<void>(
            'excludeFromBackup',
            history.path,
          );
        } catch (e, st) {
          debugPrint('history backup exclusion failed: $e\n$st');
        }
      }
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    }

    return HistoryManager._(directory: directory);
  }

  Future<void> appendRecords(List<HistoryRecord> records) async {
    if (_directory == null || records.isEmpty) return;

    final grouped = <int, List<HistoryRecord>>{};
    for (final record in records) {
      final date = Common.dateOfEpoch(record.epoch);
      (grouped[date] ??= <HistoryRecord>[]).add(record);
    }

    await _withLock(() async {
      for (final entry in grouped.entries) {
        await _appendDayRecords(entry.key, entry.value);
      }
    });
  }

  Future<void> consolidateIfDue() async {
    if (_directory == null) return;

    try {
      await _withLock(_consolidateLocked);
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    }
  }

  Future<List<int>> listMonths() async {
    if (_directory == null) return const [];
    return _withLock(_listMonthsUnlocked);
  }

  Future<List<int>> listDays(int month) async {
    final directory = _directory;
    if (directory == null || !Common.isValidMonth(month)) return const [];

    return _withLock(() async {
      final days = <int>{};

      try {
        await for (final entity in directory.list()) {
          if (entity is! File) continue;
          final name = _basename(entity.path);
          final match = _dayFilePattern.firstMatch(name);
          if (match == null) continue;
          final date = int.parse(match.group(1)!);
          if (!Common.isValidDate(date) || Common.monthDateOf(date) != month) {
            continue;
          }
          days.add(date);
        }
      } catch (e, st) {
        debugPrint('error: $e\n$st');
      }

      final archive = File('${directory.path}/$month.zip');
      if (await archive.exists()) {
        try {
          final records = _readMonthZipRecords(
            await archive.readAsBytes(),
            month,
          );
          for (final record in records) {
            days.add(Common.dateOfEpoch(record.epoch));
          }
        } catch (e, st) {
          debugPrint('error: $e\n$st');
        }
      }

      final list = days.toList()..sort((a, b) => b.compareTo(a));
      return list;
    });
  }

  Future<List<HistoryRecord>> readMonth(int month) async {
    if (_directory == null || !Common.isValidMonth(month)) return const [];
    return _withLock(() => _readMonthUnlocked(month));
  }

  Future<List<HistoryRecord>> readDay(int date) async {
    if (_directory == null || !Common.isValidDate(date)) return const [];
    final month = Common.monthDateOf(date);

    return _withLock(() async {
      final records = await _readMonthUnlocked(month);
      return records
          .where((record) => Common.dateOfEpoch(record.epoch) == date)
          .toList(growable: false);
    });
  }

  Future<int> createBackup(
    File output,
    void Function(double) onProgress,
  ) async {
    if (_directory == null) throw StateError('history unavailable');

    return _withLock(() async {
      final directory = _directory;
      final archives = <File>[];
      final dailies = <File>[];

      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = _basename(entity.path);

        final monthMatch = _monthZipPattern.firstMatch(name);
        if (monthMatch != null) {
          if (Common.isValidMonth(int.parse(monthMatch.group(1)!))) {
            archives.add(entity);
          }
          continue;
        }

        final dayMatch = _dayFilePattern.firstMatch(name);
        if (dayMatch != null) {
          if (Common.isValidDate(int.parse(dayMatch.group(1)!))) {
            dailies.add(entity);
          }
        }
      }

      archives.sort((a, b) => _basename(a.path).compareTo(_basename(b.path)));
      dailies.sort((a, b) => _basename(a.path).compareTo(_basename(b.path)));

      if (archives.isEmpty && dailies.isEmpty) {
        throw StateError('no history');
      }

      final archiveMonths = archives
          .map(
            (file) =>
                _monthZipPattern.firstMatch(_basename(file.path))!.group(1)!,
          )
          .toList(growable: false);
      final dailyFiles = dailies
          .map((file) => _basename(file.path))
          .toList(growable: false);

      final exportedAt = DateTime.now().millisecondsSinceEpoch;
      final manifest = <String, Object>{
        'v': Common.historySchemaVersion,
        'exportedAt': exportedAt,
        'archiveMonths': archiveMonths,
        'dailyFiles': dailyFiles,
        'fileCount': archives.length + dailies.length + 2,
      };
      final manifestBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(manifest)),
      );

      final sumsLines = <String>[
        '${sha256.convert(manifestBytes)}  ${Common.historyManifestFileName}',
      ];

      final total = archives.length + dailies.length + 1;
      var done = 0;
      final encoder = ZipFileEncoder();
      var closed = false;

      try {
        await output.parent.create(recursive: true);
        encoder.create(output.path);
        encoder.addArchiveFile(
          ArchiveFile(
            Common.historyManifestFileName,
            manifestBytes.length,
            manifestBytes,
          ),
        );

        for (final file in archives) {
          final name = _basename(file.path);
          sumsLines.add('${await _hashFile(file)}  $name');
          await encoder.addFile(file, name, 0);
          done++;
          onProgress(done / total);
        }

        for (final file in dailies) {
          final name = _basename(file.path);
          sumsLines.add('${await _hashFile(file)}  $name');
          await encoder.addFile(file, name);
          done++;
          onProgress(done / total);
        }

        final sumsBytes = Uint8List.fromList(
          utf8.encode('${sumsLines.join('\n')}\n'),
        );
        encoder.addArchiveFile(
          ArchiveFile(Common.sumsFileName, sumsBytes.length, sumsBytes),
        );
        await encoder.close();
        closed = true;
        onProgress(1);
      } catch (e) {
        try {
          if (await output.exists()) await output.delete();
        } catch (_) {}
        rethrow;
      } finally {
        if (!closed) {
          try {
            await encoder.close();
          } catch (_) {}
        }
      }

      return exportedAt;
    });
  }

  Future<void> importBackup(
    File input,
    void Function(double) onProgress,
  ) async {
    if (_directory == null) throw StateError('history unavailable');

    await _withLock(() async {
      await _importBackupLocked(input, onProgress);
    });
  }

  Future<T> _withLock<T>(Future<T> Function() action) async {
    final previous = _lock;
    final completer = Completer<void>();
    _lock = completer.future;

    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  Future<void> _appendDayRecords(int date, List<HistoryRecord> records) async {
    final file = _dayFile(date);
    final randomAccess = await file.open(mode: FileMode.append);

    try {
      final length = await randomAccess.length();
      if (length > 0) {
        await randomAccess.setPosition(length - 1);
        final lastByte = await randomAccess.readByte();
        if (lastByte != 0x0A) await randomAccess.writeString('\n');
      } else {
        await randomAccess.writeString('${_header()}\n');
      }

      final buffer = StringBuffer();
      for (final record in records) {
        buffer.writeln(jsonEncode(record.toRow()));
      }
      await randomAccess.writeString(buffer.toString());
      await randomAccess.flush();
    } finally {
      await randomAccess.close();
    }
  }

  Future<void> _consolidateLocked() async {
    if (_directory == null) return;

    final date = Common.today();
    final day = Common.dayOf(date);
    if (day < Common.historyArchiveWindowStartDay) return;

    final months = await _unarchivedMonthsLocked(Common.monthDateOf(date));
    if (months.isEmpty) return;

    if (day <= Common.historyArchiveWindowEndDay && !_random.nextBool()) {
      return;
    }

    for (final month in months) {
      try {
        await _archiveMonth(month);
      } catch (e, st) {
        debugPrint('error: $e\n$st');
      }
    }
  }

  Future<List<int>> _unarchivedMonthsLocked(int currentMonth) async {
    final directory = _directory!;
    final archiveMonths = <int>{};
    final dayMonths = <int>{};

    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = _basename(entity.path);

      final monthMatch = _monthZipPattern.firstMatch(name);
      if (monthMatch != null) {
        final month = int.parse(monthMatch.group(1)!);
        if (Common.isValidMonth(month)) archiveMonths.add(month);
        continue;
      }

      final dayMatch = _dayFilePattern.firstMatch(name);
      if (dayMatch != null) {
        final date = int.parse(dayMatch.group(1)!);
        if (!Common.isValidDate(date)) continue;
        dayMonths.add(Common.monthDateOf(date));
      }
    }

    final target = <int>{...archiveMonths, ...dayMonths};
    final result = <int>[];

    for (final month in target) {
      if (month >= currentMonth) continue;

      final hasArchive = archiveMonths.contains(month);
      final hasDays = dayMonths.contains(month);
      if (!hasArchive || hasDays) result.add(month);
    }

    result.sort();
    return result;
  }

  Future<void> _archiveMonth(int month) async {
    final directory = _directory!;
    final dayFiles = <File>[];

    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = _basename(entity.path);
      final match = _dayFilePattern.firstMatch(name);
      if (match == null) continue;
      final date = int.parse(match.group(1)!);
      if (!Common.isValidDate(date) || Common.monthDateOf(date) != month) {
        continue;
      }
      dayFiles.add(entity);
    }

    final merged = <HistoryRecord>[];
    final mergedFiles = <File>[];
    final archive = File('${directory.path}/$month.zip');

    if (await archive.exists()) {
      final records = _readMonthZipRecords(await archive.readAsBytes(), month);
      merged.addAll(records);
    }

    for (final file in dayFiles) {
      try {
        final parsed = _parseNdjson(await file.readAsBytes());
        if (parsed == null) {
          debugPrint('invalid history day file: ${file.path}');
          continue;
        }
        merged.addAll(parsed);
        mergedFiles.add(file);
      } catch (e, st) {
        debugPrint('error: $e\n$st');
      }
    }

    final records = _dedupeSort(merged);
    final ndjsonBytes = _encodeNdjson(records);
    final hash = sha256.convert(ndjsonBytes).toString();
    final sumsBytes = Uint8List.fromList(utf8.encode('$hash  $month.ndjson\n'));

    final suffix = DateTime.now().microsecondsSinceEpoch;
    final tempNdjson = File('${directory.path}/.$month.ndjson.$suffix.tmp');
    final tempZip = File('${directory.path}/.$month.zip.$suffix.tmp');
    final encoder = ZipFileEncoder();
    var closed = false;

    try {
      await tempNdjson.writeAsBytes(ndjsonBytes, flush: true);
      encoder.create(tempZip.path);
      await encoder.addFile(tempNdjson, '$month.ndjson');
      encoder.addArchiveFile(
        ArchiveFile(Common.sumsFileName, sumsBytes.length, sumsBytes),
      );
      await encoder.close();
      closed = true;

      try {
        await tempZip.rename(archive.path);
      } on FileSystemException {
        if (await archive.exists()) await archive.delete();
        await tempZip.rename(archive.path);
      }
    } finally {
      if (!closed) {
        try {
          await encoder.close();
        } catch (_) {}
      }
      try {
        if (await tempNdjson.exists()) await tempNdjson.delete();
      } catch (_) {}
      try {
        if (await tempZip.exists()) await tempZip.delete();
      } catch (_) {}
    }

    for (final file in mergedFiles) {
      try {
        await file.delete();
      } catch (e, st) {
        debugPrint('error: $e\n$st');
      }
    }
  }

  Future<List<int>> _listMonthsUnlocked() async {
    final directory = _directory;
    if (directory == null) return const [];
    final months = <int>{};

    try {
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = _basename(entity.path);

        final monthMatch = _monthZipPattern.firstMatch(name);
        if (monthMatch != null) {
          final month = int.parse(monthMatch.group(1)!);
          if (Common.isValidMonth(month)) months.add(month);
          continue;
        }

        final dayMatch = _dayFilePattern.firstMatch(name);
        if (dayMatch != null) {
          final date = int.parse(dayMatch.group(1)!);
          if (Common.isValidDate(date)) months.add(Common.monthDateOf(date));
        }
      }
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    }

    final list = months.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  Future<List<HistoryRecord>> _readMonthUnlocked(int month) async {
    final directory = _directory;
    if (directory == null) return const [];

    final records = <HistoryRecord>[];
    final archive = File('${directory.path}/$month.zip');

    if (await archive.exists()) {
      try {
        records.addAll(
          _readMonthZipRecords(await archive.readAsBytes(), month),
        );
      } catch (e, st) {
        debugPrint('error: $e\n$st');
      }
    }

    try {
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = _basename(entity.path);
        final match = _dayFilePattern.firstMatch(name);
        if (match == null) continue;
        final date = int.parse(match.group(1)!);
        if (!Common.isValidDate(date) || Common.monthDateOf(date) != month) {
          continue;
        }

        try {
          final parsed = _parseNdjson(await entity.readAsBytes());
          if (parsed == null) {
            debugPrint('invalid history day file: ${entity.path}');
            continue;
          }
          records.addAll(parsed);
        } catch (e, st) {
          debugPrint('error: $e\n$st');
        }
      }
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    }

    return _dedupeSort(records);
  }

  List<HistoryRecord> _readMonthZipRecords(Uint8List bytes, int month) {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? ndjson;
    final seen = <String>{};

    for (final entry in archive.files) {
      if (!entry.isFile) throw const FormatException('invalid entry');
      final name = entry.name;
      if (name.contains('/') || name.contains('\\')) {
        throw const FormatException('invalid entry path');
      }
      if (!seen.add(name)) throw const FormatException('duplicate entry');
      if (name == '$month.ndjson') ndjson = entry;
    }

    if (ndjson == null) throw const FormatException('missing month ndjson');
    if (ndjson.size <= 0 || ndjson.size > _maxMonthNdjsonSize) {
      throw const FormatException('invalid month ndjson size');
    }

    final data = ndjson.readBytes();
    if (data == null || data.length != ndjson.size) {
      throw const FormatException('invalid month ndjson');
    }

    final records = _parseNdjson(data);
    if (records == null) throw const FormatException('invalid month header');
    return records;
  }

  Future<List<HistoryRecord>> _readDayFileUnlocked(int date) async {
    final file = _dayFile(date);
    if (!await file.exists()) return const [];

    try {
      return _parseNdjson(await file.readAsBytes()) ?? const [];
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      return const [];
    }
  }

  Future<void> _importBackupLocked(
    File input,
    void Function(double) onProgress,
  ) async {
    final length = await input.length();
    if (length <= 0 || length > _maxBackupTotalSize) {
      throw const FormatException('invalid backup size');
    }

    final stream = InputFileStream(input.path);

    try {
      final archive = ZipDecoder().decodeStream(stream);
      final files = <String, ArchiveFile>{};
      var totalSize = 0;

      for (final entry in archive.files) {
        if (!entry.isFile) throw const FormatException('invalid entry');
        final name = entry.name;
        if (name.contains('/') || name.contains('\\')) {
          throw const FormatException('invalid entry path');
        }
        if (!_backupEntryPattern.hasMatch(name)) {
          throw const FormatException('invalid entry name');
        }
        if (files.containsKey(name)) {
          throw const FormatException('duplicate entry');
        }
        if (entry.size <= 0 || entry.size > _maxBackupEntrySize) {
          throw const FormatException('invalid entry size');
        }

        totalSize += entry.size;
        if (totalSize > _maxBackupTotalSize) {
          throw const FormatException('backup too large');
        }

        files[name] = entry;
      }

      if (files.length < 2 || files.length > _maxBackupEntries) {
        throw const FormatException('invalid entry count');
      }

      final manifestEntry = files[Common.historyManifestFileName];
      final sumsEntry = files[Common.sumsFileName];
      if (manifestEntry == null || sumsEntry == null) {
        throw const FormatException('missing manifest');
      }

      if (sumsEntry.size > _maxSumsSize) {
        throw const FormatException('invalid checksum size');
      }
      final sums = _parseSums(utf8.decode(_readEntry(sumsEntry)));
      final payloadEntries = files.entries
          .where((entry) => entry.key != Common.sumsFileName)
          .toList(growable: false);

      if (sums.length != payloadEntries.length) {
        throw const FormatException('checksum count mismatch');
      }
      for (final entry in payloadEntries) {
        if (!sums.containsKey(entry.key)) {
          throw const FormatException('missing checksum');
        }
      }

      final total = payloadEntries.length;
      var verified = 0;
      Uint8List? manifestBytes;

      for (final entry in payloadEntries) {
        final bytes = _readEntry(entry.value);
        final actual = sha256.convert(bytes).toString();
        if (actual != sums[entry.key]) {
          throw const FormatException('checksum mismatch');
        }
        if (entry.key == Common.historyManifestFileName) {
          manifestBytes = bytes;
        }
        verified++;
        onProgress(0.4 * verified / total);
      }

      if (manifestBytes == null) {
        throw const FormatException('missing manifest');
      }

      final manifest = _parseManifest(manifestBytes);
      final archiveMonths =
          (manifest['archiveMonths'] as List<String>).map(int.parse).toList()
            ..sort();
      final dailyFiles =
          (manifest['dailyFiles'] as List<String>).toList()..sort();

      final expected = <String>{
        Common.historyManifestFileName,
        Common.sumsFileName,
        for (final month in archiveMonths) '$month.zip',
        ...dailyFiles,
      };
      if (expected.length != files.length ||
          !files.keys.every((name) => expected.contains(name))) {
        throw const FormatException('manifest mismatch');
      }

      final currentMonth = Common.currentMonth();
      for (final month in archiveMonths) {
        if (month >= currentMonth) {
          throw const FormatException('invalid archive month');
        }
      }

      var processed = 0;
      for (final month in archiveMonths) {
        final bytes = _readEntry(files['$month.zip']!);
        final backupRecords = _parseBackupMonthZip(bytes, month);
        final localRecords = await _readMonthUnlocked(month);

        if (backupRecords.length > localRecords.length) {
          await _writeAtomic(File('${_directory!.path}/$month.zip'), bytes);
          await _deleteMonthDayFiles(month);
        }

        processed++;
        onProgress(0.4 + 0.6 * processed / total);
      }

      for (final name in dailyFiles) {
        final bytes = _readEntry(files[name]!);
        final parsed = _parseNdjson(bytes);
        if (parsed == null) {
          throw const FormatException('invalid day ndjson');
        }

        final date = int.parse(_dayFilePattern.firstMatch(name)!.group(1)!);
        final localRecords = await _readDayFileUnlocked(date);
        final merged = _dedupeSort([...localRecords, ...parsed]);
        await _writeAtomic(_dayFile(date), _encodeNdjson(merged));

        processed++;
        onProgress(0.4 + 0.6 * processed / total);
      }

      onProgress(1);
    } finally {
      try {
        await stream.close();
      } catch (_) {}
    }
  }

  List<HistoryRecord> _parseBackupMonthZip(Uint8List bytes, int month) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, ArchiveFile>{};

    for (final entry in archive.files) {
      if (!entry.isFile) throw const FormatException('invalid entry');
      final name = entry.name;
      if (name.contains('/') || name.contains('\\')) {
        throw const FormatException('invalid entry path');
      }
      if (files.containsKey(name)) {
        throw const FormatException('duplicate entry');
      }
      files[name] = entry;
    }

    if (files.length != 2) throw const FormatException('invalid month zip');

    final ndjsonEntry = files['$month.ndjson'];
    final sumsEntry = files[Common.sumsFileName];
    if (ndjsonEntry == null || sumsEntry == null) {
      throw const FormatException('missing month file');
    }

    if (ndjsonEntry.size <= 0 || ndjsonEntry.size > _maxMonthNdjsonSize) {
      throw const FormatException('invalid month ndjson size');
    }
    if (sumsEntry.size <= 0 || sumsEntry.size > _maxSumsSize) {
      throw const FormatException('invalid checksum size');
    }

    final ndjsonBytes = _readEntry(ndjsonEntry);
    final sums = _parseSums(utf8.decode(_readEntry(sumsEntry)));
    if (sums.length != 1) throw const FormatException('invalid checksum');

    final expected = sums['$month.ndjson'];
    if (expected == null) throw const FormatException('missing checksum');
    if (sha256.convert(ndjsonBytes).toString() != expected) {
      throw const FormatException('checksum mismatch');
    }

    final records = _parseNdjson(ndjsonBytes);
    if (records == null) throw const FormatException('invalid month header');
    return records;
  }

  Map<String, String> _parseSums(String text) {
    final sums = <String, String>{};
    final body = text.startsWith('\uFEFF') ? text.substring(1) : text;

    for (final rawLine in const LineSplitter().convert(body)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final separator = line.indexOf(RegExp(r'\s'));
      if (separator <= 0) throw const FormatException('invalid checksum line');

      final hash = line.substring(0, separator);
      var name = line.substring(separator).trim();
      if (name.startsWith('*')) name = name.substring(1);

      if (!_hex64.hasMatch(hash)) {
        throw const FormatException('invalid checksum');
      }
      if (name.isEmpty || name.contains('/') || name.contains('\\')) {
        throw const FormatException('invalid checksum path');
      }
      if (sums.containsKey(name)) {
        throw const FormatException('duplicate checksum');
      }

      sums[name] = hash.toLowerCase();
    }

    return sums;
  }

  Map<String, Object> _parseManifest(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('invalid manifest');

    final version = decoded['v'];
    if (version is! int || version != Common.historySchemaVersion) {
      throw const FormatException('invalid manifest version');
    }

    final exportedAt = decoded['exportedAt'];
    if (exportedAt is! int || exportedAt <= 0) {
      throw const FormatException('invalid manifest time');
    }

    final monthsRaw = decoded['archiveMonths'];
    final dailiesRaw = decoded['dailyFiles'];
    final fileCount = decoded['fileCount'];
    if (monthsRaw is! List || dailiesRaw is! List || fileCount is! int) {
      throw const FormatException('invalid manifest fields');
    }

    final archiveMonths = <String>[];
    for (final value in monthsRaw) {
      if (value is! String ||
          !_monthPattern.hasMatch(value) ||
          !Common.isValidMonth(int.parse(value))) {
        throw const FormatException('invalid archive month');
      }
      if (archiveMonths.contains(value)) {
        throw const FormatException('duplicate archive month');
      }
      archiveMonths.add(value);
    }

    final dailyFiles = <String>[];
    for (final value in dailiesRaw) {
      if (value is! String) throw const FormatException('invalid daily file');
      final match = _dayFilePattern.firstMatch(value);
      if (match == null || !Common.isValidDate(int.parse(match.group(1)!))) {
        throw const FormatException('invalid daily file');
      }
      if (dailyFiles.contains(value)) {
        throw const FormatException('duplicate daily file');
      }
      dailyFiles.add(value);
    }

    final expectedCount = archiveMonths.length + dailyFiles.length + 2;
    if (fileCount != expectedCount) {
      throw const FormatException('invalid manifest file count');
    }

    return {
      'v': version,
      'exportedAt': exportedAt,
      'archiveMonths': archiveMonths,
      'dailyFiles': dailyFiles,
      'fileCount': fileCount,
    };
  }

  Uint8List _readEntry(ArchiveFile entry) {
    if (entry.size <= 0 || entry.size > _maxBackupEntrySize) {
      throw const FormatException('invalid entry size');
    }

    final bytes = entry.readBytes();
    if (bytes == null || bytes.length != entry.size) {
      throw const FormatException('invalid entry content');
    }
    return bytes;
  }

  Future<void> _deleteMonthDayFiles(int month) async {
    final directory = _directory;
    if (directory == null) return;

    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = _basename(entity.path);
      final match = _dayFilePattern.firstMatch(name);
      if (match == null) continue;
      final date = int.parse(match.group(1)!);
      if (!Common.isValidDate(date) || Common.monthDateOf(date) != month) {
        continue;
      }

      try {
        await entity.delete();
      } catch (e, st) {
        debugPrint('error: $e\n$st');
      }
    }
  }

  Future<void> _writeAtomic(File target, List<int> bytes) async {
    final temp = File('${target.path}.tmp');

    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
    } catch (e) {
      try {
        await temp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<String> _hashFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  File _dayFile(int date) => File('${_directory!.path}/$date.ndjson');

  String _header() => jsonEncode({
    'v': Common.historySchemaVersion,
    'fields': Common.historyFields,
  });

  Uint8List _encodeNdjson(List<HistoryRecord> records) {
    final buffer = StringBuffer('${_header()}\n');
    for (final record in records) {
      buffer.writeln(jsonEncode(record.toRow()));
    }
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  static List<HistoryRecord>? _parseNdjson(Uint8List bytes) {
    try {
      var text = utf8.decode(bytes);
      if (text.startsWith('\uFEFF')) text = text.substring(1);

      final lines =
          const LineSplitter()
              .convert(text)
              .where((line) => line.trim().isNotEmpty)
              .toList();
      if (lines.isEmpty) return null;

      final header = jsonDecode(lines.first);
      if (header is! Map) return null;
      if (header['v'] != Common.historySchemaVersion) return null;

      final fields = header['fields'];
      if (fields is! List || fields.length != Common.historyFields.length) {
        return null;
      }
      for (var i = 0; i < Common.historyFields.length; i++) {
        if (fields[i] != Common.historyFields[i]) return null;
      }

      final records = <HistoryRecord>[];
      for (final line in lines.skip(1)) {
        try {
          final record = HistoryRecord.tryParse(jsonDecode(line));
          if (record != null) records.add(record);
        } catch (_) {}
      }

      return records;
    } catch (_) {
      return null;
    }
  }

  static List<HistoryRecord> _dedupeSort(Iterable<HistoryRecord> input) =>
      HistoryRecord.mergeDedup(input);

  static String _basename(String path) {
    final index = path.lastIndexOf(Platform.pathSeparator);
    return index < 0 ? path : path.substring(index + 1);
  }
}
