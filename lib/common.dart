import 'dart:math';

class Common {
  // ── 动态包名常驻内存（由 main 在冷启动时注入） ───────────────────────
  static late final String appName;

  // 駅情報
  static const binFileName = 'station_data_xyz.bin';
  static const stationSchemaVersion = 'v2';

  // イベント情報
  static const eventFileName = 'event_data.ndjson';
  static const eventSchemaVersion = 2;
  static const eventFields = <String>['start_epoch', 'end_epoch'];

  // 履歴
  static const historyDirName = 'history';
  static const historySchemaVersion = 1;
  static const historyFields = <String>['gcd', 'epoch', 'lat_e6', 'lon_e6'];
  static const historyMergeWindow = Duration(minutes: 5);

  // 车站历史汇总
  static const summaryFileName = 'summary.ndjson';
  static const summarySchemaVersion = 1;
  static const summaryFields = <String>[
    'gcd',
    'first_epoch',
    'first_lat_e6',
    'first_lon_e6',
    'last_epoch',
    'last_lat_e6',
    'last_lon_e6',
  ];

  static const sumsFileName = 'SHA256SUMS';
  static const manifestFileName = 'MANIFEST';

  // ── 导入 zip 限制 ──────────────────────────────────────────────
  static const maxZipSize = 20 * 1024 * 1024;
  static const maxZipTotalUnzipSize = 50 * 1024 * 1024;
  static const maxZipEntrySize = 10 * 1024 * 1024;
  static const maxZipEntries = 100;

  // 示例数据判定阈值（小于该车站数视为示例数据）
  static const sampleThreshold = 50;

  // 旧格式站名中的駅 ID 解析（v2 已分离为独立 gcd 区）
  static final namePattern = RegExp(r'^(\d{1,7}),(.*)$');

  // // 駅データ.jp へのリンク
  // static final uriEkidata = Uri.parse('https://ekidata.jp/');

  // 駅情報・イベント情報データダウンロードへのリンク
  static final uriInformation = Uri.parse('https://w57.name/p2.html');

  static const flnChannelId = 'notification_fln_channel';
  static const flnNotificationId = 1058;
  static const flnNotificationIcon = 'ic_notification';

  static const bgtChannelId =
      'name.w57.nearest_station_notification/background_task';

  // // 距离过远检测
  // // 单位为经纬度差值平方 / 弦长平方
  // // 约等于 Equirectangular 和 Haversine 计算距离 99.55 km
  // // 二进制对应 2 ^ -12
  // static const farScore = 2.44140625e-4;

  // 最少搜索站数
  static const leastCount = 5;
  static const leastCountInactive = 1;

  // GPS 漂移（距离过近）检测
  // 单位为经纬度差值
  // 二进制对应 2 ^ -15
  static const nearCoord = 3.0517578125e-5;

  // int(UInt32) 最大值
  static const intMaxValue = 4294967295;

  // ── 日期（int yyyyMMdd / yyyyMM，见 architecture.md 的 Date Representation）
  /// 本地日期键：`yyyyMMdd`
  static int dateOf(DateTime time) =>
      time.year * 10000 + time.month * 100 + time.day;

  /// epoch 毫秒 → 本地日期键
  static int dateOfEpoch(int epoch) =>
      dateOf(DateTime.fromMillisecondsSinceEpoch(epoch));

  /// 日期键 → 月份键：`yyyyMM`
  static int monthDateOf(int date) => date ~/ 100;

  /// 当前本地日期键：`yyyyMMdd`
  static int today() => dateOf(DateTime.now());

  /// 当前本地月份键：`yyyyMM`
  static int currentMonth() => monthDateOf(today());

  /// 月份键加减
  /// 处理跨年：`202601` + (-1) → `202512`
  static int addMonths(int month, int delta) {
    final index = (month ~/ 100) * 12 + (month % 100 - 1) + delta;
    return (index ~/ 12) * 100 + index % 12 + 1;
  }

  /// 年
  static int yearOf(int date) => date ~/ 10000;

  /// 月（1–12）
  static int monthOf(int date) => date ~/ 100 % 100;

  /// 日（1–31）
  static int dayOf(int date) => date % 100;

  /// 合法日期键
  /// 0 表示未设置
  static bool isValidDate(int date) {
    if (date == 0) return true;
    if (date < 10000101 || date > 99991231) return false;

    final year = yearOf(date);
    final month = monthOf(date);
    final day = dayOf(date);
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;

    final time = DateTime(year, month, day);
    return time.year == year && time.month == month && time.day == day;
  }

  /// 合法月份键
  /// 0 表示未设置
  static bool isValidMonth(int month) {
    if (month == 0) return true;
    if (month < 100001 || month > 999912) return false;

    final monthOfYear = month % 100;
    return monthOfYear >= 1 && monthOfYear <= 12;
  }

  static String dateString(int year, int month, int day) {
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  static String timeString(int hour, int minute, int second) {
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}:'
        '${second.toString().padLeft(2, '0')}';
  }

  // 地球半径常数（米）
  static const _earthRadius = 6371000.0;
  // 角度转弧度的常数
  static const _degreesToRadians = pi / 180.0;

  // // 计算 8 方向时代表静止 （不在 0 ~ 7 范围）
  // static const int headingStaying = -1;

  // 日本全境及近海轮廓（不含离岛）
  // Generated from Natural Earth 1:50m Land, version 4.0.0.
  // Included: Hokkaido, Honshu, Shikoku, Kyushu, and Okinawa main island.
  // Outward buffer: 50,000 m. Simplification tolerance: 8,000 m.
  // Coordinates: WGS84 (latitude, longitude).
  static const _insidePolygons = [
    // Hokkaido, Honshu, Shikoku, and Kyushu
    [
      (latitude: 32.321957, longitude: 129.325307),
      (latitude: 33.444481, longitude: 129.087072),
      (latitude: 33.690040, longitude: 129.267827),
      (latitude: 34.022085, longitude: 129.992727),
      (latitude: 34.284045, longitude: 130.349617),
      (latitude: 34.711941, longitude: 130.620899),
      (latitude: 35.088295, longitude: 131.525349),
      (latitude: 35.805824, longitude: 132.410045),
      (latitude: 35.995972, longitude: 133.023892),
      (latitude: 35.945488, longitude: 133.827031),
      (latitude: 36.190920, longitude: 135.079037),
      (latitude: 36.137554, longitude: 135.483961),
      (latitude: 36.917314, longitude: 136.169478),
      (latitude: 37.329142, longitude: 136.179822),
      (latitude: 37.726614, longitude: 136.478807),
      (latitude: 37.966379, longitude: 137.416268),
      (latitude: 37.842190, longitude: 137.721472),
      (latitude: 37.564619, longitude: 137.896930),
      (latitude: 38.181108, longitude: 138.507602),
      (latitude: 38.364809, longitude: 138.886387),
      (latitude: 39.520269, longitude: 139.458398),
      (latitude: 39.955682, longitude: 139.158537),
      (latitude: 40.309914, longitude: 139.391557),
      (latitude: 40.781459, longitude: 139.382984),
      (latitude: 41.099659, longitude: 139.690238),
      (latitude: 41.435779, longitude: 139.421937),
      (latitude: 41.872437, longitude: 139.469416),
      (latitude: 42.231890, longitude: 139.233493),
      (latitude: 42.657584, longitude: 139.260498),
      (latitude: 42.943096, longitude: 139.429550),
      (latitude: 43.114668, longitude: 139.786319),
      (latitude: 43.598017, longitude: 139.927498),
      (latitude: 43.772439, longitude: 140.326764),
      (latitude: 43.735128, longitude: 140.794234),
      (latitude: 44.557493, longitude: 141.139115),
      (latitude: 45.363970, longitude: 140.977385),
      (latitude: 45.768857, longitude: 141.302054),
      (latitude: 45.954597, longitude: 141.850232),
      (latitude: 45.904825, longitude: 142.244167),
      (latitude: 44.744367, longitude: 143.689211),
      (latitude: 44.423294, longitude: 144.584902),
      (latitude: 44.771750, longitude: 145.207131),
      (latitude: 44.752518, longitude: 145.573989),
      (latitude: 44.589208, longitude: 145.880359),
      (latitude: 44.282551, longitude: 145.994479),
      (latitude: 43.843949, longitude: 145.783307),
      (latitude: 43.715791, longitude: 146.253870),
      (latitude: 43.414636, longitude: 146.448003),
      (latitude: 43.098267, longitude: 146.303045),
      (latitude: 42.820273, longitude: 145.879780),
      (latitude: 42.582449, longitude: 145.140967),
      (latitude: 42.510973, longitude: 144.318720),
      (latitude: 42.201755, longitude: 143.959972),
      (latitude: 41.749172, longitude: 143.739097),
      (latitude: 41.554786, longitude: 143.316916),
      (latitude: 41.607212, longitude: 142.879112),
      (latitude: 42.105434, longitude: 141.602964),
      (latitude: 41.496336, longitude: 142.040953),
      (latitude: 40.825963, longitude: 142.011378),
      (latitude: 40.082506, longitude: 142.498027),
      (latitude: 39.396914, longitude: 142.555880),
      (latitude: 38.987158, longitude: 142.455715),
      (latitude: 38.610762, longitude: 142.096251),
      (latitude: 38.179498, longitude: 141.962579),
      (latitude: 37.944851, longitude: 141.508884),
      (latitude: 37.009511, longitude: 141.548303),
      (latitude: 36.225458, longitude: 141.141480),
      (latitude: 35.863814, longitude: 141.400076),
      (latitude: 35.602974, longitude: 141.405619),
      (latitude: 35.275256, longitude: 140.965767),
      (latitude: 34.830009, longitude: 140.697580),
      (latitude: 34.478992, longitude: 140.116312),
      (latitude: 34.554040, longitude: 139.517615),
      (latitude: 34.185400, longitude: 138.996715),
      (latitude: 34.182501, longitude: 137.370184),
      (latitude: 33.960926, longitude: 137.174738),
      (latitude: 33.825103, longitude: 136.709132),
      (latitude: 33.251264, longitude: 136.305588),
      (latitude: 33.068983, longitude: 135.896025),
      (latitude: 33.124598, longitude: 135.286940),
      (latitude: 33.395516, longitude: 134.935393),
      (latitude: 32.822632, longitude: 134.360684),
      (latitude: 32.813246, longitude: 134.036753),
      (latitude: 33.012090, longitude: 133.698109),
      (latitude: 32.582701, longitude: 133.412602),
      (latitude: 32.340610, longitude: 133.079278),
      (latitude: 32.312960, longitude: 132.603828),
      (latitude: 32.440096, longitude: 132.272108),
      (latitude: 31.155360, longitude: 131.773047),
      (latitude: 30.582055, longitude: 130.827401),
      (latitude: 30.625830, longitude: 130.422024),
      (latitude: 31.047006, longitude: 129.760406),
      (latitude: 31.331419, longitude: 129.630035),
      (latitude: 32.128539, longitude: 129.670107),
    ],
    // Okinawa main island
    [
      (latitude: 26.903096, longitude: 127.465878),
      (latitude: 27.331996, longitude: 128.256118),
      (latitude: 27.199354, longitude: 128.612800),
      (latitude: 26.899169, longitude: 128.823250),
      (latitude: 26.397831, longitude: 128.667739),
      (latitude: 25.661478, longitude: 127.849546),
      (latitude: 25.709469, longitude: 127.393219),
      (latitude: 25.980878, longitude: 127.171813),
      (latitude: 26.519943, longitude: 127.240429),
    ],
  ];

  static bool inside(double latitude, double longitude) {
    return _insidePolygons.any((polygon) {
      bool inside = false;
      final n = polygon.length;
      for (int i = 0, j = n - 1; i < n; j = i++) {
        final latitudeI = polygon[i].latitude;
        final longitudeI = polygon[i].longitude;
        final latitudeJ = polygon[j].latitude;
        final longitudeJ = polygon[j].longitude;

        final intersect =
            ((latitude < latitudeI) != (latitude < latitudeJ)) &&
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

  static Direction direction(double? degrees, {double? speed}) {
    // 阈值定义
    // 低于此速度认为方向不可信
    if (degrees == null ||
        (speed != null && sampling(speed) == SamplingMode.staying)) {
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
  final int node;
  final int? gcd; // SearchEngine 原产出无此資訊，由 Coordinator 補全
  final String? name; // SearchEngine 原产出无此資訊，由 Coordinator 補全
  final double? distance;
  final double? bearing;

  StationResult({
    required this.node,
    this.gcd,
    this.name,
    this.distance,
    this.bearing,
  });

  String get distanceInUnit {
    final d = distance == null || distance! < 0.0 ? 0.0 : distance!;

    return d < 1000.0
        ? '${d.toStringAsFixed(1)} m'
        : d < 1000000.0
        ? '${(d / 1000.0).toStringAsFixed(2)} km'
        : '${(d / 1000000.0).toStringAsFixed(2)} Mm';
  }

  Direction get bearingIndex => Common.direction(bearing);

  // // 序列化（暂存，未来可能用于 Isolate 间通信，当前无调用）
  // List<dynamic> toTransferable() => [node, gcd, name, distance, bearing];

  // // 反序列化
  // // 添加显式强制转换
  // factory StationResult.fromTransferable(List<dynamic> data) => StationResult(
  //       node: data[0] as int,
  //       gcd: data[1] as int?,
  //       name: data[2] as String?,
  //       distance: (data[3] as num).toDouble(),
  //       bearing: (data[4] as num).toDouble(),
  //     );
}

class PositionResult {
  final double latitude, longitude, speed, accuracy, heading;
  final int epoch;

  const PositionResult({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.accuracy,
    required this.heading,
    required this.epoch,
  });

  @override
  String toString() {
    return '{'
        'latitude: $latitude, longitude: $longitude, '
        'speed: $speedString, accuracy: $accuracyString, '
        'heading: $headingIndex, datetime: $timeString'
        '}';
  }

  String get speedString => speed < SamplingMode.cycling.speed
      ? '${speed.toStringAsFixed(1)} m/s'
      : '${(speed * 3.6).toStringAsFixed(2)} km/h';
  String get accuracyString => '${accuracy.toStringAsFixed(1)} m';
  Direction get headingIndex => Common.direction(heading, speed: speed);
  String get timeString {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(epoch);
    return Common.timeString(
      timestamp.hour,
      timestamp.minute,
      timestamp.second,
    );
  }

  // int get elapsed => DateTime.now().difference(timestamp).inMilliseconds;
  SamplingMode get samplingMode => Common.sampling(speed);

  // // 序列化（暂存，未来可能用于 Isolate 间通信，当前无调用）
  // List<dynamic> toTransferable() => [
  //       latitude,
  //       longitude,
  //       speed,
  //       accuracy,
  //       heading,
  //       timestamp.millisecondsSinceEpoch,
  //     ];

  // // 反序列化
  // // 添加显式强制转换
  // factory PositionResult.fromTransferable(List<dynamic> data) =>
  //     PositionResult(
  //       latitude: (data[0] as num).toDouble(),
  //       longitude: (data[1] as num).toDouble(),
  //       speed: (data[2] as num).toDouble(),
  //       accuracy: (data[3] as num).toDouble(),
  //       heading: (data[4] as num).toDouble(),
  //       timestamp: DateTime.fromMillisecondsSinceEpoch(data[5] as int),
  //     );
}

class HistoryRecord {
  final int gcd;
  final int epoch;
  final int latE6;
  final int lonE6;

  const HistoryRecord({
    required this.gcd,
    required this.epoch,
    required this.latE6,
    required this.lonE6,
  });

  double get latitude => latE6 / 1e6;
  double get longitude => lonE6 / 1e6;
  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(epoch);
  String get key => '$gcd|$epoch|$latE6|$lonE6';

  List<Object?> toRow() => [gcd, epoch, latE6, lonE6];

  static HistoryRecord? tryParse(Object? value) {
    if (value is! List || value.length != 4) return null;

    final gcd = value[0];
    final epoch = value[1];
    final latE6 = value[2];
    final lonE6 = value[3];

    if (gcd is! int) return null;
    if (epoch is! int || latE6 is! int || lonE6 is! int) return null;

    return HistoryRecord(gcd: gcd, epoch: epoch, latE6: latE6, lonE6: lonE6);
  }

  /// 记录键去重后按 epoch / gcd / key 升序排序
  /// 磁盘读取与页面合并共用同一实现，避免两处排序不一致
  static List<HistoryRecord> mergeDedup(Iterable<HistoryRecord> input) {
    final unique = <String, HistoryRecord>{};
    for (final record in input) {
      unique.putIfAbsent(record.key, () => record);
    }

    final records = unique.values.toList();
    records.sort((a, b) {
      final byEpoch = a.epoch.compareTo(b.epoch);
      if (byEpoch != 0) return byEpoch;

      final byStation = a.gcd.compareTo(b.gcd);
      if (byStation != 0) return byStation;

      return a.key.compareTo(b.key);
    });
    return records;
  }
}

class HistorySummary {
  final HistoryRecord first;
  final HistoryRecord last;

  const HistorySummary({required this.first, required this.last});

  int get gcd => first.gcd;

  factory HistorySummary.fromRecord(HistoryRecord record) =>
      HistorySummary(first: record, last: record);

  /// 時間順序固定為 `(epoch, latE6, lonE6)` 升序
  static int compare(HistoryRecord a, HistoryRecord b) {
    final byEpoch = a.epoch.compareTo(b.epoch);
    if (byEpoch != 0) return byEpoch;

    final byLat = a.latE6.compareTo(b.latE6);
    if (byLat != 0) return byLat;

    return a.lonE6.compareTo(b.lonE6);
  }

  HistorySummary merge(HistoryRecord record) {
    assert(record.gcd == gcd);
    return HistorySummary(
      first: compare(record, first) < 0 ? record : first,
      last: compare(record, last) > 0 ? record : last,
    );
  }

  HistorySummary mergeSummary(HistorySummary other) {
    assert(other.gcd == gcd);
    return HistorySummary(
      first: compare(other.first, first) < 0 ? other.first : first,
      last: compare(other.last, last) > 0 ? other.last : last,
    );
  }

  List<Object?> toRow() => [
    gcd,
    first.epoch,
    first.latE6,
    first.lonE6,
    last.epoch,
    last.latE6,
    last.lonE6,
  ];

  static HistorySummary? tryParse(Object? value) {
    if (value is! List || value.length != 7) return null;

    final gcd = value[0];
    final firstEpoch = value[1];
    final firstLatE6 = value[2];
    final firstLonE6 = value[3];
    final lastEpoch = value[4];
    final lastLatE6 = value[5];
    final lastLonE6 = value[6];

    if (gcd is! int ||
        firstEpoch is! int ||
        firstLatE6 is! int ||
        firstLonE6 is! int ||
        lastEpoch is! int ||
        lastLatE6 is! int ||
        lastLonE6 is! int) {
      return null;
    }

    final first = HistoryRecord(
      gcd: gcd,
      epoch: firstEpoch,
      latE6: firstLatE6,
      lonE6: firstLonE6,
    );
    final last = HistoryRecord(
      gcd: gcd,
      epoch: lastEpoch,
      latE6: lastLatE6,
      lonE6: lastLonE6,
    );
    if (compare(first, last) > 0) return null;

    return HistorySummary(first: first, last: last);
  }

  static Map<int, HistorySummary> mergeAll(Iterable<HistoryRecord> records) =>
      mergeInto(<int, HistorySummary>{}, records);

  static Map<int, HistorySummary> mergeInto(
    Map<int, HistorySummary> base,
    Iterable<HistoryRecord> records,
  ) {
    for (final record in records) {
      final existing = base[record.gcd];
      base[record.gcd] = existing == null
          ? HistorySummary.fromRecord(record)
          : existing.merge(record);
    }
    return base;
  }
}

enum RunningStatus { stopped, starting, running }

enum SamplingMode {
  staying(speed: 0.0), // 静止
  walking(speed: 1.0), // 步行 >= 1 m/s
  cycling(speed: 4.0), // 骑自行车 >= 4 m/s
  transit(speed: 8.0, filter: 16); // 乘车 >= 8 m/s（~ 30 km/h）

  final double speed;
  final int filter;

  const SamplingMode({required this.speed, this.filter = 4});

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
  s1(seconds: 1, milliseconds: 1024),
  s3(seconds: 3, milliseconds: 3072),
  s5(seconds: 5, milliseconds: 5120);

  final int seconds;
  final int milliseconds;

  const LocationInterval({required this.seconds, required this.milliseconds});
}

// enum NotificationMode {
//   location,
//   station,
// }

// StationCount 的四个预设
// friend: 传入 engine 的基础数量
// event: 事件期间追加的数量
// radar: 第一段扩展（+4）
// natsume: 第二段扩展（+2）
enum StationCount {
  game(friend: 12, event: 2, radar: 4, natsume: 2),
  max(friend: 20, event: 0, radar: 0, natsume: 0);

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

  /// 事件期间判定器（由 EventManager 初始化时注入；默认 false）
  static bool Function() eventPeriod = () => false;

  // 传入 engine 的实际 count
  int get count => friend + (eventPeriod() ? event : 0) + radar + natsume;

  StationCountPart part(int part) {
    if (part < friend) {
      return StationCountPart.friend;
    } else {
      if (eventPeriod()) {
        if (part < friend + event) return StationCountPart.event;
        if (part < friend + event + radar) return StationCountPart.radar;
        return StationCountPart.natsume;
      } else {
        if (part < friend + radar) return StationCountPart.radar;
        return StationCountPart.natsume;
      }
    }
  }

  // 显示标签，例如 "12"、"12 + 4"、"12 + 4 + 2"
  String get label {
    return '$friend${(event > 0 && eventPeriod() ? ' + $event' : '')}'
        '${(radar > 0 ? ' + $radar' : '')}${(natsume > 0 ? ' + $natsume' : '')}';
  }
}

enum StationCountPart { friend, event, radar, natsume }

enum HomeMenuAction { settings, history, info }
