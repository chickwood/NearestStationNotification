import 'dart:math';

class Common {
  // ── 动态包名常驻内存（由 main 在冷启动时注入） ───────────────────────
  static late final String appName;

  // 駅情報
  static const binFileName = 'station_data_xyz.bin';

  // 駅ID解析
  static final namePattern = RegExp(r'^(\d{1,7}),(.*)$');

  // // 駅データ.jp へのリンク
  // static final uriEkidata = Uri.parse('https://ekidata.jp/');

  static const fgtChannelId = 'notification_fgt_channel';
  static const fgtNotificationId = 1057;
  static const fgtNotificationIconMetaDataName =
      "name.w57.nearest_station_notification.ic_notification";

  static const flnChannelId = 'notification_fln_channel';
  static const flnNotificationId = 1058;
  static const flnNotificationIcon = "ic_notification";

  // // 距离过远检测
  // // 单位为经纬度差值平方 / 弦长平方
  // // 约等于 Equirectangular 和 Haversine 计算距离 99.55 km
  // // 二进制对应 2^-12
  // static const farScore = 2.44140625e-4;

  // GPS漂移（距离过近）检测
  // 单位为经纬度差值
  // 二进制对应 2^-15
  static const nearCoord = 3.0517578125e-5;

  // int(UInt32) 最大值
  static const intMaxValue = 4294967295;

  // 地球半径常数（米）
  static const _earthRadius = 6371000.0;
  // 角度转弧度的常数
  static const _degreesToRadians = pi / 180.0;

  // // 计算 8 方向时代表静止 （不在 0 ~ 7 范围）
  // static const int headingStaying = -1;

  // 日本全境及近海轮廓（不含离岛）
  static const _insidePolygons = [
    // 本州・四国・九州・北海道
    [
      (latitude: 42.747012, longitude: 139.284668),
      (latitude: 41.129021, longitude: 139.965820),
      (latitude: 40.763901, longitude: 139.504395),
      (latitude: 40.044438, longitude: 139.416504),
      (latitude: 39.419221, longitude: 139.570313),
      (latitude: 38.393339, longitude: 139.042969),
      (latitude: 37.335224, longitude: 137.790527),
      (latitude: 37.909534, longitude: 137.460938),
      (latitude: 37.527154, longitude: 136.208496),
      (latitude: 36.862043, longitude: 136.318359),
      (latitude: 36.066862, longitude: 135.307617),
      (latitude: 35.776229, longitude: 132.392578),
      (latitude: 35.101934, longitude: 131.791992),
      (latitude: 34.705493, longitude: 130.605469),
      (latitude: 34.016242, longitude: 130.275879),
      (latitude: 33.669497, longitude: 129.243164),
      (latitude: 32.805745, longitude: 128.935547),
      (latitude: 32.231390, longitude: 129.638672),
      (latitude: 31.034108, longitude: 129.704590),
      (latitude: 30.609550, longitude: 130.675049),
      (latitude: 31.269161, longitude: 131.671143),
      (latitude: 32.506673, longitude: 132.143555),
      (latitude: 32.333559, longitude: 133.121338),
      (latitude: 33.174342, longitude: 133.615723),
      (latitude: 32.768800, longitude: 134.241943),
      (latitude: 33.504759, longitude: 134.912109),
      (latitude: 33.005592, longitude: 135.812988),
      (latitude: 34.034453, longitude: 136.713867),
      (latitude: 34.470335, longitude: 138.273926),
      (latitude: 34.307144, longitude: 138.955078),
      (latitude: 34.759666, longitude: 139.394531),
      (latitude: 34.597042, longitude: 140.163574),
      (latitude: 35.576917, longitude: 141.313476),
      (latitude: 37.718590, longitude: 141.372070),
      (latitude: 39.639538, longitude: 142.602539),
      (latitude: 42.261049, longitude: 141.547852),
      (latitude: 41.508577, longitude: 143.349609),
      (latitude: 42.472097, longitude: 144.294434),
      (latitude: 43.309191, longitude: 146.337891),
      (latitude: 43.707594, longitude: 145.590820),
      (latitude: 44.496505, longitude: 145.590820),
      (latitude: 44.260937, longitude: 144.602051),
      (latitude: 44.653024, longitude: 143.437500),
      (latitude: 45.798170, longitude: 141.943359),
      (latitude: 45.460131, longitude: 141.020508),
      (latitude: 44.574817, longitude: 141.394043),
      (latitude: 43.500752, longitude: 140.888672),
      (latitude: 43.945372, longitude: 139.768066),
      (latitude: 43.052834, longitude: 139.987793),
    ],
    // 冲绳本岛
    [
      (latitude: 27.498527, longitude: 128.232422),
      (latitude: 26.833875, longitude: 129.166260),
      (latitude: 25.304304, longitude: 127.518311),
      (latitude: 26.106121, longitude: 126.672363),
    ],
  ];

  static bool inside(
    double latitude,
    double longitude,
  ) {
    return _insidePolygons.any((polygon) {
      bool inside = false;
      final n = polygon.length;
      for (int i = 0, j = n - 1; i < n; j = i++) {
        final latitudeI = polygon[i].latitude;
        final longitudeI = polygon[i].longitude;
        final latitudeJ = polygon[j].latitude;
        final longitudeJ = polygon[j].longitude;

        final intersect = ((latitude < latitudeI) != (latitude < latitudeJ)) &&
            (longitude <
                (longitudeJ - longitudeI) *
                        (latitude - latitudeI) /
                        (latitudeJ - latitudeI) +
                    longitudeI);
        if (intersect) inside = !inside;
      }
      return inside;
    });
  }

  static final _eventPeriods = [
    (start: DateTime(2026, 5, 1, 15), end: DateTime(2026, 5, 31, 23, 59, 59)),
  ];

  static bool event() {
    final now = DateTime.now();
    return _eventPeriods.any((period) {
      return !now.isBefore(period.start) && !now.isAfter(period.end);
    });
  }

  static bool near(
    double userLatitude,
    double userLongitude,
    double prevLatitude,
    double prevLongitude,
  ) {
    final dLatitude = userLatitude - prevLatitude;
    final dLongitude = userLongitude - prevLongitude;

    return dLatitude < Common.nearCoord &&
        dLatitude > -Common.nearCoord &&
        dLongitude < Common.nearCoord &&
        dLongitude > -Common.nearCoord;
  }

  static double radians(double degrees) {
    return degrees * _degreesToRadians;
  }

  static double bearing(
    double userCosLatRad,
    double userSinLatRad,
    double stCosLatRad,
    double stSinLatRad,
    double dCosLonRad,
    double dSinLonRad,
  ) {
    var result = atan2(
      stCosLatRad * dSinLonRad,
      userCosLatRad * stSinLatRad - userSinLatRad * stCosLatRad * dCosLonRad,
    );
    if (result < 0) result += 2 * pi;
    return result / _degreesToRadians;
  }

  // 勾股定理
  // Equirectangular 前置计算
  static double pythagorean(
    // 高纬度下经度方向的距离畸变修正的参数
    // double userCosLatRad,
    // double stCosLatRad,
    double dLatRad,
    double dLonRad,
  ) {
    if (dLonRad > pi) dLonRad -= 2 * pi;
    if (dLonRad <= -pi) dLonRad += 2 * pi;
    // 高纬度下经度方向的距离畸变修正
    // 需要时再开放
    // dLonRad *= (stCosLatRad + userCosLatRad) * 0.5;

    // 返回弧度平方和
    return dLatRad * dLatRad + dLonRad * dLonRad;
  }

  /// 等距长方投影近似距离（米）
  static double equirectangular(double score) {
    return sqrt(score) * _earthRadius;
  }

  // static double degua(...)

  /// 大圆距离（米）
  static double haversine(double score) {
    return 2 * asin(score > 4.0 ? 1.0 : sqrt(score) * 0.5) * _earthRadius;
  }

  static Direction direction(double degrees, {double? speed}) {
    // 阈值定义
    // 低于此速度认为方向不可信
    if (speed != null && sampling(speed) == SamplingMode.staying) {
      return Direction.staying;
    }

    if (degrees >= 337.5 || degrees < 22.5) return Direction.n; // 北
    if (degrees >= 22.5 && degrees < 67.5) return Direction.ne; // 东北
    if (degrees >= 67.5 && degrees < 112.5) return Direction.e; // 东
    if (degrees >= 112.5 && degrees < 157.5) return Direction.se; // 东南
    if (degrees >= 157.5 && degrees < 202.5) return Direction.s; // 南
    if (degrees >= 202.5 && degrees < 247.5) return Direction.sw; // 西南
    if (degrees >= 247.5 && degrees < 292.5) return Direction.w; // 西
    return Direction.nw; // 西北 (292.5 - 337.5);
  }

  /// 根据速度判断采样模式
  static SamplingMode sampling(double speed) {
    if (speed >= SamplingMode.transit.speed) return SamplingMode.transit;
    if (speed >= SamplingMode.cycling.speed) return SamplingMode.cycling;
    if (speed >= SamplingMode.walking.speed) return SamplingMode.walking;
    return SamplingMode.staying;
  }
}

class StationResult {
  final int index;
  final int gcd;
  final String name;
  final double distance;
  final double bearing;

  StationResult({
    required this.index,
    required this.gcd,
    required this.name,
    required this.distance,
    required this.bearing,
  });

  @override
  String toString() {
    return '{index: $index, gcd: $gcd, name: $name, distance: $distance}';
  }

  String get distanceInUnit => distance < 1000.0
      ? '${distance.toStringAsFixed(1)} m'
      : '${(distance / 1000.0).toStringAsFixed(2)} km';
  Direction get bearingIndex => Common.direction(bearing);

  // 序列化
  List<dynamic> toTransferable() => [index, gcd, name, distance, bearing];

  // 反序列化
  // 添加显式强制转换
  factory StationResult.fromTransferable(List<dynamic> data) => StationResult(
        index: data[0] as int,
        gcd: data[1] as int,
        name: data[2] as String,
        distance: (data[3] as num).toDouble(),
        bearing: (data[4] as num).toDouble(),
      );
}

class PositionResult {
  final double latitude, longitude, speed, accuracy, heading;
  final DateTime timestamp;
  const PositionResult({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.accuracy,
    required this.heading,
    required this.timestamp,
  });

  @override
  String toString() {
    return '{latitude: $latitude, longitude: $longitude, speed: $speedString, accuracy: $accuracyString, heading: $headingIndex, datetime: $timestampString}';
  }

  String get speedString => speed < SamplingMode.cycling.speed
      ? '${speed.toStringAsFixed(1)} m/s'
      : '${(speed * 3.6).toStringAsFixed(2)} km/h';
  String get accuracyString => '${accuracy.toStringAsFixed(1)} m';
  Direction get headingIndex => Common.direction(heading, speed: speed);
  String get timestampString =>
      "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
  int get elapsed => DateTime.now().difference(timestamp).inMilliseconds;
  SamplingMode get samplingMode => Common.sampling(speed);

  // 序列化
  List<dynamic> toTransferable() => [
        latitude,
        longitude,
        speed,
        accuracy,
        heading,
        timestamp.millisecondsSinceEpoch,
      ];

  // 反序列化
  // 添加显式强制转换
  factory PositionResult.fromTransferable(List<dynamic> data) => PositionResult(
        latitude: (data[0] as num).toDouble(),
        longitude: (data[1] as num).toDouble(),
        speed: (data[2] as num).toDouble(),
        accuracy: (data[3] as num).toDouble(),
        heading: (data[4] as num).toDouble(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(data[5] as int),
      );
}

enum RunningStatus {
  stopped,
  starting,
  running,
}

enum SamplingMode {
  staying(speed: 0, filter: 4), // 静止
  walking(speed: 1, filter: 4), // 步行 >1 m/s
  cycling(speed: 4, filter: 4), // 骑自行车 >1 m/s
  transit(speed: 8, filter: 16); // 乘车 >8 m/s（~30 km/h）

  final double speed;
  final int filter;

  const SamplingMode({
    required this.speed,
    required this.filter,
  });

  @override
  String toString() {
    return '{speed: $speed, filter: $filter}';
  }
}

enum Direction {
  staying(-1),
  n(0), // 北
  ne(1), // 东北
  e(2), // 东
  se(3), // 东南
  s(4), // 南
  sw(5), // 西南
  w(6), // 西
  nw(7); // 西北

  final int v;

  const Direction(this.v);

  @override
  String toString() {
    return '{heading: $v}';
  }
}

// ── 设置项枚举 ────────────────────────────────────────────────────

enum LocationInterval {
  s1(
    seconds: 1,
    milliseconds: 1024,
  ),
  s3(
    seconds: 3,
    milliseconds: 3072,
  ),
  s5(
    seconds: 5,
    milliseconds: 5120,
  );

  final int seconds;
  final int milliseconds;

  const LocationInterval({
    required this.seconds,
    required this.milliseconds,
  });
}

// enum NotificationMode {
//   location,
//   station,
// }

// StationCount 的四个预设
// friend: 传入 engine 的基础数量
// radar: 第一段扩展（+4）
// natsume: 第二段扩展（+2）
enum StationCount {
  game(
    friend: 12,
    event: 2,
    radar: 4,
    natsume: 2,
  ),
  max(
    friend: 20,
    event: 0,
    radar: 0,
    natsume: 0,
  );

  final int friend;
  final int event;
  final int radar;
  final int natsume;

  const StationCount({
    required this.friend,
    required this.event,
    required this.radar,
    required this.natsume,
  });

  // 传入 engine 的实际 count
  int get count => friend + (Common.event() ? event : 0) + radar + natsume;

  StationCountPart part(int index) {
    if (index < friend) {
      return StationCountPart.friend;
    } else {
      if (Common.event()) {
        if (index < friend + event) return StationCountPart.event;
        if (index < friend + event + radar) return StationCountPart.radar;
        return StationCountPart.natsume;
      } else {
        if (index < friend + radar) return StationCountPart.radar;
        return StationCountPart.natsume;
      }
    }
  }

  // 显示标签，例如 "12"、"12 + 4"、"12 + 4 + 2"
  String get label {
    return '$friend${(event > 0 && Common.event() ? ' + $event' : '')}'
        '${(radar > 0 ? ' + $radar' : '')}${(natsume > 0 ? ' + $natsume' : '')}';
  }
}

enum StationCountPart {
  friend,
  event,
  radar,
  natsume,
}
