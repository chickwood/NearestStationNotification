import 'package:flutter/foundation.dart';

import '../manager/history_manager.dart';

class HistoryArchiveResult {
  final bool succeeded;
  final bool cancelled;
  final Object? error;
  final int completed;
  final int failed;
  final int total;

  const HistoryArchiveResult._({
    required this.succeeded,
    required this.cancelled,
    required this.completed,
    required this.failed,
    required this.total,
    this.error,
  });

  factory HistoryArchiveResult.success({
    required int completed,
    required int failed,
    required int total,
  }) => HistoryArchiveResult._(
    succeeded: true,
    cancelled: false,
    completed: completed,
    failed: failed,
    total: total,
  );

  factory HistoryArchiveResult.cancelled({
    required int completed,
    required int failed,
    required int total,
  }) => HistoryArchiveResult._(
    succeeded: false,
    cancelled: true,
    completed: completed,
    failed: failed,
    total: total,
  );

  factory HistoryArchiveResult.failure(
    Object error, {
    required int completed,
    required int failed,
    required int total,
  }) => HistoryArchiveResult._(
    succeeded: false,
    cancelled: false,
    completed: completed,
    failed: failed,
    total: total,
    error: error,
  );
}

class HistoryArchiveService {
  final ValueNotifier<HistoryArchiveResult?> last = ValueNotifier(null);
  final ValueNotifier<bool> busy = ValueNotifier(false);
  final ValueNotifier<double> progress = ValueNotifier(0);

  bool _disposed = false;
  bool _cancelRequested = false;
  bool _running = false;

  Future<void> start(HistoryManager historyManager) async {
    if (_disposed || _running) return;

    _running = true;
    _cancelRequested = false;
    _setProgress(0);

    try {
      final months = await historyManager.listUnarchivedMonths();
      if (_disposed || _cancelRequested || months.isEmpty) return;

      if (_disposed) return;
      busy.value = true;

      final outcome = await historyManager.consolidateMonths(
        months,
        onProgress: (done, total) {
          _setProgress(total <= 0 ? 1 : done / total);
        },
        isCancelled: () => _disposed || _cancelRequested,
      );

      if (_disposed) return;

      if (outcome.cancelled) {
        _setResult(
          HistoryArchiveResult.cancelled(
            completed: outcome.completed,
            failed: outcome.failed,
            total: outcome.total,
          ),
        );
      } else if (outcome.failed > 0) {
        _setResult(
          HistoryArchiveResult.failure(
            StateError('history archive failed'),
            completed: outcome.completed,
            failed: outcome.failed,
            total: outcome.total,
          ),
        );
      } else {
        _setProgress(1);
        _setResult(
          HistoryArchiveResult.success(
            completed: outcome.completed,
            failed: outcome.failed,
            total: outcome.total,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('error: $e\n$st');
      _setResult(
        HistoryArchiveResult.failure(e, completed: 0, failed: 1, total: 0),
      );
    } finally {
      _running = false;
      if (!_disposed) busy.value = false;
    }
  }

  void cancel() {
    _cancelRequested = true;
  }

  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    last.dispose();
    busy.dispose();
    progress.dispose();
  }

  void _setProgress(double value) {
    if (_disposed) return;
    progress.value = value.clamp(0.0, 1.0).toDouble();
  }

  void _setResult(HistoryArchiveResult result) {
    if (_disposed) return;
    last.value = result;
  }
}
