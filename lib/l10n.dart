import 'package:flutter/material.dart';

import 'common.dart';

/// Supported locales for this app.
/// Falls back to English for anything not listed here.
class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('en'));
  }

  static const delegate = _AppLocalizationsDelegate();

  static const supportedLocales = [
    Locale('en'),
    Locale('ja'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ];

  bool get _isEn => locale.languageCode == 'en';
  bool get _isJa => locale.languageCode == 'ja';
  bool get _isZhHans =>
      locale.languageCode == 'zh' &&
      (locale.scriptCode == 'Hans' || locale.countryCode == 'CN');

  // 8 方向标签字典
  static const Map<String, List<String>> _directionLabels = {
    'ja': ['北', '北東', '東', '南東', '南', '南西', '西', '北西'],
    'zhHans': ['北', '东北', '东', '东南', '南', '西南', '西', '西北'],
    'en': ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'],
  };

  // ── App ─────────────────────────────────────────────────────────
  String get appTitle {
    if (_isJa) return '最寄り駅通知';
    if (_isZhHans) return '附近车站通知';
    return 'Nearest Station Notification';
  }

  // ── HomePage ─────────────────────────────────────────────────────

  String get currentStatus {
    if (_isJa) return '現在状態';
    if (_isZhHans) return '当前状态';
    return 'Current Status';
  }

  String get notStarted {
    if (_isJa) return '位置情報取得停止中...';
    if (_isZhHans) return '定位停止中...';
    return 'Location update stopped...';
  }

  String get waitingForLocation {
    if (_isJa) return '位置情報取得中...';
    if (_isZhHans) return '定位更新中...';
    return 'Location updating...';
  }

  String get latitude {
    if (_isJa) return '緯度';
    if (_isZhHans) return '纬度';
    return 'Lat';
  }

  String get longitude {
    if (_isJa) return '経度';
    if (_isZhHans) return '经度';
    return 'Lon';
  }

  String get speed {
    if (_isJa || _isZhHans) return '速度';
    return 'Speed';
  }

  String direction(Direction direction) {
    if (direction == Direction.staying) return '--';

    if (_isJa) return _directionLabels['ja']![direction.v];
    if (_isZhHans) return _directionLabels['zhHans']![direction.v];
    return _directionLabels['en']![direction.v];
  }

  String get accuracy {
    if (_isJa || _isZhHans) return '精度';
    return 'Accuracy';
  }

  String get heading {
    if (_isJa || _isZhHans) return '方向';
    return 'Heading';
  }

  String get timestamp {
    if (_isJa) return '取得時刻';
    if (_isZhHans) return '更新时刻';
    return 'Updated at';
  }

  String get nearestStations {
    if (_isJa) return '最寄り駅一覧';
    if (_isZhHans) return '附近车站列表';
    return 'Nearby Stations';
  }

  // ── Info Card ───────────────────────────────────────────────────
  String get infoTitle {
    if (_isJa) return '駅情報・ライセンス';
    if (_isZhHans) return '车站信息和许可证';
    return 'Station Infomation and License';
  }

  String get infoNoStationsLoaded {
    if (_isJa) {
      return '0 駅を読み込みました。\n'
          'クリックしてライセンスを表示。';
    } else if (_isZhHans) {
      return '已读取 0 个车站。\n'
          '点击以显示许可证。';
    } else {
      return 'No stations loaded.\n'
          'Click to view license details.';
    }
  }

  String infoHasStationsLoaded(int count, int date, int size) {
    final ts = date > 0 ? '$date' : '--';
    final kb = size ~/ 1024;

    if (_isJa) {
      return '$count 駅を読み込みました。\n'
          'バージョン: $ts\n'
          'サイズ: $kb KB\n'
          'クリックして駅情報詳細・ライセンスを表示。';
      // '駅情報は 駅データ.jp に基づきます。\n'
      // 'ソースコードは MIT License で公開。\n'
      // '駅情報は元プロバイダの利用規約に準拠します。';
    } else if (_isZhHans) {
      return '已读取 $count 个车站。\n'
          '版本: $ts\n'
          '大小: $kb KB\n'
          '点击以显示车站信息详情和许可证。';
      // '车站信息基于 ekidata.jp。\n'
      // '代码基于 MIT License 开源。\n'
      // '车站信息衍生数据遵循其原始使用条款。';
    } else {
      return '$count station${count == 1 ? '' : 's'} loaded.\n'
          'Version: $ts\n'
          'Size: $kb KB\n'
          'Click to view station infomation and license details.';
      // 'Station infomation based on ekidata.jp.\n'
      // 'Code licensed under the MIT License.\n'
      // 'Station infomation binary assets comply with the original provider agreement.';
    }
  }

  // ── SnackBar ───────────────────────────────────────────────
  String errorMsg(String message) {
    if (_isJa) return '読み込み失敗: $message';
    if (_isZhHans) return '读取失败: $message';
    return 'Failed: $message';
  }

  // ── SamplingFilter ─────────────────────────────────────────────────

  String get stayingMode {
    if (_isJa) return '静止 🧍';
    if (_isZhHans) return '停留 🧍';
    return 'Staying 🧍';
  }

  String get walkingMode {
    if (_isJa) return '歩く 🚶';
    if (_isZhHans) return '步行 🚶';
    return 'Walking 🚶';
  }

  String get cyclingMode {
    if (_isJa) return '自転車 🚲';
    if (_isZhHans) return '骑行 🚲';
    return 'Cycling 🚲';
  }

  String get transitMode {
    if (_isJa) return '乗り物移動 🚃';
    if (_isZhHans) return '乘用交通工具 🚃';
    return 'Transit 🚃';
  }

  // ── Notification ──────────────────────────────────────────────────
  String get flnChannelName => appTitle;

  String get flnChannelDescription {
    if (_isJa) return '最寄り駅変更通知';
    if (_isZhHans) return '最近车站变动通知';
    return 'Nearest station update alerts';
  }

  String flnNotificationTitle(String name) {
    if (_isJa) return '🚉 最寄り駅: $name';
    if (_isZhHans) return '🚉 最近车站: $name';
    return '🚉 Nearest: $name';
  }

  String? flnNotificationGcd(int gcd) {
    return 'ID: $gcd';
  }

  String? flnNotificationFull(int gcd, String distanceInUnit) {
    if (_isJa) return '${flnNotificationGcd(gcd)}\n距離: $distanceInUnit';
    if (_isZhHans) return '${flnNotificationGcd(gcd)}\n距离: $distanceInUnit';
    return '${flnNotificationGcd(gcd)}\nDistance: $distanceInUnit';
  }

  // FGT 通知标题
  String get fgtChannelName => fgtNotificationTitle; // 定义别名区分使用位置
  String get fgtNotificationTitle {
    if (_isJa) return 'アプリ常駐通知';
    if (_isZhHans) return '常驻服务通知';
    return 'Persistent Service Notification';
  }

  // FGT 通知正文
  String get fgtChannelDescription => fgtNotificationBody; // 定义别名区分使用位置
  String get fgtNotificationBody {
    if (_isJa) return '長押しでこの常駐通知の非表示を推奨します';
    if (_isZhHans) return '建议长按关闭常驻服务通知';
    return 'Recommanded to hide this notification by long press';
  }

  // ── Settings Dialog ───────────────────────────────────────────────────────────

  String get settingsDialogTitle {
    if (_isJa) return '設定';
    if (_isZhHans) return '设置';
    return 'Settings';
  }

  String get settingsStationCount {
    if (_isJa) return '検出駅数';
    if (_isZhHans) return '定位车站数';
    return 'Station Count';
  }

  String get settingsNotificationMode {
    if (_isJa) return '通知モード';
    if (_isZhHans) return '通知模式';
    return 'Notification Mode';
  }

  String get settingsNotificationModeLocation {
    if (_isJa) return '位置情報取得ごと';
    if (_isZhHans) return '定位更新时';
    return 'On location update';
  }

  String get settingsNotificationModeStation {
    if (_isJa) return '最寄り駅変更時';
    if (_isZhHans) return '车站变动时';
    return 'On station change';
  }

  String get settingsLocationInterval {
    if (_isJa) return '位置情報取得間隔';
    if (_isZhHans) return '定位更新间隔';
    return 'Location Update Interval';
  }

  String settingsLocationIntervalLabel(int seconds) {
    if (_isJa || _isZhHans) return '$seconds 秒';
    return '$seconds s';
  }

  String get settingsSave {
    if (_isJa || _isZhHans) return '保存';
    return 'Save';
  }

  String get settingsCancel {
    if (_isJa) return 'キャンセル';
    if (_isZhHans) return '取消';
    return 'Cancel';
  }

  // ── License Dialog ───────────────────────────────────────────────────────────

  String get licensesDialogTitle => infoTitle;

  String licenseCount(int count) {
    if (_isJa) return '$count 件ライセンス';
    if (_isZhHans) return '$count 份许可';
    return '$count license${count == 1 ? '' : 's'}';
  }
}

// ── Delegate ──────────────────────────────────────────────────────────────────

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    final AppLocalizations loc = AppLocalizations(locale);
    return loc._isEn || loc._isJa || loc._isZhHans;
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final AppLocalizations loc = AppLocalizations(locale);
    if (!isSupported(locale)) return AppLocalizations(const Locale('en'));
    return loc;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
