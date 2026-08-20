import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'common.dart';

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

  // _manager 构造时赋值
  // _info 使用默认值
  final int root; // KD-Tree 根节点索引
  final int mcount;
  final int count;
  final int date;
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
    required this.size,
  });

  StationManager._info()
      : root = Common.intMaxValue,
        mcount = 0,
        count = 0,
        date = 0,
        size = 0;

  // ── BIN 文件读写 ────────────────────────────────────────────────

  /// BIN ファイルを読み込み StationManager インスタンスを生成する
  /// 读取或解析失败时抛出异常
  /// 将来的には documents → assets の順に試み
  /// どちらも存在しないか 0 バイトなら null を返す
  static Future<StationManager> load() async {
    final data = await _loadStationBin();

    // 数据完整性校验
    // 总长度应大于尾部长度 (车站数(4) + 日期戳(4))
    final size = data.lengthInBytes;
    if (size > 16) {
      // 提取车站数和日期戳
      final root = data.getUint32(size - 16, Endian.little);
      final mcount = data.getUint32(size - 12, Endian.little);
      final count = data.getUint32(size - 8, Endian.little);
      final date = data.getUint32(size - 4, Endian.little);

      // 取得 _count 后的数据完整性校验
      // 总长度应大于不含车站名的基础长度加尾部长度
      // (_count * (经纬度(16) + XYZ(24) + 车站名偏移(4)) + 根节点索引(4) + 非叶节点数(4) + 车站数(4) + 日期戳(4))
      if (size > (count * 44) + 16) {
        return StationManager._manager(
          data.buffer.asFloat64List(data.offsetInBytes, count),
          data.buffer.asFloat64List(data.offsetInBytes + (count * 8), count),
          data.buffer.asFloat64List(data.offsetInBytes + (count * 16), count),
          data.buffer.asFloat64List(data.offsetInBytes + (count * 24), count),
          data.buffer.asFloat64List(data.offsetInBytes + (count * 32), count),
          data.buffer.asUint32List(data.offsetInBytes + (count * 40), mcount),
          data.buffer.asUint32List(
              data.offsetInBytes + (count * 40) + (mcount * 4), mcount),
          data.buffer.asUint32List(
              data.offsetInBytes + (count * 40) + (mcount * 8), count),
          data.buffer.asUint8List(
              data.offsetInBytes + (count * 44) + (mcount * 8),
              size - 16 - (count * 44) - (mcount * 8)),
          root: root,
          mcount: mcount,
          count: count,
          date: date,
          size: size,
        );
      }
    }

    return StationManager._info();
  }

  // static Future<StationManager> loadInfo() async {
  //   final data = await _loadStationBin();

  //   // 数据完整性校验
  //   // 总长度应大于尾部长度 (车站数(4) + 日期戳(4))
  //   final size = data.lengthInBytes;
  //   if (size > 16) {
  //     // 提取车站数和日期戳
  //     final root = data.getUint32(size - 16, Endian.little);
  //     final mcount = data.getUint32(size - 12, Endian.little);
  //     final count = data.getUint32(size - 8, Endian.little);
  //     final date = data.getUint32(size - 4, Endian.little);

  //     // 提取车站数和日期戳
  //     return StationManager._info(
  //       root: root,
  //       mcount: mcount,
  //       count: count,
  //       date: date,
  //       size: size,
  //     );
  //   }

  //   return StationManager._info();
  // }

  static Future<ByteData> _loadStationBin() async {
    ByteData? data;

    // // 先尝试从私有目录加载
    // final path =
    //     await PathProviderPlatform.instance.getApplicationDocumentsPath();
    // if (path != null) {
    //   final dir = Directory(path);
    //   final file = File('${dir.path}/${Common.binFileName}');
    //   if (await file.exists()) {
    //     final bytes = await file.readAsBytes();
    //     if (bytes.length > 8) data = bytes.buffer.asByteData();
    //   }
    // }

    // 私有目录没有有效数据时尝试从 assets 加载
    data ??= await rootBundle.load('assets/${Common.binFileName}');

    return data;
  }

  // ── 数据访问 ────────────────────────────────────────────────────

  /// 根据索引按需获取车站名 (Lazy Loading)
  /// 解析失败时返回 (null, null) 以与正常数据区分
  (int?, String?) getStationName(int index) {
    try {
      if (isLoaded) {
        final int start = _offsets[index];
        final int end = (index == _offsets.length - 1)
            ? _names.length
            : _offsets[index + 1];
        final nameBytes = _names.buffer
            .asUint8List(_names.offsetInBytes + start, end - start);

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

  // 根据索引按需获取车站坐标详情
  double getStationLatitude(int index) => _latitudes[index];
  double getStationLongitude(int index) => _longitudes[index];
  double getStationXcoord(int index) => _xcoords[index];
  double getStationYcoord(int index) => _ycoords[index];
  double getStationZcoord(int index) => _zcoords[index];
  int getStationLeft(int index) => _lefts[index];
  int getStationRight(int index) => _rights[index];
}
