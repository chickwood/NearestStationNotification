# 车站・事件数据外置化 重构文档

> 状态：已实现
> 关联：`docs/architecture.md`、`docs/service-refactor.md`（save / import Service 化定案）
> 验证：由 IDE 与手动测试清单执行，不自动运行构建 / 分析 / 测试

## 背景与目标

车站数据 `station_data_xyz.bin`（约 600KB、9000+ 车站）作为 asset 随应用打包；事件数据（event periods）独立为 `EventManager`，从 documents 覆盖。

目标：

1. station：assets 保留示例 / 过时数据，documents 中的导入数据优先；
2. event：独立成子系统（`EventManager`），documents 优先，缺失 / 无效时为空；
3. 去除应用内下载与自动更新；改为「info 界面提示 + 打开浏览器手动下载 + 导入」；
4. 通过 **ZIP 包**导入更新 station / event，并保留使用旧版本数据的选择能力。

入口：HomePage AppBar actions 最右侧 info 按钮（`starting` 中禁用）→ `InfoDialog`；原 settings 对话框内的「许可证及车站信息」区块迁入该 dialog。

---

## 定案设计

### 1. 生效方式（热重载 + 即时生效）

- `changeLocale` / `changeActive` / `changeSettings` / `changeStationData` / `changeEventData` 构成 changeXxx 家族（外部事件驱动的状态更新）。
- 车站数据即时原子换链：`Coordinator._manager`、`LocationProcessor._manager`、`_engine`（重建为 `SearchEngine(新 manager)`）在同一同步块内完成替换。
- 事件数据：`EventManager.isEventPeriod`（getter）读内存缓存；导入后重新加载即时生效，不需要换链。
- 语义：流不中断、队列不清、无停止限制，任意状态（stopped / starting / running）可调用；UI 列表与通知在下一个定位点（≤ 采样间隔）刷新。
- `changeXxx` 本身不显示提示；导入 / 设置保存的结果由 HomePage 在调用 `changeXxx` 之外统一 Toast。

### 2. 数据操作流程

```text
InfoDialog 导入按钮
        │
        ▼
InfoService.import()
        │
        ├─ file_selector 单选 zip
        ├─ 解析 zip（仅 bin / 仅 event / 两者）
        ├─ SHA256SUMS 校验（实际存在的文件）
        └─ StationManager.validate / EventManager.validate
        │
        ▼
原子写 documents（临时文件 → 改名；失败保留旧数据）
        │
        ├─ station → StationManager.load()
        └─ event   → EventManager.load()
        │
        ▼
InfoService.lastResult = InfoImportSucceeded / InfoImportFailed
        │
        ├─ InfoDialog：刷新 bin 信息，不关闭、不弹 Toast
        └─ HomePage：changeStationData / changeEventData + setState + Toast
```

设置保存：

```text
SettingsDialog 保存按钮
        │
        ▼
SettingsService.save(_draft)
        │
        ▼
Settings.save()
        │
        ▼
SettingsService.lastResult = SettingsSaved / SettingsSaveFailed
        │
        ├─ SettingsDialog：刷新自身状态，不关闭、不弹 Toast
        └─ HomePage：setState + changeSettings + Toast
```

### 3. 数据源与回退

- station 文件名不变：assets 与 documents 同名 `station_data_xyz.bin`（路径不同）。
- event：`event_data.json`（documents）；无代码内默认 periods，缺失 / 无效时为空。schema：

```json
{"periods": [{"start": "2026-05-01T15:00:00", "end": "2026-05-31T23:59:59"}]}
```

- 两个固定文件名文件，可只更新其一。
- 事件数据独立：`StationCount` 经注入的 `eventPeriod` 判定器消费（不直接依赖 `EventManager`）。
- 启动选源（station）：只依据 documents 文件（含此前更新版本）的读取结果——读取成功则使用；读取异常 / 文件不存在回退 assets（示例 / 过时数据）；加载后校验失败（含 assets 数据损坏）回退空实例（静默回退策略）。
- 启动加载（event）：与 `StationManager` 初始化同阶段；documents 优先，读取失败 / 无效 → 回退空实例（静默）。
- 更新（导入）失败：不覆盖现有私有文件、不生效（station 不执行 `changeStationData` / event 不刷新内存）——此前更新过的版本继续生效，从未更新过则仍为 assets / 空。
- 校验：
  - station：尺寸 / 结构校验在加载后与写入前执行，复用同一 `validate`；
  - event：JSON 可解析、`periods` 为数组、各元素 `start` / `end` 为可解析的本地时间且 start ≤ end，空数组合法；
  - zip：限制文件数、压缩 / 解压尺寸、条目名，`SHA256SUMS` 必须存在，实际存在的 bin / json 必须校验通过。
- 文件 IO：documents 读取、导入文件读取（`file_selector` 取 `XFile.path` 后 `File(path).readAsBytes()`）、documents 写入（临时文件 → 改名）均由 `dart:io` 承担；assets 读取保持 `rootBundle`。

### 4. 托管与发布（手动下载）

- 独立网站（背后为另一个 GitHub Release）提供 ZIP 包下载，包内含 `station_data_xyz.bin` / `event_data.json` / `SHA256SUMS`。
- URL 写死为 `Common` 常量。
- 不做：自动更新检测、应用内下载。

### 5. 入口与交互

#### info dialog

- 结构（自上而下）：标题行（信息）/ 许可证框 / 提示框 / 按钮行（关闭、导入）。
- 许可证框：展示当前 bin 信息（已读取 N 个车站 / 大小 / 版本（= date，存在修订时附 + 修订 = pdate））与许可证入口（打开 `LicenseListDialog`）。
- 提示框：与许可证框同外观（小节标签「更新」）——提示定期更新车站信息 / 事件信息数据；点击框体打开 `Common.dataUrl`（下载网站）；提示下载后点击导入、选择数据文件更新信息。
- 链接：`launchUrl(..., mode: LaunchMode.externalApplication)` 调用系统浏览器。
- 导入：
  - 按钮调用 `InfoService.import()`，`busy` 期间禁用；
  - `file_selector` 单选 zip，允许仅 bin、仅 event 或两者都有；
  - Service 内部完成解析、`SHA256SUMS` 校验、格式校验、原子写入与加载；
  - 订阅 `InfoService.lastResult`：`InfoImportSucceeded` 时刷新 bin 信息；成功 / 失败都不自动关闭；
  - Toast 由 HomePage 统一显示。
- 关闭：X、左下「关闭」、系统返回、点击遮罩均允许；关闭不影响 Service 继续执行与结果处理。

#### settings dialog

- 移除「许可证及车站信息」区块；不接收 `manager`。
- 保存：调用 `SettingsService.save(_draft)`，`busy` 期间禁用保存按钮。
- 订阅 `SettingsService.lastResult`：仅刷新自身状态；成功 / 失败都不自动关闭。
- 左下「关闭」与 X 同职责（`Navigator.pop`）。
- Toast 由 HomePage 统一显示。

#### 文案

- 提示框正文：
  - ja `駅情報・イベント情報データは定期的に更新してください。\nここをクリックして、ダウンロードサイトを開く。\n\nダウンロード後、インポートをクリックして、データファイルを選択して情報を更新。`
  - zh-Hans `请定期更新车站信息与事件信息数据。\n点击此处打开下载网站。\n\n下载后，点击导入，选择数据文件更新信息。`
  - en `Update station information and event information data periodically.\nTap here to open download website.\n\nAfter download, tap import, select data file to update information.`
- 导入结果：
  - station：ja `駅情報データをインポートしました。イベント情報データを更新する場合は続けてインポートしてください。` / zh-Hans `已导入车站信息数据。如需更新事件信息数据，可继续导入。` / en `Station information data imported. To update event information data, import it as well.`
  - event：ja `イベント情報データをインポートしました。駅情報データを更新する場合は続けてインポートしてください。` / zh-Hans `已导入事件信息数据。如需更新车站信息数据，可继续导入。` / en `Event information data imported. To update station information data, import it as well.`
- 导入失败：ja `無効なファイルです` / zh-Hans `无效的文件` / en `Invalid file`
- 设置保存：成功 `settingsSaveSucceeded`（ja `設定を保存しました。` / zh-Hans `设置已保存。` / en `Settings saved.`）；失败 `settingsSaveFailed`（ja `設定の保存に失敗しました` / zh-Hans `保存设置失败` / en `Failed to save settings`）
- 按钮与标题：导入 ja `インポート` / zh `导入` / en `Import`；关闭 ja `閉じる` / zh `关闭` / en `Close`；标题 ja `情報` / zh `信息` / en `Info`

### 6. HomePage 引导

- 仅 `stopped` 且为示例数据时，在「定位停止中...」（`l10n.notStarted`）下一行显示引导提示。
- 导入真实车站数据后自动消失。
- 文案：
  - ja：`サンプル駅情報を使用中です。右上の情報ボタンをクリックして駅情報を確認・更新。`
  - zh-Hans：`当前正在使用示例车站信息。点击右上角的信息按钮查看和更新车站信息。`
  - en：`Sample data in use. Tap the Info button on the top right to view and update station information.`

---

## Service 化

- HomePage 创建并持有 `InfoService` / `SettingsService`，`dispose` 取消订阅并释放。
- 两个 Service 各自持有 `ValueNotifier lastResult` 与 `ValueNotifier busy`；busy 时忽略新请求（单飞）。
- 结果类型：
  - `InfoImportResult` → `InfoImportSucceeded` / `InfoImportFailed`
  - `SettingsSaveResult` → `SettingsSaved` / `SettingsSaveFailed`
- Dialog 只触发 Service、订阅结果刷新自身；写盘、持久化、全局 Toast 均由 Service / HomePage 承担。
- 订阅方忽略订阅前的旧值；HomePage 在 `initState` 即订阅，不会漏掉新结果。

---

## 风险与处置

| # | 风险 | 处置 |
|---|---|---|
| 1 | 替换前校验、原子写入（校验 → 临时文件 → 改名；失败保旧数据） | 已实现（即时换链的前置依赖） |
| 2 | 类型化视图偏移（offsetInBytes 写法） | 已关闭（写法由实现处理） |
| 3 | 启动加载静默回退（station 见定案 3；event 回退空实例） | 已实现 |
| 4 | 生效方式 | 已定案（见定案 1） |
| 5 | 选择器跨平台（iOS 立即复制进 documents、Android SAF 免权限） | 已关闭（平台实现细节） |
| 6 | 入口位置：HomePage 右上角 info 按钮 → info dialog | 已实现（唯一数据管理入口） |
| 7 | 示例数据首印象 | 已关闭（HomePage 引导提示覆盖） |
| 8 | 托管与手动更新流程 | 已定案（见定案 4） |
| 9 | 出处说明文案（ADDITIONAL_NOTICE / 许可证详情） | 已实现·已检查 |
| 10 | Dialog 生命周期与异步操作解耦 | 已实现（见 Service 化） |
| 11 | 手动测试面 | 见文末测试清单 |

---

## 变更文件清单

| 文件 | 内容 |
|---|---|
| `lib/station_manager.dart` | 选源（documents → assets）、校验拆分、原子写入 |
| `lib/event_manager.dart` | 事件数据校验 / 加载 / 写入 / 期间判定 |
| `lib/info_service.dart`（新增） | `import()`：zip 选择 / 解析 / SHA256SUMS 校验 / 格式校验 / 原子写入 / 加载；`lastResult` + `busy` 单飞 |
| `lib/settings_service.dart`（新增） | `save()`：`Settings.save()`；`lastResult` + `busy` 单飞 |
| `lib/info_dialog.dart` | info dialog：bin 信息 / 许可证入口 / 提示框 / 导入按钮（触发 `InfoService`） / 结果订阅 / 关闭按钮 |
| `lib/settings_dialog.dart` | 移除许可证区块；通过 `SettingsService.save()` 保存；关闭按钮；不自动关闭 |
| `lib/home_page.dart` | info 按钮、`_showInfoDialog`、引导提示、持有并订阅两个 Service、Toast 与热加载 |
| `lib/common.dart` | URL 常量、示例判定常量、zip 限制常量 |
| `lib/coordinator.dart` | `changeStationData` / `changeEventData` |
| `lib/location_processor.dart` | `changeData`（换链 + 引擎重建） |
| `lib/l10n.dart` | info / 导入 / 引导 / `dialogClose` / `settingsSaveSucceeded` / `settingsSaveFailed`；删除 `settingsCancel` |
| `pubspec.yaml` | `file_selector`、`path_provider` / `url_launcher`、assets |
| `assets/station_data_xyz.bin` | 示例 / 过时数据（可保持现状） |
| `ios/Runner.xcodeproj/project.pbxproj` | deployment target 14.0 → 13.0 |
| `docs/architecture.md` | changeXxx、Service 化、Update Flow、info dialog、settings 职责、事件数据来源 |
| `docs/service-refactor.md` | save / import Service 化定案与实现记录 |

---

## 实施顺序（已完成）

1. 更新 `docs/architecture.md`（契约先行）；
2. 实现数据外置与 info dialog；
3. Service 化（`InfoService` / `SettingsService`）；
4. 同步文档；
5. 手动测试（见下）。

---

## 手动测试清单

- 全新安装：加载 assets；为示例数据时 stopped 引导提示出现；
- info 按钮：stopped / running 可打开；starting 中禁用；settings 对话框不含许可证区块；
- info dialog 许可证入口：打开 `LicenseListDialog`，原功能无回归；
- 提示框链接：点击打开系统浏览器；
- 导入 zip（仅 bin）：成功 Toast → bin 信息刷新 → 引导消失 → 下一个定位点列表使用新数据；
- 导入 zip（仅 event）：成功 Toast；`StationCount` 标签与搜索件数即时变化；
- 导入 zip（bin + event）：同时更新两侧，Toast 为「车站及活动信息」；
- 导入无效数据：错误 zip、缺失 / 错误 `SHA256SUMS`、格式非法 → 红色「无效的文件」Toast，不生效；
- 取消文件选择：无变化、无 Toast；
- 导入进行中关闭对话框：结果仍由 HomePage 接收并 Toast / 热加载；X、关闭按钮、系统返回、遮罩均可用；
- 设置保存成功 / 失败：Toast 与导入同配色；保存后对话框不关闭，可继续编辑或点击关闭；
- 重复点击保存 / 导入：Service 单飞生效，不重复执行；
- 更新失败且此前已更新过：不覆盖现有文件、不生效（station 不换链 / event 不刷新内存），前次版本继续生效（不回落到 assets / 空）；
- documents 已有数据：冷启动优先加载；读取失败 / 文件不存在静默回退 assets（示例 / 过时数据）；文件损坏（含 0 字节文件）→ 加载后校验失败回退空实例；
- 冷启动（event）：documents 事件数据优先；不存在 / 无效 → 空实例；
- HomePage 销毁 / 重建：Service 监听与生命周期正确释放。
