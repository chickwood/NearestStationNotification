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
  late final Uint8List _names; // 车站名原始数据区 (变长)
  Map<int, String>? _namesByGcd;

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
    this._offsets,
    this._names, {
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

  /// 尺寸 / 结构校验（加载、写入共用）
  static bool validate(ByteData data) {
    // 数据完整性校验
    // 总长度应大于尾部长度 (根节点索引(4) + 非叶节点数(4) + 车站数(4) + 日期戳(4) + 修订日期戳(4))
    final size = data.lengthInBytes;
    if (size > 20) {
      // 提取车站数
      final count = data.getUint32(size - 12, Endian.little);

      // 取得 count 后的数据完整性校验
      // 总长度应大于不含车站名的基础长度加尾部长度
      // (count * (经纬度(16) + XYZ(24) + 车站名偏移(4)) + 根节点索引(4) + 非叶节点数(4) + 车站数(4) + 日期戳(4) + 修订日期戳(4))
      if (size > (count * 44) + 20) return true;
    }

    return false;
  }

  /// StationManager インスタンスを生成する
  /// 解析校验失败时返回空实例
  static Future<StationManager> load() async {
    final data = await _loadStationBin();
    if (!validate(data)) return StationManager._info();

    // 提取车站数和日期戳
    final size = data.lengthInBytes;
    final root = data.getUint32(size - 20, Endian.little);
    final mcount = data.getUint32(size - 16, Endian.little);
    final count = data.getUint32(size - 12, Endian.little);
    final date = data.getUint32(size - 8, Endian.little);
    final pdate = data.getUint32(size - 4, Endian.little);

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
      data.buffer.asUint32List(
        data.offsetInBytes + (count * 40) + (mcount * 8),
        count,
      ),
      data.buffer.asUint8List(
        data.offsetInBytes + (count * 44) + (mcount * 8),
        size - 20 - (count * 44) - (mcount * 8),
      ),
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
  (int?, String?) getStationName(int index) {
    try {
      if (isLoaded) {
        final int start = _offsets[index];
        final int end =
            (index == _offsets.length - 1)
                ? _names.length
                : _offsets[index + 1];
        final nameBytes = _names.buffer.asUint8List(
          _names.offsetInBytes + start,
          end - start,
        );

        final match = Common.namePattern.firstMatch(utf8.decode(nameBytes));
        if (match != null) {
          return (int.parse(match.group(1)!), match.group(2)!);
        }
      }
    } catch (e, st) {
      debugPrint('error: $e\n$st');
    }

    return (null, null);
  }

  /// 根据 gcd 获取车站名（首次调用时构建 gcd → name 缓存）
  String? getStationNameByGcd(int gcd) {
    if (!isLoaded) return null;

    final cached = _namesByGcd;
    if (cached != null) return cached[gcd];

    final names = <int, String>{};
    for (var index = 0; index < count; index++) {
      final (stationGcd, name) = getStationName(index);
      if (stationGcd == null || name == null) continue;
      names[stationGcd] = name;
    }

    _namesByGcd = names;
    return names[gcd];
  }

  // 根据索引按需获取车站坐标详情
  double getStationLatitude(int index) => _latitudes[index];
  double getStationLongitude(int index) => _longitudes[index];
  double getStationXcoord(int index) => _xcoords[index];
  double getStationYcoord(int index) => _ycoords[index];
  double getStationZcoord(int index) => _zcoords[index];
  int getStationLeft(int index) => _lefts[index];
  int getStationRight(int index) => _rights[index];
}
