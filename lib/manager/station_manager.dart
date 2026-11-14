import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../common.dart';

/// 车站信息管理器
/// 駅データ.jp CSV 解析 + BIN 文件读写
class StationManager {
  late final Float64List _latitudes; // 纬度区
  late final Float64List _longitudes; // 经度区
  late final Float64List _xcoords; // X 区
  late final Float64List _ycoords; // Y 区
  late final Float64List _zcoords; // Z 区
  late final Uint32List _lefts; // KD-Tree Left 区
  late final Uint32List _rights; // KD-Tree Right 区
  late final Uint32List _offsets; // 车站名偏移索引区
  late final Uint32List _gcds; // gcd 区（v2；旧版为空）
  late final Uint8List _names; // 车站名原始数据区 (变长)
  late final bool _legacy; // 旧格式标志（缺少 gcd 区与版本尾）
  final Map<int, int> _nodesByGcd = {}; // gcd → node（增量填充）
  int _scanCursor = 0; // 已连续扫描的 node 上界（不含）

  // _manager 构造时赋值
  // _info 使用默认值
  final int root; // KD-Tree 根节点索引
  final int mcount;
  final int count;
  final int date;
  final int pdate;
  final int size;

  bool get isLoaded =>
      count > 0 &&
      (_latitudes.isNotEmpty) &&
      (_longitudes.isNotEmpty) &&
      (_xcoords.isNotEmpty) &&
      (_ycoords.isNotEmpty) &&
      (_zcoords.isNotEmpty) &&
      (_offsets.isNotEmpty) &&
      (_names.isNotEmpty);

  /// 示例数据判定（count 阈值）
  bool get isSampleData => count > 0 && count < Common.sampleThreshold;

  StationManager._manager(
    this._latitudes,
    this._longitudes,
    this._xcoords,
    this._ycoords,
    this._zcoords,
    this._lefts,
    this._rights,
    this._gcds,
    this._offsets,
    this._names,
    this._legacy, {
    required this.root,
    required this.mcount,
    required this.count,
    required this.date,
    required this.pdate,
    required this.size,
  });

  StationManager._info()
    : root = Common.intMaxValue,
      mcount = 0,
      count = 0,
      date = 0,
      pdate = 0,
      size = 0;

  // ── BIN 文件读写 ────────────────────────────────────────────────

  /// BIN ファイルを読み込み
  /// 读取（资产加载）失败时抛出异常
  static Future<ByteData> _loadStationBin() async {
    ByteData? data;

    // 先尝试从私有目录加载
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${Common.binFileName}');
      if (await file.exists()) {
        data = ByteData.sublistView(await file.readAsBytes());
      }
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    }

    // 私有目录没有有效数据时尝试从 assets 加载
    data ??= await rootBundle.load('assets/${Common.binFileName}');

    return data;
  }

  /// 文件末尾 2 字节是否为 v2 版本标志
  static bool _isV2(ByteData data) {
    final size = data.lengthInBytes;
    if (size < 2) return false;

    return utf8.decode(
          data.buffer.asUint8List(data.offsetInBytes + size - 2, 2),
          allowMalformed: true,
        ) ==
        Common.stationSchemaVersion;
  }

  /// 尺寸 / 结构校验（加载、写入共用）
  /// v1（尾部 20 字节）与 v2（尾部 22 字节，追加 gcd 区）均接受
  static bool validate(ByteData data) {
    final size = data.lengthInBytes;
    if (size < 24) return false;

    final v2 = _isV2(data);
    final tailSize = v2 ? 22 : 20;
    final mcount = data.getUint32(size - tailSize + 4, Endian.little);
    final count = data.getUint32(size - tailSize + 8, Endian.little);

    // v2: count * (经纬度(40) + gcd(4) + 车站名偏移(4)) + left/right(mcount * 8) + 尾部(22)
    // v1: 维持原有校验 count * (经纬度(40) + 车站名偏移(4)) + 尾部(20)
    final base = v2 ? count * 48 + mcount * 8 + 22 : count * 44 + 20;

    return size > base;
  }

  /// StationManager インスタンスを生成する
  /// 解析校验失败时返回空实例
  static Future<StationManager> load() async {
    final data = await _loadStationBin();
    if (!validate(data)) return StationManager._info();

    // 提取车站数和日期戳
    final size = data.lengthInBytes;
    final v2 = _isV2(data);
    final tailSize = v2 ? 22 : 20;
    final tail = size - tailSize;
    final root = data.getUint32(tail, Endian.little);
    final mcount = data.getUint32(tail + 4, Endian.little);
    final count = data.getUint32(tail + 8, Endian.little);
    final date = data.getUint32(tail + 12, Endian.little);
    final pdate = data.getUint32(tail + 16, Endian.little);

    final gcdStart = (count * 40) + (mcount * 8);
    final offsetsStart = gcdStart + (v2 ? count * 4 : 0);
    final namesStart = offsetsStart + (count * 4);

    return StationManager._manager(
      data.buffer.asFloat64List(data.offsetInBytes, count),
      data.buffer.asFloat64List(data.offsetInBytes + (count * 8), count),
      data.buffer.asFloat64List(data.offsetInBytes + (count * 16), count),
      data.buffer.asFloat64List(data.offsetInBytes + (count * 24), count),
      data.buffer.asFloat64List(data.offsetInBytes + (count * 32), count),
      data.buffer.asUint32List(data.offsetInBytes + (count * 40), mcount),
      data.buffer.asUint32List(
        data.offsetInBytes + (count * 40) + (mcount * 4),
        mcount,
      ),
      v2
          ? data.buffer.asUint32List(data.offsetInBytes + gcdStart, count)
          : Uint32List(0),
      data.buffer.asUint32List(data.offsetInBytes + offsetsStart, count),
      data.buffer.asUint8List(
        data.offsetInBytes + namesStart,
        size - tailSize - namesStart,
      ),
      !v2,
      root: root,
      mcount: mcount,
      count: count,
      date: date,
      pdate: pdate,
      size: size,
    );
  }

  /// 原子写入私有目录（临时文件 → 改名；失败不覆盖现有文件）
  static Future<void> write(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = File('${dir.path}/${Common.binFileName}');
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

  // ── 数据访问 ────────────────────────────────────────────────────

  /// 根据索引按需获取车站名 (Lazy Loading)
  /// 解析失败时返回 (null, null) 以与正常数据区分
  (int?, String?) getGcdName(int node) {
    try {
      if (isLoaded) {
        final int start = _offsets[node];
        final int end = (node == _offsets.length - 1)
            ? _names.length
            : _offsets[node + 1];
        final nameBytes = _names.buffer.asUint8List(
          _names.offsetInBytes + start,
          end - start,
        );

        if (_legacy) {
          final match = Common.namePattern.firstMatch(utf8.decode(nameBytes));
          if (match != null) {
            final gcd = int.parse(match.group(1)!);
            _nodesByGcd[gcd] = node;
            return (gcd, match.group(2)!);
          }
        } else {
          final gcd = _gcds[node];
          _nodesByGcd[gcd] = node;
          return (gcd, utf8.decode(nameBytes));
        }
      }
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    }

    return (null, null);
  }

  /// 根据 gcd 获取 node
  /// v2：扁平扫描 gcd 区并缓存命中项；旧版：按扫描游标增量解析站名
  int? getNodeByGcd(int gcd) {
    if (!isLoaded) return null;

    final cached = _nodesByGcd[gcd];
    if (cached != null) return cached;

    if (_legacy) {
      // 已扫描全部 node 时，缺失即为确定结果
      while (_scanCursor < count) {
        final node = _scanCursor++;
        final (stationGcd, _) = getGcdName(node);
        if (stationGcd == gcd) return node;
      }
    } else {
      for (var node = 0; node < count; node++) {
        if (_gcds[node] == gcd) {
          _nodesByGcd[gcd] = node;
          return node;
        }
      }
    }

    return null;
  }

  // 根据索引按需获取车站坐标详情
  double getStationLat(int node) => _latitudes[node];
  double getStationLon(int node) => _longitudes[node];
  double getStationXcoord(int node) => _xcoords[node];
  double getStationYcoord(int node) => _ycoords[node];
  double getStationZcoord(int node) => _zcoords[node];
  int getStationLeft(int node) => _lefts[node];
  int getStationRight(int node) => _rights[node];
}
