import 'dart:math';

import 'common.dart';
import 'station_manager.dart';

/// 核心定位引擎
class SearchEngine {
  late final StationManager _manager;

  SearchEngine._load(this._manager);

  /// 搜索最近的 K 个节点
  /// 返回包含索引和弦长平方
  List<StationResult> locate(
      double userLatitude, double userLongitude, int count, bool active) {
    if (!_manager.isLoaded || // 数据未加载完成时返回空列表
        count <= 0) {
      return [];
    }

    final inside = Common.inside(userLatitude, userLongitude);

    var search = active ? (inside ? count * 2 : count) : 5;
    if (search < 5) search = 5;
    final take = active ? count : 1;

    final userLatRad = Common.radians(userLatitude);
    final userLonRad = Common.radians(userLongitude);
    final userCosLatRad = cos(userLatRad);
    final userSinLatRad = sin(userLatRad);
    final userCosLonRad = cos(userLonRad);
    final userSinLonRad = sin(userLonRad);

    // 目标点经纬度转单位球面 XYZ
    final userXcoord = userCosLatRad * userCosLonRad;
    final userYcoord = userCosLatRad * userSinLonRad;
    final userZcoord = userSinLatRad;

    // 结果容器
    // 手动维护升序 List
    // [last] 为当前 search 个中最远的
    final bestNodes = <({int index, double score})>[];

    // 递归搜索内部方法
    void recursiveSearch(int node, int depth) {
      if (depth > 64) return; // 防御性上限
      // 无效索引（空指针UInt32.MaxValue > 总节点数）直接返回
      if (node > _manager.count - 1) return;

      // 处理当前节点（无论是否为叶子节点）
      final dXcoord = userXcoord - _manager.getStationXcoord(node);
      final dYcoord = userYcoord - _manager.getStationYcoord(node);
      final dZcoord = userZcoord - _manager.getStationZcoord(node);
      // final score = Common.degua(...);
      final score = dXcoord * dXcoord + dYcoord * dYcoord + dZcoord * dZcoord;
      if (bestNodes.length < search) {
        bestNodes.add((
          index: node,
          score: score,
        ));
        bestNodes.sort((a, b) => a.score.compareTo(b.score));
      } else if (score < bestNodes.last.score) {
        bestNodes[bestNodes.length - 1] = (
          index: node,
          score: score,
        );
        bestNodes.sort((a, b) => a.score.compareTo(b.score));
      }

      // 只有非叶子节点才具备向下探测的资格
      if (node >= _manager.mcount) return;
      final axis = depth % 3;
      double diff = switch (axis) {
        0 => dXcoord,
        1 => dYcoord,
        2 => dZcoord,
        _ => 0,
      };

      final int nearChild = diff < 0
          ? _manager.getStationLeft(node)
          : _manager.getStationRight(node);
      final int farChild = diff < 0
          ? _manager.getStationRight(node)
          : _manager.getStationLeft(node);

      // 递归
      // 在函数开头检查 NULL_PTR
      recursiveSearch(nearChild, depth + 1);

      // 剪枝回溯
      if (bestNodes.length < search || (diff * diff) < bestNodes.last.score) {
        recursiveSearch(farChild, depth + 1);
      }
    }

    // 执行搜索
    recursiveSearch(_manager.root, 0);

    // 节点封装内部方法
    ({
      int index,
      double score,
      double stCosLatRad,
      double stSinLatRad,
      double dCosLonRad,
      double dSinLonRad,
    }) transferNode(
        ({
          int index,
          double score,
        }) result) {
      final stLatRad =
          Common.radians(_manager.getStationLatitude(result.index));
      final stLonRad =
          Common.radians(_manager.getStationLongitude(result.index));
      final dLatRad = inside ? stLatRad - userLatRad : double.nan;
      final dLonRad = stLonRad - userLonRad;

      final stCosLatRad = cos(stLatRad);
      final stSinLatRad = sin(stLatRad);
      final dCosLonRad = cos(dLonRad);
      final dSinLonRad = sin(dLonRad);

      // inside 时计算 pythagorean
      final score = inside
          // ? Common.pythagorean(userCosLatRad, stCosLatRad, dLatRad, dLonRad)
          ? Common.pythagorean(dLatRad, dLonRad)
          : result.score;

      return (
        index: result.index,
        score: score,
        stCosLatRad: stCosLatRad,
        stSinLatRad: stSinLatRad,
        dCosLonRad: dCosLonRad,
        dSinLonRad: dSinLonRad,
      );
    }

    final transferNodes = inside
        ? (bestNodes.map((result) => transferNode(result)).toList()
              ..sort((a, b) => a.score.compareTo(b.score)))
            .take(take)
        : bestNodes.take(take).map((result) => transferNode(result));

    return transferNodes.map((result) {
      final (gcd, name) = _manager.getStationName(result.index);
      final distance = inside
          ? Common.equirectangular(result.score)
          : Common.haversine(result.score);

      return StationResult(
        gcd: gcd,
        name: name,
        distance: distance,
        bearing: Common.bearing(
          userCosLatRad,
          userSinLatRad,
          result.stCosLatRad,
          result.stSinLatRad,
          result.dCosLonRad,
          result.dSinLonRad,
        ),
      );
    }).toList(growable: false);
  }

  static Future<SearchEngine> load() async {
    return SearchEngine._load(await StationManager.load());
  }
}
