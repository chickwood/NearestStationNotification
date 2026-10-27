import 'dart:async';

import 'package:flutter/foundation.dart';

import '../common.dart';
import '../manager/history_manager.dart';
import '../manager/settings_manager.dart';

/// 定位結果の常駐コンシューマ（履歴記録担当）
/// - 放送された payload だけで駅切替・記録スイッチ・同駅 5 分以内の補記スキップを判定する
/// - 記録は pending に溜め、10 条または先頭の入隊から 5 分で
///   HistoryManager へ日付単位でまとめて追記する
/// - 書き込み成功分だけ pending から除去し、進捗を自身の flushCount で通知する
/// - pending の公開は Coordinator が担い、UI へは直接触れない
class HistoryConsumer {
  static const _flushThreshold = 10;
  static const _flushInterval = Duration(minutes: 5);

  bool _active;
  final HistoryManager _historyManager;
  HistorySettingsManager _settingsManager;

  final List<HistoryRecord> _pending = [];
  final ValueNotifier<int> _pendingRevision = ValueNotifier<int>(0);

  Timer? _flushTimer;
  Future<void>? _flushing;
  bool _flushBlockedUntilTimer = false;
  DateTime? _pendingSince;
  final ValueNotifier<int> _flushCount = ValueNotifier<int>(0);

  bool _hasLastHistory = false;
  int? _lastHistoryGcd;

  int _date = Common.dateOf(DateTime.now());

  int? _lastProcessedEpoch;
  PositionResult? _lastPositionResult;
  List<StationResult>? _lastStationResults;

  HistoryConsumer(this._active, this._historyManager, this._settingsManager);

  /// 未落盘记录（当日展示は disk + この一覧を日付で合并する）
  List<HistoryRecord> get pendingRecords =>
      List<HistoryRecord>.unmodifiable(_pending);

  /// pending 追加通知（値ではなく変化のみを購読する）
  ValueListenable<int> get pendingRevision => _pendingRevision;

  /// 落盘进度通知（値そのものは使わず、変化のみを購読する）
  ValueListenable<int> get flushCount => _flushCount;

  // ── 定位結果イベント（常駐 handler） ──────────────────────────────

  void handleLocationResultReceived(
    PositionResult? positionResult,
    List<StationResult>? stationResults,
  ) {
    // stop() の forceNotify は (null, null)。セッション状態を破棄して
    // 次回 start 後の初回定位で改めて記録できるようにする
    if (positionResult == null || stationResults == null) {
      _resetSession();
      return;
    }

    // 前台復帰時の再放送など、同一の定位結果をもう一度受けても二重処理しない
    final epoch = positionResult.timestamp.millisecondsSinceEpoch;
    if (epoch == _lastProcessedEpoch) return;
    _lastProcessedEpoch = epoch;

    _lastPositionResult = positionResult;
    _lastStationResults = stationResults;

    // 前回セッションの未落盘分が残っている場合は、その先頭の入隊時刻
    // 起点に flush されるようタイマーを張り直す
    if (_flushing == null && _pending.isNotEmpty) _armTimer();

    _rollDateIfNeeded(epoch);
    _recordOnStationChange(positionResult, stationResults);
  }

  // ── 設定・フラッシュ ────────────────────────────────────────────

  /// 設定更新（オフ → オン時は現在の通知駅を補記）
  Future<void> changeSettings(HistorySettingsManager manager) async {
    final wasEnabled = _settingsManager.historyEnabled;
    _settingsManager = manager;

    if (!wasEnabled && manager.historyEnabled) await _recordLastIfNeeded();
  }

  /// UI 活動状態の変更
  /// active が false → true になった場合は画面向け通知を再送する
  void changeActive(bool active) {
    final activeChanged = _active != active;
    _active = active;

    if (activeChanged && _active) {
      // HomePage の再放送に相当：復帰時に pending / disk を取り直させる
      _pendingRevision.value++;
      _flushCount.value++;
    }
  }

  /// pending をすべて日ファイルへ追記する（stop / 导出 / 导入前）
  Future<void> flush() {
    final running = _flushing;
    if (running != null) return running;

    final future = _flushPending();
    _flushing = future;
    return future;
  }

  Future<void> _flushPending() async {
    // _flushing を設定してから本体を再開させる
    await Future<void>.value();

    _flushTimer?.cancel();
    _flushTimer = null;

    var wroteAny = false;
    var failed = false;
    try {
      while (_pending.isNotEmpty) {
        final batch = _nextPendingGroup();
        try {
          await _historyManager.appendRecords(batch);
        } catch (e, st) {
          debugPrint('error: $e\n$st');
          failed = true;
          break;
        }
        final written = Set<HistoryRecord>.identity()..addAll(batch);
        _pending.removeWhere(written.contains);
        wroteAny = true;
      }
      if (!failed) _flushBlockedUntilTimer = false;
    } finally {
      if (wroteAny && _active) _flushCount.value++;

      _flushing = null;

      if (failed) {
        // 失敗した flush の完了時刻を次回の 5 分窓の起点にする
        _flushBlockedUntilTimer = true;
        _pendingSince = DateTime.now();
        _armTimer();
      } else if (_pending.isEmpty) {
        _pendingSince = null;
        _flushTimer?.cancel();
        _flushTimer = null;
      } else if (_pending.length >= _flushThreshold) {
        unawaited(flush());
      } else {
        _armTimer();
      }
    }
  }

  List<HistoryRecord> _nextPendingGroup() {
    final date = Common.dateOfEpoch(_pending.first.epoch);
    return _pending
        .where((record) => Common.dateOfEpoch(record.epoch) == date)
        .toList(growable: false);
  }

  // ── 記録判定 ────────────────────────────────────────────────────

  /// 日付が変わったら切替ベースラインを破棄し、新しい日の初回定位で
  /// 同じ駅でも改めて記録できるようにする
  void _rollDateIfNeeded(int epoch) {
    final date = Common.dateOfEpoch(epoch);
    if (date == _date) return;

    _date = date;
    _hasLastHistory = false;
    _lastHistoryGcd = null;
  }

  void _recordOnStationChange(
    PositionResult positionResult,
    List<StationResult> stationResults,
  ) {
    if (stationResults.isEmpty) return;

    final first = stationResults.first;
    final stationChanged =
        _hasLastHistory ? first.gcd != _lastHistoryGcd : first.gcd != null;

    _hasLastHistory = true;
    _lastHistoryGcd = first.gcd;

    if (!stationChanged ||
        !_settingsManager.historyEnabled ||
        first.gcd == null) {
      return;
    }

    _append(
      HistoryRecord(
        gcd: first.gcd!,
        latE6: (positionResult.latitude * 1e6).round(),
        lonE6: (positionResult.longitude * 1e6).round(),
        epoch: positionResult.timestamp.millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _recordLastIfNeeded() async {
    final positionResult = _lastPositionResult;
    final stationResults = _lastStationResults;
    if (positionResult == null ||
        stationResults == null ||
        stationResults.isEmpty) {
      return;
    }

    final first = stationResults.first;
    final gcd = first.gcd;
    if (gcd == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final today = Common.dateOfEpoch(now);
    final stored = await _historyManager.readDay(today);

    HistoryRecord? latest;
    for (final record in [...stored, ..._pending]) {
      if (Common.dateOfEpoch(record.epoch) != today) continue;
      if (latest == null || record.epoch > latest.epoch) latest = record;
    }

    if (latest != null &&
        latest.gcd == gcd &&
        now >= latest.epoch &&
        now - latest.epoch <= Common.historyMergeWindow.inMilliseconds) {
      return;
    }

    _append(
      HistoryRecord(
        gcd: gcd,
        latE6: (positionResult.latitude * 1e6).round(),
        lonE6: (positionResult.longitude * 1e6).round(),
        epoch: now,
      ),
    );
  }

  void _append(HistoryRecord record) {
    if (_pending.isEmpty) _pendingSince = DateTime.now();
    _pending.add(record);
    if (_active) _pendingRevision.value++;
    if (_flushing == null) _armTimer();

    if (_pending.length >= _flushThreshold &&
        !_flushBlockedUntilTimer &&
        _flushing == null) {
      unawaited(flush());
    }
  }

  void _armTimer() {
    if (_flushTimer != null || _pending.isEmpty) return;

    final dueAt = (_pendingSince ??= DateTime.now()).add(_flushInterval);
    final delay = dueAt.difference(DateTime.now());

    _flushTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _flushTimer = null;
      _flushBlockedUntilTimer = false;
      unawaited(flush());
    });
  }

  void _resetSession() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _flushBlockedUntilTimer = false;

    _lastProcessedEpoch = null;
    _lastPositionResult = null;
    _lastStationResults = null;
    _hasLastHistory = false;
    _lastHistoryGcd = null;
  }
}
