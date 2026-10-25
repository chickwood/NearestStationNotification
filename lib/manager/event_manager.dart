import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../common.dart';

/// 事件数据管理器
/// documents 覆盖（缺失 / 无效时为空）
class EventManager {
  final List<({int startEpoch, int endEpoch})> _periods;

  // _manager 构造时赋值
  EventManager._manager(this._periods);

  /// 当前是否处于事件期间（毫秒精度，含端点）
  bool get isEventPeriod {
    final nowEpoch = DateTime.now().millisecondsSinceEpoch;
    return _periods.any((period) {
      return nowEpoch >= period.startEpoch && nowEpoch <= period.endEpoch;
    });
  }

  // ── NDJSON 文件读写 ──────────────────────────────────────────────

  /// documents から event NDJSON バイト列を読み込み
  /// 読み込み失敗 / ファイル不存在は null
  static Future<Uint8List?> _loadEventJson() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${Common.eventFileName}');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    }

    return null;
  }

  /// 解析并校验 NDJSON；无效返回 null
  /// 仅 header、无数据行是合法空列表；时间保留为 epoch ms
  static List<({int startEpoch, int endEpoch})>? _parse(Uint8List? bytes) {
    if (bytes == null) return null;

    try {
      var text = utf8.decode(bytes);
      if (text.startsWith('\uFEFF')) {
        text = text.substring(1);
      }

      final lines =
          const LineSplitter()
              .convert(text)
              .where((line) => line.trim().isNotEmpty)
              .toList();
      if (lines.isEmpty) return null;

      final header = jsonDecode(lines.first);
      if (header is! Map) return null;

      final version = header['v'];
      if (version is! int || version != Common.eventVersion) return null;

      final fields = header['fields'];
      if (fields is! List || fields.length != Common.eventFields.length) {
        return null;
      }
      for (var i = 0; i < Common.eventFields.length; i++) {
        if (fields[i] != Common.eventFields[i]) return null;
      }

      final periods = <({int startEpoch, int endEpoch})>[];
      for (final line in lines.skip(1)) {
        final row = jsonDecode(line);
        if (row is! List || row.length != 2) return null;

        final startEpoch = row[0];
        final endEpoch = row[1];
        if (startEpoch is! int || endEpoch is! int) return null;
        if (startEpoch > endEpoch) return null;

        periods.add((startEpoch: startEpoch, endEpoch: endEpoch));
      }

      return periods;
    } catch (e) {
      return null;
    }
  }

  /// NDJSON 校验（导入时使用）
  static bool validate(Uint8List bytes) => _parse(bytes) != null;

  /// EventManager インスタンスを生成する
  /// 启动加载：documents 优先，读取失败 / 无效回退空实例（静默）
  static Future<EventManager> load() async {
    return EventManager._manager(
      _parse(await _loadEventJson()) ??
          const <({int startEpoch, int endEpoch})>[],
    );
  }

  /// 原子写入私有目录（临时文件 → 改名；失败不覆盖现有文件）
  static Future<void> write(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = File('${dir.path}/${Common.eventFileName}');
    final temp = File('${target.path}.tmp');

    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
    } catch (e) {
      try {
        await temp.delete();
      } catch (_) {
        // 清理失败时忽略，保留原始异常
      }
      rethrow;
    }
  }
}
