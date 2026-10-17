# 车站・事件数据外置化 重构文档

> 状态：已实现
> 关联：`docs/architecture.md`（实施时按项目约定先行更新）

## 背景与目标

现状：车站数据 `station_data_xyz.bin`（约 600KB、9000+ 车站）作为 asset 随应用打包，数据更新需发版；事件数据（event periods）硬编码在代码中。

目标：

1. station：asset 保留现状（示例 / 过时数据）或替换为**少量示例数据**（与某个游戏相关的车站，可预测近年内 ≤10 个）——非强制；
2. event：独立成子系统（`EventManager`），从「代码硬编码」改为「documents 覆盖」；
3. 去除应用内下载与自动更新（不做检测、不做下载）；改为「info 界面提示 + 打开浏览器手动下载 + 导入」；
4. 保留**文件选择器导入**——单个文件（station 或 event），用于手动下载文件的导入更新，并保留使用旧版本数据的选择能力。

入口：home 右上角 info 按钮（AppBar actions 最右侧、starting 中禁用）→ 新建 info dialog；原 settings 对话框内的「许可证及车站信息」区块整体迁入该 dialog。

---

## 定案设计

### 1. 生效方式（热重载 + 即时生效）

- 新增 `changeData`，与 `changeLocale` / `changeActive` / `changeSettings` 构成 changeXxx 家族（外部事件驱动的状态更新）。
- 即时原子换链：`Coordinator._manager`、`LocationProcessor._manager`、`_engine`（重建为 `SearchEngine(新 manager)`）在**同一同步块**内完成替换。
  - `LocationProcessor._manager`：final → 可变；`_engine`：late final → late。
  - Dart 单线程保证换链不与在途 fix 交错；索引与站名成对换新。
- 语义：流不中断、队列不清、无停止限制，任意状态（stopped / starting / running）可调用；UI 列表与通知在**下一个定位点**（≤ 采样间隔）刷新。
- 无任何提示（Toast 等）。
- 事件数据：`EventManager.isEventPeriod`（getter）读内存缓存；导入后重新加载即时生效（不需要 `changeData`）。

### 2. 数据操作流程

```
（info dialog 内导入触发，单文件）获取字节 → 校验 → 原子写 ${documents}/<对应文件名>
（临时文件 → 改名；失败保留旧数据）

station：StationManager.load()（documents 优先；选源回退规则见定案 3）
→ info dialog 刷新 bin 信息 + 回调 HomePage → _coordinator.changeData(新 manager) + HomePage setState

event：刷新内存 periods（即时生效）
```

### 3. 数据源与回退

- station 文件名不变：assets 与 documents 同名 `station_data_xyz.bin`（路径不同）。
- event：`event_data.json`（documents）；无代码内默认 periods，缺失 / 无效时为空。schema：

```json
{"periods": [{"start": "2026-05-01T15:00:00", "end": "2026-05-31T23:59:59"}]}
```

- 两个固定文件名文件，可只更新其一。
- 事件数据独立：`common.dart` 的 `_eventPeriods` 与 `isEventPeriod()` 迁入 `lib/event_manager.dart`（`EventManager`）；`common.dart` 的 `StationCount` 经注入的 `eventPeriod` 判定器消费（不直接依赖 `EventManager`）。
- 启动选源（station）：只依据 documents 文件（含此前更新版本）的读取结果——读取成功则使用；读取异常 / 文件不存在回退 assets（示例 / 过时数据）；加载后校验失败（含 assets 数据损坏）回退空实例（静默回退策略）。
- 启动加载（event）：与 `StationManager` 初始化同阶段；documents 优先，读取失败 / 无效 → 回退空实例（静默）。
- 更新（导入）失败：不覆盖现有私有文件、不生效（station 不执行 `changeData` / event 不刷新内存）——此前更新过的版本继续生效，从未更新过则仍为 assets / 空。
- 校验：station 尺寸 / 结构校验在加载后与写入前执行，复用同一 `validate`；event JSON 校验——可解析、`periods` 为数组、各元素 `start` / `end` 为可解析的本地时间且 start ≤ end、空数组合法。
- 文件 IO 统一：内容读取 / 写入全部由 `dart:io` 承担——documents 读取、导入文件读取（`file_selector` 取 `XFile.path` 后 `File(path).readAsBytes()`）、documents 写入（临时文件 → 改名）；选择器只负责选择；assets 读取保持 `rootBundle`。
- 激活 station_manager 中既有的 documents → assets 注释脚手架；pubspec 中 `path_provider` 取消注释。

### 4. 托管与发布（手动下载）

- 独立网站（背后为另一个 GitHub Release）：页面提供两个文件的下载（`station_data_xyz.bin` / `event_data.json`）。
- URL 写死为常量（Common）。
- 不做：自动更新检测、应用内下载。

### 5. 入口与交互（info dialog）

- 入口：home AppBar actions 最右侧新增 info 按钮；点击打开新建的 `InfoDialog`。按钮在 `starting` 中禁用，stopped / running 可用（换链本身任意状态安全，禁用仅为与 settings 一致的 UI 策略）。
- info dialog 结构（自上而下）：标题行（信息）/ 许可证框 / 提示框 / 按钮行（取消、导入）。
- 删除（已实现部分）：下载按钮与下载进度 / 状态、`_download` / `_fetchData` 方法及 `dart:io`（HttpClient）、超时与大小上限常量（`_connectTimeout` / `_idleTimeout` / `_maxDataBytes`）、下载中禁止关闭相关逻辑（`_downloading` 守卫、`PopScope`）。
- 许可证框：展示当前 bin 信息（已读取 N 个车站 / 大小 / 版本（= date，存在修订时附 + 修订 = pdate））与许可证入口（点击打开现有 `LicenseListDialog`，详情子对话框）。
- 提示框：与许可证框同外观（小节标签「更新」）——提示定期更新车站信息 / 事件信息数据；点击框体打开 `Common.dataUrl`（下载网站）；并提示下载后点击导入、选择数据文件更新信息。
- 链接：点击 → `launchUrl(..., mode: LaunchMode.externalApplication)` 调用系统浏览器。
- settings 对话框：移除「许可证及车站信息」区块；`SettingsDialog` 不再接收 `manager`。
- 导入：使用 `file_selector` 单选（限 `bin` / `json`），一次只选一个文件（多选可能误选同一数据的多个版本）；按**内容**路由（station 走 `validate`；event 走 JSON 校验；无法识别 → 无效文件）；成功 Toast 提示已导入车站信息 / 事件信息数据，并提示另一侧可再次选择导入；失败 → Toast 红字（统一「无效的文件」）。
- 文案：
  - 提示框正文：ja `駅情報・イベント情報データは定期的に更新してください。\nここをクリックして、ダウンロードサイトを開く。\n\nダウンロード後、インポートをクリックして、データファイルを選択して情報を更新。` / zh-Hans `请定期更新车站信息与事件信息数据。\n点击此处打开下载网站。\n\n下载后，点击导入，选择数据文件更新信息。` / en `Update station information and event information data periodically.\nTap here to open download website.\n\nAfter download, tap import, select data file to update information.`
  - 导入结果提示：
    - station：ja `駅情報データをインポートしました。イベント情報データを更新する場合は続けてインポートしてください。` / zh-Hans `已导入车站信息数据。如需更新事件信息数据，可继续导入。` / en `Station information data imported. To update event information data, import it as well.`
    - event：ja `イベント情報データをインポートしました。駅情報データを更新する場合は続けてインポートしてください。` / zh-Hans `已导入事件信息数据。如需更新车站信息数据，可继续导入。` / en `Event information data imported. To update station information data, import it as well.`
  - 导入失败：ja `無効なファイルです` / zh-Hans `无效的文件` / en `Invalid file`
  - 按钮与标题：导入 ja `インポート` / zh `导入` / en `Import`；标题 ja `情報` / zh `信息` / en `Info`

### 6. HomePage 引导

- 仅 `stopped` 且为示例数据时，在「定位停止中...」（`l10n.notStarted`）**下一行**显示引导提示（改为 Column，第二行条件插入）。
- 导入真实车站数据后自动消失。
- 文案：
  - ja：`サンプル駅情報を使用中です。右上の情報ボタンをクリックして駅情報を確認・更新。`
  - zh-Hans：`当前正在使用示例车站信息。点击右上角的信息按钮查看和更新车站信息。`
  - en：`Sample data in use. Tap the Info button on the top right to view and update station information.`

---

## 风险与处置

| # | 风险 | 处置 |
|---|---|---|
| 1 | 替换前校验、原子写入（校验 → 临时文件 → 改名；失败保旧数据） | 采纳·实现细节（即时换链的前置依赖） |
| 2 | 类型化视图偏移（offsetInBytes 写法） | 已关闭（写法由实现处理） |
| 3 | 启动加载静默回退（station 见定案 3；event 回退空实例） | 策略已定·实现落地 |
| 4 | 生效方式 | 已定案（见定案 1） |
| 5 | 选择器跨平台（iOS 立即复制进 documents、Android SAF 免权限） | 已关闭（平台实现细节，不占决策面） |
| 6 | 入口位置：home 右上角 info 按钮 → info dialog（原 settings 区块迁入，为唯一数据管理入口） | 已定（info dialog 承载原区块与新增内容） |
| 7 | 示例数据首印象 | 已关闭（HomePage 引导提示覆盖） |
| 8 | 托管与手动更新流程 | 已定案（见定案 4） |
| 9 | 出处说明文案（ADDITIONAL_NOTICE / 许可证详情） | 已实现·已检查 |
| 10 | 手动测试面 | 见文末测试清单 |

---

## 变更文件清单

| 文件 | 内容 |
|---|---|
| `lib/station_manager.dart` | 选源激活（documents → assets）、校验拆分、写入方法 |
| `lib/event_manager.dart`（新增） | 事件数据校验 / 加载 / 写入 / 期间判定 |
| `lib/info_dialog.dart`（新增） | 删下载相关；info dialog：bin 信息 / 许可证入口 / 提示框（含链接） / 导入（`file_selector` 单选、内容路由、`dart:io` 读取） / Toast（结果与失败） |
| `lib/settings_dialog.dart` | 移除「许可证及车站信息」区块；去除 `manager` 参数 |
| `lib/home_page.dart` | AppBar info 按钮（最右侧、starting 禁用）、`_showInfoDialog`、引导提示、`changeData` 调用 |
| `lib/common.dart` | URL 常量、示例判定常量；移出 `_eventPeriods` / `isEventPeriod()`（`StationCount` 改经注入判定器消费） |
| `lib/coordinator.dart` | `changeData` |
| `lib/location_processor.dart` | `changeData`（换链 + 引擎重建、字段可变性） |
| `lib/l10n.dart` | 新增文案（info dialog 标题 / 许可证框 / 提示框 / 导入结果与失败 / 引导）；删除 `infoDownload` / `infoDownloadFailed`；settingsInfoTitle → infoTitle |
| `pubspec.yaml` | 依赖（`file_selector`）、`path_provider` / `url_launcher` 取消注释、assets |
| `assets/station_data_xyz.bin` | 可选：替换为示例数据（非强制，可保持现状） |
| `ios/Runner.xcodeproj/project.pbxproj` | deployment target 14.0 → 13.0 |
| `docs/architecture.md` | 按约定先行更新（changeData 家族、数据获取流程、info dialog 入口、settings 职责收缩、事件数据来源与格式、去下载条款） |

---

## 实施顺序（按项目约定）

1. 更新 `docs/architecture.md`（契约先行）；
2. 实现（按变更文件清单）；
3. 手动测试。

---

## 手动测试清单

- 全新安装：加载 assets；为示例数据时 stopped 引导提示出现；
- info 按钮：stopped / running 可打开；starting 中禁用；settings 对话框不再含许可证区块；
- info dialog 许可证入口：打开 LicenseListDialog，原功能无回归；
- 提示框链接：点击打开系统浏览器；
- 导入 station 单文件：Toast 提示（已导入车站信息数据 / 另一侧可继续导入）→ bin 信息刷新 → 引导消失 → 下一个定位点列表使用新数据；
- 导入 event 单文件：Toast 提示（已导入事件信息数据 / 另一侧可继续导入）；`StationCount` 标签与搜索件数即时变化；
- 导入无效文件：红色失败文案；取消选择：无变化；
- 更新失败且此前已更新过：不覆盖现有文件、不生效（station 不换链 / event 不刷新内存），前次版本继续生效（不回落到 assets / 空）；
- documents 已有数据：冷启动优先加载；读取失败 / 文件不存在静默回退 assets（示例 / 过时数据）；文件损坏（含 0 字节文件）→ 加载后校验失败回退空实例；
- 冷启动（event）：documents 事件数据优先；不存在 / 无效 → 空实例。
