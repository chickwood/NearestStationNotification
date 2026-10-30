import 'package:flutter/material.dart';

import 'common.dart';

/// Supported locales for this app.
/// Falls back to English for anything not listed here.
class L10n {
  final Locale locale;
  const L10n(this.locale);

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n) ?? const L10n(Locale('en'));
  }

  static const delegate = _L10nDelegate();

  static const supportedLocales = [
    Locale('en'),
    Locale('ja'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ];

  /// 严格 locale 解析：按优先顺序返回第一个受支持语言的规范 locale
  /// zh 仅接受 Hans 文字或 CN 地区（与 _isZhHans 一致），
  /// 不做语言码级宽松回退；无匹配时返回 en
  static Locale resolve(List<Locale>? locales) {
    for (final locale in locales ?? const <Locale>[]) {
      if (locale.languageCode == 'ja') return const Locale('ja');
      if (locale.languageCode == 'en') return const Locale('en');
      if (locale.languageCode == 'zh' &&
          (locale.scriptCode == 'Hans' || locale.countryCode == 'CN')) {
        return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
      }
    }
    return const Locale('en');
  }

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
  String get currentLocation {
    if (_isJa) return '現在位置';
    if (_isZhHans) return '当前定位';
    return 'Current Location';
  }

  String get currentLocationStatus {
    if (_isJa) return '$currentLocation・状態';
    if (_isZhHans) return '$currentLocation及状态';
    return '$currentLocation and Status';
  }

  String get notStarted {
    if (_isJa) return '位置情報取得停止中...';
    if (_isZhHans) return '定位停止中...';
    return 'Location update stopped...';
  }

  String get tapToStart {
    if (_isJa) return '右上の▶をクリックして開始';
    if (_isZhHans) return '点击右上角的▶开始定位';
    return 'Tap ▶ in the title bar to start';
  }

  String get waitingForLocation {
    if (_isJa) return '位置情報取得中...';
    if (_isZhHans) return '定位更新中...';
    return 'Location updating...';
  }

  String get waitingForLongtime {
    if (_isJa) return '長時間固まると一回▶をクリックして一旦停止';
    if (_isZhHans) return '长时间未能启动时再次点击▶可以暂时停止';
    return 'Tap ▶ to stop once while not start for a long time';
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

  String get nearbyStations {
    if (_isJa) return '最寄り駅一覧';
    if (_isZhHans) return '附近车站列表';
    return 'Nearby Stations';
  }

  String countStations(int count) {
    if (_isJa) return '$count 駅を読み込みました。';
    if (_isZhHans) return '已读取 $count 个车站。';
    return '${count > 0 ? '$count' : 'No'} station${count == 1 ? '' : 's'} loaded.';
  }

  String get sampleDataGuide {
    if (_isJa) return 'サンプル駅情報を使用中です。右上の情報ボタンをクリックして駅情報を確認・更新。';
    if (_isZhHans) return '当前正在使用示例车站信息。点击右上角的信息按钮查看和更新车站信息。';
    return 'Sample data in use. Tap the Info button on the top right to view and update station information.';
  }

  // ── Toast ──────────────────────────────────────────────────
  String errorMsg(String message) {
    if (_isJa) return '読み込み失敗: $message';
    if (_isZhHans) return '读取失败: $message';
    return 'Failed: $message';
  }

  // ── SamplingFilter ─────────────────────────────────────────────────
  // String get stayingMode {
  //   if (_isJa) return '静止 🧍';
  //   if (_isZhHans) return '停留 🧍';
  //   return 'Staying 🧍';
  // }

  // String get walkingMode {
  //   if (_isJa) return '歩く 🚶';
  //   if (_isZhHans) return '步行 🚶';
  //   return 'Walking 🚶';
  // }

  // String get cyclingMode {
  //   if (_isJa) return '自転車 🚲';
  //   if (_isZhHans) return '骑行 🚲';
  //   return 'Cycling 🚲';
  // }

  // String get transitMode {
  //   if (_isJa) return '乗り物移動 🚃';
  //   if (_isZhHans) return '乘用交通工具 🚃';
  //   return 'Transit 🚃';
  // }

  // ── Notification ──────────────────────────────────────────────────
  String get flnChannelName {
    if (_isJa) return '最寄り駅変更通知';
    if (_isZhHans) return '最近车站变动通知';
    return 'Nearest Station Change Notification';
  }

  String get flnChannelDescription {
    if (_isJa) return '最寄り駅の変更時に通知します';
    if (_isZhHans) return '最近车站发生变动时显示通知';
    return 'This notification is shown when the nearest station changes';
  }

  String flnNotificationTitle(String? name) {
    if (_isJa) return '🚉 最寄り駅: $name';
    if (_isZhHans) return '🚉 最近车站: $name';
    return '🚉 Nearest: $name';
  }

  String flnNotificationGcd(int? gcd) {
    return 'ID: $gcd';
  }

  // String flnNotificationFull(int? gcd, String distanceInUnit) {
  //   if (_isJa) return '${flnNotificationGcd(gcd)}\n距離: $distanceInUnit';
  //   if (_isZhHans) return '${flnNotificationGcd(gcd)}\n距离: $distanceInUnit';
  //   return '${flnNotificationGcd(gcd)}\nDistance: $distanceInUnit';
  // }

  // Geolocator 服务通知标题
  String get fgnChannelName => fgnNotificationTitle; // 定义别名区分使用位置
  String get fgnNotificationTitle {
    if (_isJa) return 'アプリ常駐通知';
    if (_isZhHans) return '常驻服务通知';
    return 'Persistent Service Notification';
  }

  // Geolocator 服务通知正文
  String get fgnNotificationBody {
    if (_isJa) return '長押しでこの常駐通知の非表示を推奨します';
    if (_isZhHans) return '建议长按关闭常驻服务通知';
    return 'Recommended to hide this notification by long press';
  }

  // ── Settings Page ─────────────────────────────────────────────────────────────
  String get settingsPageTitle => settingsDialogTitle;
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

  String get settingsHistory {
    if (_isJa) return '履歴';
    if (_isZhHans) return '历史记录';
    return 'History';
  }

  String get settingsHistoryEnabled {
    if (_isJa) return '最寄り駅の変更履歴を記録';
    if (_isZhHans) return '记录车站切换历史';
    return 'Record station change history';
  }

  String get settingsHistoryMergeRapid {
    if (_isJa) return '5分以内の再切替をまとめて表示';
    if (_isZhHans) return '将5分钟内反复切换的车站合并展示';
    return 'Merge repeat switches within 5 minutes';
  }

  String get historyTitle {
    if (_isJa) return '履歴';
    if (_isZhHans) return '历史记录';
    return 'History';
  }

  String get historyMonthEmpty {
    if (_isJa) return '今月の履歴はありません';
    if (_isZhHans) return '本月暂无历史记录';
    return 'No history this month';
  }

  String get historyDayEmpty {
    if (_isJa) return 'この日の履歴はありません';
    if (_isZhHans) return '当天暂无历史记录';
    return 'No history for this day';
  }

  String historyDayCount(int count) {
    if (_isJa) return '$count 件';
    if (_isZhHans) return '共 $count 条记录';
    return '$count records';
  }

  String get historyLoadFailed {
    if (_isJa) return '履歴の読み込みに失敗しました';
    if (_isZhHans) return '读取历史记录失败';
    return 'Failed to load history';
  }

  String get historyRefresh {
    if (_isJa) return '更新';
    if (_isZhHans) return '刷新';
    return 'Refresh';
  }

  String get historyJumpMonth {
    if (_isJa) return '月を選択';
    if (_isZhHans) return '选择月份';
    return 'Select month';
  }

  String get historyPrevMonth {
    if (_isJa) return '前月';
    if (_isZhHans) return '上一月';
    return 'Previous month';
  }

  String get historyNextMonth {
    if (_isJa) return '翌月';
    if (_isZhHans) return '下一月';
    return 'Next month';
  }

  String get historyTime {
    if (_isJa) return '時刻';
    if (_isZhHans) return '时间';
    return 'Time';
  }

  String get historyCoordinates {
    if (_isJa) return '座標';
    if (_isZhHans) return '坐标';
    return 'Coordinates';
  }

  String get historyExport {
    if (_isJa) return 'バックアップをエクスポート';
    if (_isZhHans) return '导出备份';
    return 'Export backup';
  }

  String get historyImport {
    if (_isJa) return 'バックアップをインポート';
    if (_isZhHans) return '导入备份';
    return 'Import backup';
  }

  String get historyExporting {
    if (_isJa) return 'エクスポート中...';
    if (_isZhHans) return '正在导出...';
    return 'Exporting...';
  }

  String get historyImporting {
    if (_isJa) return 'インポート中...';
    if (_isZhHans) return '正在导入...';
    return 'Importing...';
  }

  String get historyExportSucceeded {
    if (_isJa) return 'エクスポートしました';
    if (_isZhHans) return '导出完成';
    return 'Export complete';
  }

  String get historyImportSucceeded {
    if (_isJa) return 'インポートしました';
    if (_isZhHans) return '导入完成';
    return 'Import complete';
  }

  String get historyBackupFailed {
    if (_isJa) return 'バックアップ操作に失敗しました';
    if (_isZhHans) return '备份操作失败';
    return 'Backup operation failed';
  }

  String get historyImportConfirm {
    if (_isJa) {
      return '過去の月はバックアップの件数が多い場合のみ上書きされ、当月は統合されます。続行しますか？';
    }
    if (_isZhHans) {
      return '过往月份仅在备份条数更多时覆盖，当前月将合并；继续？';
    }
    return 'Past months are overwritten only when the backup has more records; the current month is merged. Continue?';
  }

  String historyStationId(int id) {
    return 'ID: $id';
  }

  String get settingsSave {
    if (_isJa || _isZhHans) return '保存';
    return 'Save';
  }

  String get settingsSaveSucceeded {
    if (_isJa) return '設定を保存しました。';
    if (_isZhHans) return '设置已保存。';
    return 'Settings saved.';
  }

  String get settingsSaveFailed {
    if (_isJa) return '設定の保存に失敗しました';
    if (_isZhHans) return '保存设置失败';
    return 'Failed to save settings';
  }

  String get dialogClose {
    if (_isJa) return '閉じる';
    if (_isZhHans) return '关闭';
    return 'Close';
  }

  // ── Info Page ──────────────────────────────────────────────────
  String get infoPageTitle => infoDialogTitle;
  String get infoDialogTitle {
    if (_isJa) return '情報';
    if (_isZhHans) return '信息';
    return 'Info';
  }

  String get infoTitle {
    if (_isJa) return 'ライセンス・駅情報';
    if (_isZhHans) return '许可证及车站信息';
    return 'Licenses and Station Information';
  }

  String infoStations(int count) => countStations(count); // 定义别名区分使用位置

  String infoVersion(int date, int pdate) {
    if (_isJa) {
      return 'バージョン: ${date > 0 ? '$date${pdate > 0 ? ' + パッチ: $pdate' : ''}' : ''}';
    }
    if (_isZhHans) {
      return '版本: ${date > 0 ? '$date${pdate > 0 ? ' + 修订: $pdate' : ''}' : ''}';
    }
    return 'Version: ${date > 0 ? '$date${pdate > 0 ? ' + Patch: $pdate' : ''}' : ''}';
  }

  String infoSize(int size) {
    if (_isJa) return 'サイズ: ${size ~/ 1024} KB';
    if (_isZhHans) return '大小: ${size ~/ 1024} KB';
    return 'Size: ${size ~/ 1024} KB';
  }

  String get infoLicense {
    if (_isJa) return 'ここをクリックして、ライセンス・駅情報詳細を表示。';
    if (_isZhHans) return '点击此处显示许可证及车站信息详情。';
    return 'Tap here to view licenses and station information details.';
  }

  String get infoUpdateTitle {
    if (_isJa || _isZhHans) return '更新';
    return 'Update';
  }

  String get infoUpdateNotice {
    if (_isJa) {
      return '駅情報・イベント情報データは定期的に更新してください。'
          '\nここをクリックして、ダウンロードサイトを開く。'
          '\n\nダウンロード後、インポートをクリックして、データファイルを選択して情報を更新。';
    }
    if (_isZhHans) {
      return '请定期更新车站信息与事件信息数据。'
          '\n点击此处打开下载网站。'
          '\n\n下载后，点击导入，选择数据文件更新信息。';
    }
    return 'Update station information and event information data periodically.'
        '\nTap here to open download website.'
        '\n\nAfter download, tap import, select data file to update information.';
  }

  String get infoImport {
    if (_isJa) return 'インポート';
    if (_isZhHans) return '导入';
    return 'Import';
  }

  String get infoImportedStationAndEvent {
    if (_isJa) return '駅情報・イベント情報をインポートしました。';
    if (_isZhHans) return '已导入车站及活动信息。';
    return 'Station and event information imported.';
  }

  String get infoImportedStation {
    if (_isJa) return '駅情報をインポートしました。';
    if (_isZhHans) return '已导入车站信息。';
    return 'Station information imported.';
  }

  String get infoImportedEvent {
    if (_isJa) return 'イベント情報をインポートしました。';
    if (_isZhHans) return '已导入活动信息。';
    return 'Event information imported.';
  }

  String get infoInvalidFile {
    if (_isJa) return '無効なファイルです';
    if (_isZhHans) return '无效的文件';
    return 'Invalid file';
  }

  // ── License Page ───────────────────────────────────────────────────────────
  String get licensesDialogTitle => infoTitle;
  String get licensesPageTitle => licensesDialogTitle;

  String licenseCount(int count) {
    if (_isJa) return '$count 件ライセンス';
    if (_isZhHans) return '$count 份许可';
    return '$count license${count == 1 ? '' : 's'}';
  }

  String licenseCountWithAdditionalNotice(int count) {
    if (_isJa) return '${licenseCount(count)} 及び 駅情報に関する説明';
    if (_isZhHans) return '${licenseCount(count)} 及 关于车站信息的说明';
    return '${licenseCount(count)} and Notice for Station Information';
  }

  String get licensePublish {
    if (_isJa) return 'ソースコードは MIT License で公開します。';
    if (_isZhHans) return '代码基于 MIT License 开源。';
    return 'Source code published under the MIT License.';
  }

  String get licenseStationDetailsTitle {
    if (_isJa) return '駅情報詳細';
    if (_isZhHans) return '车站信息详情';
    return 'Station information details';
  }

  String get licenseStationDetailsEkidata {
    if (_isJa) return '駅情報は 駅データ.jp のデータに基づき、加工・生成されたものです。';
    if (_isZhHans) return '车站信息衍生于 ekidata.jp 所公开的数据。';
    return 'Station information based on and derived from the dataset published by ekidata.jp.';
  }
}

/// Delegate
class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  bool isSupported(Locale locale) {
    final L10n loc = L10n(locale);
    return loc._isEn || loc._isJa || loc._isZhHans;
  }

  @override
  Future<L10n> load(Locale locale) async {
    final L10n loc = L10n(locale);
    if (!isSupported(locale)) return L10n(const Locale('en'));
    return loc;
  }

  @override
  bool shouldReload(_L10nDelegate old) => false;
}
