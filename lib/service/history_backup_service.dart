import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../manager/history_manager.dart';

enum HistoryBackupAction { export, import }

class HistoryBackupResult {
  final HistoryBackupAction action;
  final bool succeeded;
  final bool cancelled;
  final Object? error;
  final String? savedPath;

  const HistoryBackupResult._({
    required this.action,
    required this.succeeded,
    required this.cancelled,
    this.error,
    this.savedPath,
  });

  factory HistoryBackupResult.success(
    HistoryBackupAction action, {
    String? savedPath,
  }) => HistoryBackupResult._(
    action: action,
    succeeded: true,
    cancelled: false,
    savedPath: savedPath,
  );

  factory HistoryBackupResult.cancelled(HistoryBackupAction action) =>
      HistoryBackupResult._(action: action, succeeded: false, cancelled: true);

  factory HistoryBackupResult.failure(
    HistoryBackupAction action,
    Object error,
  ) => HistoryBackupResult._(
    action: action,
    succeeded: false,
    cancelled: false,
    error: error,
  );
}

class HistoryBackupService {
  final ValueNotifier<HistoryBackupResult?> last = ValueNotifier(null);
  final ValueNotifier<bool> busy = ValueNotifier(false);
  final ValueNotifier<double> progress = ValueNotifier(0);

  bool _disposed = false;

  Future<void> export(HistoryManager historyManager) async {
    if (_disposed || busy.value) return;

    busy.value = true;
    progress.value = 0;
    File? temp;

    try {
      final directory = await getTemporaryDirectory();
      temp = File(
        '${directory.path}/history-backup-'
        '${DateTime.now().millisecondsSinceEpoch}.zip',
      );

      final exportedAt = await historyManager.createBackup(temp, (value) {
        _setProgress(value);
      });

      final bytes = await temp.readAsBytes();
      try {
        if (await temp.exists()) await temp.delete();
      } catch (e, st) {
        debugPrint('error: $e\n$st');
      }

      final savedUri = await FilePicker.saveFile(
        fileName: 'history-backup-$exportedAt.zip',
        bytes: bytes,
        mimeType: 'application/zip',
      );

      if (savedUri == null) {
        _setResult(HistoryBackupResult.cancelled(HistoryBackupAction.export));
      } else {
        _setProgress(1);
        _setResult(
          HistoryBackupResult.success(
            HistoryBackupAction.export,
            savedPath: savedUri.toString(),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      _setResult(HistoryBackupResult.failure(HistoryBackupAction.export, e));
    } finally {
      try {
        if (temp != null && await temp.exists()) await temp.delete();
      } catch (e, st) {
        debugPrint('error: $e\n$st');
      }
      if (!_disposed) busy.value = false;
    }
  }

  Future<void> import(HistoryManager historyManager) async {
    if (_disposed || busy.value) return;

    busy.value = true;
    progress.value = 0;

    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );

      if (picked == null) {
        _setResult(HistoryBackupResult.cancelled(HistoryBackupAction.import));
        return;
      }

      final path = picked.path;
      if (path == null) throw StateError('file path unavailable');

      await historyManager.importBackup(File(path), (value) {
        _setProgress(value);
      });

      _setProgress(1);
      _setResult(HistoryBackupResult.success(HistoryBackupAction.import));
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      _setResult(HistoryBackupResult.failure(HistoryBackupAction.import, e));
    } finally {
      if (!_disposed) busy.value = false;
    }
  }

  void dispose() {
    _disposed = true;
    last.dispose();
    busy.dispose();
    progress.dispose();
  }

  void _setProgress(double value) {
    if (_disposed) return;
    progress.value = value.clamp(0.0, 1.0).toDouble();
  }

  void _setResult(HistoryBackupResult result) {
    if (_disposed) return;
    last.value = result;
  }
}
