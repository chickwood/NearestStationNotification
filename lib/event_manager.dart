import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'common.dart';

/// 事件数据管理器
/// documents 覆盖（缺失 / 无效时为空）
class EventManager {
  final List<({DateTime start, DateTime end})> _periods;

  // _manager 构造时赋值
  EventManager._manager(this._periods);

  /// 当前是否处于事件期间
  bool get isEventPeriod {
    final now = DateTime.now();
    return _periods.any((period) {
      return !now.isBefore(period.start) && !now.isAfter(period.end);
    });
  }

  // ── JSON 文件读写 ────────────────────────────────────────────────

  /// documents から event JSON バイト列を読み込み
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

  /// 解析并校验；无效 / 无数据返回 null（空数组合法）
  static List<({DateTime start, DateTime end})>? _parse(Uint8List? bytes) {
    if (bytes == null) return null;

    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map || json['periods'] is! List) return null;

      final periods = <({DateTime start, DateTime end})>[];
      for (final item in json['periods'] as List) {
        if (item is! Map) return null;
        final start = DateTime.tryParse(item['start']?.toString() ?? '');
        final end = DateTime.tryParse(item['end']?.toString() ?? '');
        if (start == null || end == null) return null;
        if (start.isAfter(end)) return null;
        periods.add((start: start, end: end));
      }

      return periods;
    } catch (e) {
      return null;
    }
  }

  /// JSON 校验（导入时使用）
  static bool validate(Uint8List bytes) => _parse(bytes) != null;

  /// EventManager インスタンスを生成する
  /// 启动加载：documents 优先，读取失败 / 无效回退空实例（静默）
  static Future<EventManager> load() async {
    return EventManager._manager(_parse(await _loadEventJson()) ?? const []);
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
