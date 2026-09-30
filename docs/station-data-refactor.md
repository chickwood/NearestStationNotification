# 车站数据外置化 重构文档

> 状态：定稿（保留项除外）
> 目标位置：`docs/station-data-refactor.md`（当前存于计划目录待移动）
> 关联：`docs/architecture.md`（实施时按项目约定先行更新）

## 背景与目标

现状：车站数据 `station_data_xyz.bin`（约 600KB、9000+ 车站）作为 asset 随应用打包，数据更新需发版。

目标：

1. asset 改为**少量示例数据**（与某个游戏相关的车站，可预测近年内 ≤10 个）；
2. 真实数据从**固定 URL 下载**（独立托管站点，背后为另一个 GitHub Release）；
3. 保留**文件选择器导入**——固定 URL 只能获取最新版，导入用于保留使用旧版本数据的选择能力。

入口：home 右上角 info 按钮（AppBar actions 最右侧、starting 中禁用）→ 新建 info dialog；原 settings 对话框内的「许可证及车站信息」区块整体迁入该 dialog。

---

## 定案设计

### 1. 生效方式（热重载 + 即时生效）

- 新增 `changeData`，与 `changeLocale` / `changeActive` / `changeSettings` 构成 changeXxx 家族（外部事件驱动的状态更新）。
- 即时原子换链：`Coordinator._manager`、`LocationProcessor._manager`、`_engine`（重建为 `SearchEngine(新 manager)`）在**同一同步块**内完成替换。
  - `LocationProcessor._manager`：final → 可变；`_engine`：late final → late。
  - Dart 单线程保证换链不与在途 fix 交错；索引与站名成对换新。
- 语义：流不中断、队列不清、无停止限制，任意状态（stopped / starting / running）可调用；UI 列表与通知在**下一个定位点**（≤ 采样间隔）刷新。
- 无任何提示（SnackBar 等）。

### 2. 数据操作流程

```
（info dialog 内下载 / 导入触发）获取字节 → 校验（复用尺寸校验）→ 原子写 ${documents}/${Common.binFileName}
（临时文件 → 改名；失败保旧数据）
→ StationManager.load()（documents 优先；选源回退规则见定案 3）
→ info dialog 刷新 bin 信息 + 回调 HomePage
→ _coordinator.changeData(新 manager) + HomePage setState
```

### 3. 数据源与回退

- 文件名不变：示例与真实同名 `station_data_xyz.bin`（assets 与 documents 路径不同）。
- 启动选源：documents 文件存在且校验通过则使用（含此前更新版本），否则回退 assets 示例（静默降级策略）。
- 更新（下载 / 导入）失败：不覆盖现有私有文件、不执行 `changeData`——此前更新过的版本继续生效，从未更新过则仍为示例。
- 激活 station_manager 中既有的 documents → assets 注释脚手架；pubspec 中 `path_provider` 取消注释。

### 4. 托管与发布

- 独立网站（背后为另一个 GitHub Release）；URL 写死为常量（Common）。
- AndroidManifest：增加 `INTERNET` 权限（必需——release 构建不会自动注入）；`READ_EXTERNAL_STORAGE` / `READ_MEDIA_IMAGES` 评估移除（SAF 不需要）。

### 5. 入口与交互（info dialog）

- 入口：home AppBar actions 最右侧新增 info 按钮；点击打开新建的 `InfoDialog`。按钮在 `starting` 中禁用，stopped / running 可用（换链本身任意状态安全，禁用仅为与 settings 一致的 UI 策略）。
- info dialog 结构（自上而下）：
  - 当前 bin 信息：车站数 / 大小 / 版本（= date）；（是否标注示例 / 真实来源随保留项 2）
  - 数据操作：下载按钮（固定 URL）+ 导入按钮（文件选择器）；
  - 状态行：下载中累计已下载字节 / 失败红色文案；
  - 许可证入口：原 settings 的「许可证及车站信息」区块样式不变，点击打开现有 `LicenseListDialog`（详情子对话框，维持现状）。
- settings 对话框：移除「许可证及车站信息」区块；`SettingsDialog` 不再接收 `manager`。
- 下载中：状态行显示**累计已下载字节**（无进度条、不依赖 Content-Length）；按钮（下载 / 导入 / 许可证入口）禁用；**禁止关闭**——`PopScope(canPop: false)` + `barrierDismissible: false` + X 禁用，`mounted` 守卫兜底。
- 失败：状态行红色 `下载失败，请点击下载重试`（纯文本不可点）；**下载按钮**恢复可用即重试；对话框恢复可关闭。
- 导入失败：同状态行红色文案（如"无效的文件"），重新选择即可。
- 文案草案（待定稿）：
  - 下载失败：
    - ja：`ダウンロード失敗。ダウンロードをタップして再試行`
    - zh-Hans：`下载失败，请点击下载重试`
    - en：`Download failed. Tap Download to retry`
  - 导入失败：ja `無効なファイルです` / zh-Hans `无效的文件` / en `Invalid file`
  - 按钮与标题：下载 ja `ダウンロード` / zh `下载` / en `Download`；导入 ja `インポート` / zh `导入` / en `Import`；标题 ja `情報` / zh `信息` / en `Info`

### 6. HomePage 引导

- 仅 `stopped` 且为示例数据时，在"定位停止中"（`l10n.notStarted`）**下一行**显示引导下载提示（改为 Column，第二行条件插入）。
- 下载真实数据后自动消失（见保留项 2）。
- 文案草案（待定稿）：
  - ja：`サンプルデータを使用中です。右上の情報ボタンから実データをダウンロードできます`
  - zh-Hans：`当前为示例数据。可点击右上角信息按钮下载真实数据`
  - en：`Sample data in use. Download the full data via the Info button (top right)`

---

## 风险与处置

| # | 风险 | 处置 |
|---|---|---|
| 1 | 替换前校验、原子写入（校验 → 临时文件 → 改名；失败保旧数据） | 采纳·实现细节（即时换链的前置依赖） |
| 2 | 类型化视图偏移（offsetInBytes 写法） | 已关闭（写法由实现处理） |
| 3 | 启动加载静默降级：documents 不存在 / 无效 → 示例回退（校验前置到选源） | 策略已定·实现落地 |
| 4 | HTTPS + 超时 + 响应大小上限 | 采纳·实现细节 |
| 5 | 生效方式 | 已定案（见定案 1） |
| 6 | 选择器跨平台（iOS 立即复制进 documents、Android SAF 免权限） | 已关闭（平台实现细节，不占决策面） |
| 7 | 入口位置：home 右上角 info 按钮 → info dialog（原 settings 区块迁入，为唯一数据管理入口） | 已定（info dialog 承载原区块与新增内容） |
| 8 | 示例数据首印象 | 已关闭（HomePage 引导提示覆盖） |
| 9 | 并发与退出 | 已定：下载中禁止关闭（返回键 / 外部点击 / X）；失败态恢复可关闭；按钮禁用防重入 |
| 10 | 托管与发布流程 | 已定案（见定案 4） |
| 11 | 出处说明文案（ADDITIONAL_NOTICE / 许可证详情） | 实现时检查 |
| 12 | 手动测试面 | 见文末测试清单 |

---

## 保留（未决）

1. **数据获取套餐**：A = `file_selector`（XFile.readAsBytes）+ `http` 包；B = `file_picker`（File(path).readAsBytes）+ `dart:io HttpClient`。风格问题，实现前拍板（读取在字节层收敛，不影响其余设计）。
2. **示例判定机制**：三选一——示例车站标记 / count 阈值（样本 ≤10，阈值取数十量级）/ 版本（日期）标记。
3. **是否有新版 / 自动检测**：依赖托管侧轻量清单（如 `latest.json`：日期/大小/可选 hash）+ 检测时机（启动 / 停止 / 定时）。
4. **按钮控件形态**：Button / GestureDetector / 链接；参考——对话框此前已统一为 GestureDetector 自定义样式（零涟漪）；info dialog 内新增按钮同此基准。

---

## 变更文件清单

| 文件 | 内容 |
|---|---|
| `lib/station_manager.dart` | 选源激活（documents → assets）、校验拆分、写入方法 |
| `lib/info_dialog.dart`（新增） | info dialog：bin 信息 / 下载 / 导入 / 状态行 / 失败重试 / 禁止关闭 / 许可证入口 |
| `lib/settings_dialog.dart` | 移除「许可证及车站信息」区块；去除 `manager` 参数 |
| `lib/home_page.dart` | AppBar info 按钮（最右侧、starting 禁用）、`_showInfoDialog`、引导提示、`changeData` 调用 |
| `lib/common.dart` | URL 常量、（示例判定常量——随保留项） |
| `lib/coordinator.dart` | `changeData` |
| `lib/location_processor.dart` | `changeData`（换链 + 引擎重建、字段可变性） |
| `lib/l10n.dart` | 新增文案（info dialog 标题 / 按钮 / 状态 / 失败 / 引导）；settingsInfoTitle 用途收缩为许可证详情标题 |
| `pubspec.yaml` | 依赖（套餐）、path_provider 取消注释、assets |
| `assets/station_data_xyz.bin` | 替换为示例数据 |
| `android/app/src/main/AndroidManifest.xml` | `INTERNET`（+ 可选权限清理） |
| `docs/architecture.md` | 按约定先行更新（changeData 家族、数据获取流程、info dialog 入口、settings 职责收缩） |

---

## 实施顺序（按项目约定）

1. 更新 `docs/architecture.md`（契约先行）；
2. 保留项拍板；
3. 实现（按变更文件清单）；
4. 手动测试。

---

## 手动测试清单

- 全新安装：示例数据加载 + stopped 引导提示出现；
- info 按钮：stopped / running 可打开；starting 中禁用；settings 对话框不再含许可证区块；
- info dialog 许可证入口：打开 LicenseListDialog，原功能无回归；
- 下载成功：状态行字节累计 → bin 信息刷新 → 引导消失 → 下一个定位点列表使用新数据；
- 下载失败（断网 / 超时 / 非 200）：红色文案 + 按钮重试；重试成功；
- 更新失败且此前已更新过：不覆盖现有文件、不执行 `changeData`，前次版本继续生效（不回落到示例）；
- 下载中：禁止关闭（返回键 / 外部点击 / X）、下载 / 导入 / 许可证入口禁用；
- 导入有效文件：流程同下载；导入无效文件：红色失败文案；
- documents 已有数据：冷启动优先加载；损坏时静默回退示例；
- Android release 包：`INTERNET` 权限生效（下载可用）。

---

## 附记

- `INTERNET` 权限为必需项（与数据托管位置无关，下载功能的前提）。
