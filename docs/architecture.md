# Architecture

## Preface

本文档是项目当前唯一的架构契约（Architecture Contract）。

- 所有较大的修改遵循以下流程：

```text
Discussion
↓
Update architecture.md
↓
Implementation
↓
Review
↓
Test
```

- 如实现与本文档冲突，应先讨论并更新本文档，再修改代码。
- 本文档描述的是当前认可的架构，而不是项目演进历史。

---

## Design Principles

原则：

- 单向依赖（Unidirectional Dependency）
- 单一职责（Single Responsibility）
- SearchEngine 保持纯算法
- NotificationConsumer 保持纯通知
- StationManager 是唯一站点数据来源（Single Source of Truth）
- EventManager 是唯一事件数据来源
- HistoryConsumer 持有未落盘缓冲（pending）并负责记录判定与批量写穿（10 条 / 首条起算 5 分钟，按日批量追加）；HistoryManager 负责持久化；UI 按日合并磁盘与 pending；Coordinator 只公开 HistoryConsumer，由页面直接订阅
- Coordinator 只负责协调，不负责业务实现
- 持久化与导入的异步执行从 Dialog 生命周期中解耦（InfoImportService / SettingsSaveService / HistoryBackupService）
- 日期只有一种表示：本地 `yyyyMMdd` 的 `int`（月份为 `date ~/ 100`），值即键，不做多表示并存；`epoch`（int 毫秒）单独命名（见 `Date Representation`）
- 不为了设计而设计
- 当前项目规模优先保持职责清晰、依赖简单、易维护

---

## Project Layout

| 文件 | 职责 |
|---|---|
| `lib/main.dart` | 应用引导：注入包名、注册 ADDITIONAL_NOTICE 许可证、创建 `StyledToast` / `MaterialApp` |
| `lib/ui/home_page.dart` | 主 UI、生命周期、初始化编排、Service 持有与结果处理、对话框入口、BackgroundTask |
| `lib/coordinator.dart` | 业务流程协调、权限请求、定位结果补全与广播、运行状态机、公开 HistoryConsumer |
| `lib/consumer/notification_consumer.dart` | 通知常驻消费者：接收定位结果广播并更新系统通知 |
| `lib/consumer/history_consumer.dart` | 历史常驻消费者：切换判定、开关与补记、pending 缓冲、10 条 / 首条起算 5 分钟的批量落盘 |
| `lib/location_processor.dart` | GPS 流、采样策略、漂移过滤、SearchEngine 调用 |
| `lib/search_engine.dart` | KD-Tree 最近车站搜索、距离与方位角计算 |
| `lib/manager/station_manager.dart` | 车站 BIN 数据校验、加载、原子写入、按索引访问 |
| `lib/manager/event_manager.dart` | 事件 NDJSON 数据校验、加载、原子写入、事件期间判定 |
| `lib/manager/settings_manager.dart` | `SettingsManager` 模型与 SharedPreferences 持久化 |
| `lib/manager/history_manager.dart` | 车站切换历史记录、日/月文件、月度归档、备份与导入 |
| `lib/service/info_import_service.dart` | `InfoImportService`、ZIP 导入解析与校验 |
| `lib/service/settings_save_service.dart` | `SettingsSaveService` |
| `lib/service/history_backup_service.dart` | `HistoryBackupService`、历史备份导出/导入（不含文件对话框） |
| `lib/ui/settings_dialog.dart` | 设置对话框 |
| `lib/ui/info_dialog.dart` | 信息对话框 |
| `lib/ui/license_dialog.dart` | 许可证列表与详情对话框 |
| `lib/ui/history_page.dart` | 历史月份/日期列表、单日逐条与区块展示 |
| `lib/l10n.dart` | 中 / 日 / 英文本、locale 严格解析 |
| `lib/common.dart` | 常量、几何计算、数据类与枚举 |

目录结构：

```text
lib/
├── main.dart
├── common.dart
├── coordinator.dart
├── l10n.dart
├── location_processor.dart
├── search_engine.dart
├── consumer/
│   ├── notification_consumer.dart
│   └── history_consumer.dart
├── manager/
│   ├── station_manager.dart
│   ├── event_manager.dart
│   ├── history_manager.dart
│   └── settings_manager.dart
├── service/
│   ├── info_import_service.dart
│   ├── settings_save_service.dart
│   └── history_backup_service.dart
└── ui/
    ├── home_page.dart
    ├── settings_dialog.dart
    ├── info_dialog.dart
    ├── license_dialog.dart
    └── history_page.dart
```

---

## Constructor Parameter Convention

区分「构造函数传参」与「方法执行时传参」的判断基准：

- **构造函数传参（位置参数 + `this.x` 直接赋值）**：
  - 对象生命周期内代表其依赖关系的值（如回调函数、管理器、设置、语言）
  - 判断标准不是「是否会变」，而是「变化的来源是否属于该对象所处的环境状态」；此类值变化后即代表「当前状态」、并被对象内部多处方法读取
  - 例：`l10n`（系统语言变化）、`active`（前后台切换）、`settings`（设置项保存）、`manager`（站点数据管理）、`eventManager`（事件数据管理）均属此类，生命周期模式相同：HomePage 初始化产生初值 → 传入 → 运行期间由外部事件驱动变化 → 通知更新
  - 私有字段（下划线开头）不能使用命名参数（Dart 语言限制），故统一使用位置参数

- **方法参数传参**：
  - 与某次具体操作绑定、操作结束后该值即完成使命的数据
  - 不需要被对象在多处内部方法间保存和复用

- **Service 与 Widget 的传参**：
   - `InfoImportService` / `SettingsSaveService` / `HistoryBackupService` 由 HomePage 在 `initState` 创建并持有，经构造参数传给对话框 / HistoryPage；其公开字段为 `final`
  - Widget 为不可变描述，字段公开且 `final`；可变性由配套 `State` 承接
  - 更新「当前状态」类字段时，使用专门的 `changeXxx()` 方法，不通过构造函数重新赋值
  - `start()` / `stop()` 等生命周期方法尽量保持无参数、成对存在，所需状态在构造函数或 `changeXxx()` 中已经就绪

---

## Field Visibility

「构造传参」只约束参数的传递方式，不规定字段可见性。字段可见性按对象类型区分：

- **协调 / 处理类**（`Coordinator`、`LocationProcessor`、`NotificationConsumer`、`HistoryConsumer`）：字段是内部状态，私有且可重新赋值，只能经 `changeXxx()` 等专用方法变更
- **数据快照**（`StationManager`、`EventManager`）：加载后只读；`StationManager` 的数组与元数据、`EventManager` 的期间数据（epoch ms）均不再修改
- **未落盘缓冲**（`HistoryConsumer`）：`List<HistoryRecord>` 为内部状态，只保留上次 flush 成功后新增的记录；历史页经 `historyConsumer.pendingRecords` 读取，不经 UI 修改
- **历史存储**（`HistoryManager`）：目录与锁为内部状态，全部私有；对外只提供追加、读取、日期/月份枚举、归档与备份/导入方法，不持有当天内存状态
- **可变设置**（`SettingsManager`）：字段公开可写；对话框使用 `copyWith()` 生成草稿，保存后由 Service 持久化
- **结果服务**（`InfoImportService`、`SettingsSaveService`、`HistoryBackupService`）：对外暴露 `final ValueNotifier last` 与 `final ValueNotifier<bool> busy`（`HistoryBackupService` 另有 `final ValueNotifier<double> progress`），内部不使用 `changeXxx`
- **UI 组件（Widget）**：字段须 `final` 且公开（`State` 经 `widget.x` 读取）；可变性由配套的 `State` 承接并反映到 UI

---

## Date Representation

日期只有一种表示：`int date`，即本地时区的 `yyyyMMdd`（8 位数字）。它同时充当数据值、Map key、相等比较与排序依据，因此键名直接用 `date`，不加 `Key` / `Day` 等后缀，也不引入包装类型、typedef 或 extension type。

- **月份**：`int month = date ~/ 100`（6 位），同样只用 `int`，不定义独立月份类型；位数（`date >= 10000101`）是日期与月份的区分依据。
- **提取只用算术**：年 `date ~/ 10000`、月 `date ~/ 100 % 100`、日 `date % 100`。禁止用 `substring` / `int.parse` / `padLeft` 拆装日期。
- **比较**：月份归属用 `date ~/ 100 == month`，不用 `startsWith` 等字符串前缀比较；日期 / 月份列表排序直接比较 `int`（数值序即时间序）。
- **唯一转换入口**：集中在 `lib/common.dart` 的 `Common`，其他模块不得自建副本；`HistoryRecord` 的日期派生同样走该入口：
  - `dateOf(DateTime)`、`dateOfEpoch(int epoch)` → `int date`
  - `monthDateOf(int date)` → `int month`（`date ~/ 100`）
  - `yearOf` / `monthOf` / `dayOf` → 年、月（1–12）、日（1–31）分量
  - `isValidDate` / `isValidMonth` → 合法性校验
  - 不提供通用的 `date` → `DateTime` 转换方法：仅在必须构造 `DateTime` 的边界处就地转换（见下条「分量例外」）
- **合法性**：`date >= 10000101` 且经 `DateTime(y, m, d)` 回检；`0` 表示「未设置」必须放行（`StationManager` 空实例的 `date` / `pdate` 为 0）。
- **文件名**：由 `int` 直接插值，日 `$date.ndjson`（8 位）、月 `$month.zip`（6 位），年份 ≥ 1000 时位数天然正确；目录扫描仍以 `^\d{8}$` / `^\d{6}$` 正则取名字，再 `int.parse` 成 `date` / `month`。
- **分量例外**：除键的生成 / 解析 / 合法性回检与页面标题显示之外，全项目只有以下三处需要用到分量，且都不改变「`int date` 是唯一日期表示」的约定：
  - 月度归档调度：按当前日序（`date % 100`，即当月第几天）判断 3 日 / 10 日窗口，只需要「日」，不需要年与月
  - 月份导航与月份比较：`DateTime(y, m ± 1)` / `DateTime(y, m)` 需要年 + 月成对，且必须借 `DateTime` 完成年进位归一化（1 月 → 上一年 12 月）
  - `showDatePicker` 的 `firstDate` / `lastDate`：需要年 + 月 + 日构造「今天」边界
- **边界例外**：`DateTime` 只出现在 `DateTime.now()`、`showDatePicker`、月份导航的加减与边界构造、与 epoch 互转、UI 文本格式化过程中，不作为字段、参数或 Map key 的日期类型。
- **`epoch`**：int 毫秒是另一套时间表示，与 `date` 并存但语义不同，命名必须是 `epoch` / `...Epoch`，不得写成 `date*`。
- **`stamp`**：专指由 epoch 派生的文件名字片段（当前为导出 zip 文件名），不参与数据键，也不等同于 `date`。

不采用：字符串日期键、同一日期维护 `String` / `int` 双份表示、按用途拆分多种日期类型。

---

## Dependency

```text
                        main.dart
                            │
                            ▼
                        HomePage
        ┌───────────────┬───────────────┬───────────────┬──────────────────────────┐
        ▼               ▼               ▼               ▼                          ▼
   Coordinator   StationManager   EventManager   InfoImportService /     HistoryManager /
        │               ▲               ▲          SettingsSaveService    HistoryBackupService
        │               │               │               │                          │
        │               │               │               ▼                          ▼
        │               │               │        InfoDialog /              HistoryPage
        │               │               │        SettingsDialog                  ▲
        │               │               │                                        │
        ├───────────────┘               │                               SettingsDialog
        │                               │
        ├──► LocationProcessor ──► SearchEngine ──► StationManager
        ├──► NotificationConsumer
        └──► HistoryConsumer ──► HistoryManager

HomePage 另持有 SettingsManager，并将其传入 Coordinator；Coordinator 再向 LocationProcessor 传 `processorSettingsManager`、向 HistoryConsumer 传 `historySettingsManager`；SettingsDialog 由 HomePage 注入 `historyConsumer`，再转交 HistoryPage（HistoryPage 不依赖 Coordinator）；
BackgroundTask 包裹 HomePage（Android only）。
```

约束：

- SearchEngine 是 LocationProcessor 的内部依赖。
- SettingsManager 只通过两个只读视图对外：`processorSettingsManager`（`stationCount` / `locationInterval`）与 `historySettingsManager`（`historyEnabled` / `historyMergeView`）；LocationProcessor 与 HistoryConsumer 不持有 SettingsManager 本体。
- StationManager 是共享 Repository；HomePage、LocationProcessor、SearchEngine、Coordinator、InfoImportService、InfoDialog、LicenseListDialog 均可依赖。
- EventManager 是事件数据来源，独立于定位结果流；HomePage、Coordinator、InfoDialog、LicenseListDialog 可直接依赖。
- HistoryConsumer 持有 pending 缓冲并负责记录判定、开关补记与按日批量写穿；记录按自身 `epoch` 写入对应日文件，同一天的多条一次写入，成功后从 pending 移除。
- NotificationConsumer / HistoryConsumer 是 Coordinator 的常驻定位结果消费者：接收广播 payload，各自持有私有状态并在 Coordinator 之外产生副作用；不读取 Coordinator 快照。
- HistoryConsumer 每次成功写入后递增 `flushCount`、每次追加 pending 后递增 `pendingRevision`；非活跃期间两者均不递增，恢复 active 时成对递增。历史页直接订阅这两个通知，不经过 Coordinator。
- HistoryManager 是过往历史存储与查询的唯一来源；不持有当天内存状态、不注册定位 handler、不依赖 Coordinator / HistoryConsumer、UI 或文件对话框。
- HistoryPage 由 HomePage → SettingsDialog 注入 `HistoryConsumer`，不依赖 Coordinator：订阅 `pendingRevision` 触发增量重建、`flushCount` 触发磁盘重读，build 时按日合并 `HistoryManager.readDay()` 与 `historyConsumer.pendingRecords`；页面只判断 `mounted`，前后台门控在 Consumer（`Coordinator.changeActive` 转发），恢复时由 Consumer 补发通知。
- HistoryBackupService 由 HomePage 在 `initState` 创建并持有，不持有 HistoryManager；`createExport(HistoryManager)` / `import(HistoryManager, path)` 由调用方传入参数，不接触文件对话框。注入 HistoryPage 与 SettingsDialog；文件选择/保存由 HistoryPage 负责，进入 Service 的处理在页面关闭后继续。
- Coordinator 通过 `changeEventData` 将事件期间判定注入 `StationCount.eventPeriod`。
- Coordinator 不负责 StationManager / EventManager / HistoryManager 的加载与写入实现；HistoryManager 的日文件追加由 HistoryConsumer 触发。
- InfoImportService / SettingsSaveService / HistoryBackupService 不依赖 UI，不直接调用 Coordinator 或 Toast。
- Dialog 只依赖其显示所需的管理器与 Service；HistoryPage 依赖 `HistoryConsumer`、HistoryManager、HistoryBackupService、StationManager 与 `HistorySettingsManager`。

---

## App Bootstrap

`main()`：

- 调用 `WidgetsFlutterBinding.ensureInitialized()`。
- 通过 `PackageInfo.fromPlatform()` 取包名最后一段写入 `Common.appName`。
- 注册 `ADDITIONAL_NOTICE`（车站数据免责声明）到 `LicenseRegistry`；`LICENSE` 本体已打包但注册代码当前注释停用。
- `runApp()` 启动 `StyledToast(child: MaterialApp(...))`，因此 Toast 渲染在应用级 Overlay，层级高于 Dialog 路由。

`MaterialApp`：

- 标题、主题、语言委托、`supportedLocales` 由 `L10n` 提供。
- `localeListResolutionCallback` 与 HomePage 共用 `L10n.resolve()`，保证 UI 与通知语言一致。
- 首页固定为 `HomePage`。

---

## Responsibilities

### HomePage（定义于 `ui/home_page.dart`）

职责：

- UI 与 WidgetsBindingObserver
- 生命周期（paused / resumed → `changeActive`；locale 变化 → `changeLocale`）
- 初始化编排：`initState` 注册 Service 监听与观察者，首帧后执行 `_initialize()`
- 并行加载 SettingsManager / StationManager / EventManager / HistoryManager（`Future.wait`）
- 创建 Coordinator，注册定位结果 / 运行状态 handler，调用 `coordinator.init()`
- 初始化完成后异步执行 `HistoryManager.consolidateIfDue()`，不阻塞首页
- 在 `initState` 创建并持有 InfoImportService / SettingsSaveService / HistoryBackupService（生命周期跟随 HomePage；dispose 时释放）
- Manager（Settings / Station / Event / History）在首帧后的 `Future.wait` 中加载；Service 不持有 Manager，按调用传入
- 订阅 Service 结果：导入 / 设置保存 / 历史备份的 Toast、Coordinator 热加载与 `setState`
- 设置入口（settings dialog：设置项编辑与保存、历史记录入口）
- 站点数据管理入口（info dialog：bin 信息 / 提示 / 导入 / 许可证入口）
- 示例数据引导提示（stopped 且为示例数据时）
- 通过 Coordinator 的 handler 触发 UI 重建，并通过 getter 读取当前结果和运行状态
- 向 BackgroundTask 提供 `Coordinator.runningStatus != RunningStatus.stopped` 的 keepBackgroundTask
- 坐标详情三态显示切换（隐藏 / 经纬度 / 经纬度 + 速度、精度、方向、时刻）
- 初始化失败时 `debugPrint` 并显示错误 Toast

可直接使用：

- StationManager / EventManager（站点信息显示、站点与事件数据管理）
- SettingsManager（站点显示数量、定位间隔、历史记录开关）
- HistoryManager / HistoryBackupService（过往历史读取与备份操作）
- Coordinator（直接注入历史页，提供当天记录）

不负责：

- GPS
- 搜索
- Notification
- 权限
- 数据解析与写盘

---

### Coordinator

职责：

- 协调业务流程
- 创建 LocationProcessor / NotificationConsumer / HistoryConsumer，并注册两个常驻定位结果 handler
- HistoryConsumer 以常驻 handler 注册，保证 pending 先于 active handler 更新
- 注入事件期间判定到 `StationCount.eventPeriod`
- 公开 `historyConsumer`，供 HomePage 注入 SettingsDialog → HistoryPage
- `init()` 只初始化通知，不预载历史；历史由页面按日读盘并合并 pending
- start()
- stop()（等待 `HistoryConsumer.flush()`；pending 保留在 Consumer）
- 生命周期转发（changeActive；向 LocationProcessor 与 HistoryConsumer 转发 active；恢复前台时重发缓存结果；进入后台不强制 flush，依赖 10 条阈值 / 首条起算的 5 分钟窗口 / stop）
- locale 更新（changeLocale；转发 NotificationConsumer）
- settings 更新（changeSettings；向 LocationProcessor 转发 `processorSettingsManager`，向 HistoryConsumer 转发 `historySettingsManager`）
- station data 更新（changeStationData）
- event data 更新（changeEventData）
- 请求定位权限与通知权限
- 接收定位结果、丢弃停止后到达的延迟结果
- 根据 StationManager 补全 station metadata（gcd / name）
- 维护 PositionResult / StationResults / RunningStatus
- 通过 handler 集合广播完整定位结果与运行状态
- 停止时清空定位状态、取消通知并广播 `(null, null)`

不负责：

- GPS 流实现
- SearchEngine
- 车站切换判定、历史总开关、同站补记跳过、pending 缓冲与批量落盘时机（属 HistoryConsumer）
- StationManager / EventManager / HistoryManager 的加载与文件写入实现
- 过往月份归档、备份文件格式与导入校验
- 本地通知内容与样式
- UI

Coordinator 只负责协调（Coordinate），不负责业务实现（Implement）：快照（position / stations / runningStatus）+ 广播 + 控制面转发 + 历史门面。

控制面（Coordinator 直调消费者）：NotificationConsumer 的 `init()` / `requestPermissions()` / `changeLocale()` / `cancelAll()`，HistoryConsumer 的 `changeActive()` / `changeSettings()` / `flush()`；数据面统一走 handler 广播。

---

### LocationProcessor

职责：

- Geolocator Stream 的建立、重启与停止
- 按速度选择 distanceFilter，并按更新频率切换采样参数
- GPS 漂移过滤（近距过滤 + 1 秒间隔下的观察者模式）
- 调用 SearchEngine
- 向 Coordinator 返回 PositionResult 与算法结果（index / distance / bearing）

必须：

- 仅返回算法结果
- 维护长度上限为 3 的采样队列
- 在 locale / 定位间隔 / 采样模式变化时按需重启流

不负责：

- station metadata
- UI
- Notification
- 生命周期
- 权限

SearchEngine 属于 LocationProcessor 的内部依赖。

平台参数：

- Android：`AndroidSettings`，高精度、`intervalDuration`、自适应 distanceFilter、Geolocator 前台服务通知、wake lock
- iOS / macOS：`AppleSettings`，`bestForNavigation`、`otherNavigation`、显示后台定位指示
- 其他平台：`LocationSettings`，高精度

---

### SearchEngine

必须：

- 保持纯算法
- 使用单位球面 XYZ 与 KD-Tree 粗筛
- 距离计算（日本全境及近海区域：等距长方投影；区域外：Haversine）
- 方位角计算

不得：

- 查询 station name
- 查询 gcd
- 查询 metadata 字符串
- 更新 Notification
- 更新 UI

`locate()` 行为：

- 数据未加载或 `count <= 0` 时返回空列表
- 前台且位于日本全境 / 近海轮廓内：粗筛 `count * 2`，精算后取 `count`
- 前台但在轮廓外：粗筛 `count`，精算取 `count`
- 后台 / 非活跃：粗筛至少 `leastCount`（5），精算取 `leastCountInactive`（1）
- 所有情况下粗筛量都不低于 `leastCount`（5）
- 递归深度上限 64；无效索引直接返回

SearchEngine 只负责计算。

---

### StationManager（定义于 `manager/station_manager.dart`）

职责：

- BIN 校验（尺寸 / 结构；加载与写入共用；加载校验失败后回退空实例）
- BIN 加载（documents 优先；读取异常 / 文件不存在回退 assets（示例 / 过时数据））
- BIN 写入（原子替换：临时文件 → 改名）
- XYZ、经纬度
- station metadata（name、gcd）
- `getStationNameByGcd(gcd)`：首次调用构建 gcd → name 缓存，供 HistoryPage 展示站名
- 示例数据判定（`count > 0 && count < sampleThreshold`，阈值 50）
- 加载状态判定（`isLoaded`）

BIN 布局：

- `Float64List`：纬度、经度、X、Y、Z（各 `count` 项）
- `Uint32List`：KD-Tree 左 / 右子节点（各 `mcount` 项）、车站名偏移（`count` 项）
- `Uint8List`：车站名原始数据（变长）
- 尾部 20 字节：root、mcount、count、date、pdate（`date` / `pdate` 为 `yyyyMMdd` 的 `int`，`0` 表示未设置，按 `Date Representation` 处理）

选择规则：

- documents 文件读取成功 → 使用其字节；若校验失败 → 空实例（不回退 assets）
- documents 读取异常 / 文件不存在 → 读取 assets；assets 校验失败 → 空实例

当前消费者：

- HomePage、Coordinator、LocationProcessor、SearchEngine、InfoImportService、InfoDialog、LicenseListDialog、HistoryPage

未来消费者：

- VoronoiRenderer

必须：

- 项目唯一站点数据来源（Single Source of Truth）

不得：

- 搜索
- 定位
- Notification
- UI

---

### EventManager（定义于 `manager/event_manager.dart`）

职责：

- 事件数据校验（NDJSON header `v` / `fields`、数据行是 2 元素整数数组（epoch ms）、start ≤ end；加载与写入共用）
- 事件数据加载（documents 优先；读取失败 / 无效回退空实例）
- 事件数据写入（原子替换：临时文件 → 改名）
- 事件期间判定（当前时间落在任一 period 内，含端点；毫秒精度）

schema：

```text
{"v":2,"fields":["start_epoch","end_epoch"]}
[1777615200000,1780239599000]
```

- 仅 header、无数据行是合法空集合；导入后清空 event。
- 文件缺失 / 无效时视为不在事件期间。
- 当前消费者：Coordinator、HomePage、InfoDialog、LicenseListDialog；`StationCount` 通过注入的判定器消费。

必须：

- 项目唯一事件数据来源

不得：

- 搜索
- 定位
- Notification
- UI

---

### SettingsManager（定义于 `manager/settings_manager.dart`）

职责：

- 保存站点检出数量（`StationCount`）、定位间隔（`LocationInterval`）与历史记录开关
- 通过 SharedPreferences 持久化：

| 键 | 值 |
|---|---|
| `settings_station_count` | `StationCount.index` |
| `settings_location_interval` | `LocationInterval.index` |
| `settings_history_enabled` | bool |
| `settings_history_merge_view` | bool |

- 读取时对越界索引回退默认值（`StationCount.game` / `LocationInterval.s1`）；布尔键缺失回退 false
- `copyWith()` 生成对话框草稿；`save()` 写入全部键
- `processorSettingsManager` 向 LocationProcessor 暴露 `stationCount` / `locationInterval`；`historySettingsManager` 向历史功能暴露 `historyEnabled` / `historyMergeView`，二者均为不可变的命名记录
- `historyEnabled` 控制记录；`historyMergeView` 只控制历史页展示，与记录开关独立
- `fromTransferable()` 位置约定：`data[0]` stationCount、`data[1]` locationInterval、`data[2]` historyEnabled、`data[3]` historyMergeView

默认值：`StationCount.game`、`LocationInterval.s1`、`historyEnabled = false`、`historyMergeView = false`。

---

### NotificationConsumer（定义于 `consumer/notification_consumer.dart`）

职责：

- Flutter Local Notifications 初始化
- Notification 权限（Android；返回值当前恒为 true）
- 作为 Coordinator 的常驻定位结果消费者（前后台均接收），只使用广播 payload，不读取 Coordinator 快照
- show()
- cancelAll()
- changeLocale()：已有结果时强制刷新通知

内部状态：

- 当前语言
- 最近一次定位结果列表
- 最近一次通知的车站（按 `gcd` 判定切换）
- 通知更新锁（单飞）

显示规则：

- 收到 null 结果 → `cancelAll()`
- 最近车站切换 → 取消当前通知后重新显示
- 仅在 `forceUpdate` 或最近车站变化时调用 show
- 静音、无振动、`onlyAlertOnce`、`autoCancel: false`、高 importance / priority
- iOS 不播放声音、不显示 badge

不得：

- 管理 UI
- 管理 GPS
- 查询站点数据
- 持有定位或站点业务的主状态

---

### HistoryConsumer（定义于 `consumer/history_consumer.dart`）

职责：

- 作为 Coordinator 的常驻定位结果消费者（前后台均接收），只使用广播 payload
- 最近车站切换判定：自身持有切换基线，与 NotificationConsumer 的判定相互独立
- 记录总开关（`changeSettings(HistorySettingsManager)`）：false → true 时补记当前通知车站，同站 5 分钟内跳过（读取当天磁盘 + pending 取最新）
- 换日：按定位时间戳判断本地日期变化，变化时丢弃切换基线，使新一天的首个定位可再次记录同一车站
- 记录装配：`gcd` + 坐标 ×1e6 四舍五入 + `PositionResult.timestamp`
- pending 缓冲：记录先进入内存缓冲，不逐条写盘
- 批量落盘触发（两条件先到先触发）：
  - 计数：pending 达到 10 条
  - 时间：自 pending 由空变为非空（0→1）时刻起满 5 分钟
- 时间窗口与上次落盘时刻无关：落盘后 pending 清空即清除窗口起点，下一条记录入队时重新起算；空闲超过 5 分钟后的首条记录仍完整等待 5 分钟，不立即落盘
- `_flushBlockedUntilTimer` 期间不响应计数触发；失败后窗口从失败时刻重新起算，5 分钟后重试
- `flush()`：按日期分组，同一天的多条一次批量追加；成功一组即移除该组记录，遇错停止，保留失败及后续记录
- flush 结束后若 pending 仍非空：达到 10 条时立即再 flush 一次，否则重新按窗口起点计时
- 前后台门控（`changeActive(bool)`）：非活跃期间不递增 `pendingRevision` / `flushCount`，恢复活跃时成对递增，让历史页重取 pending 与磁盘状态
- 进度通知：一次 flush 中只要有写入成功且处于活跃状态，就递增 `flushCount`；历史页直接订阅并重读磁盘
- pending 通知：每次记录进入 pending 且处于活跃状态就递增 `pendingRevision`；历史页据此做增量重建
- 失败重试：失败后不响应阈值触发，只在从失败时刻起算的 5 分钟窗口到期时重试
- 会话复位：收到 `(null, null)`（stop 的 forceNotify）时清空切换基线、缓存的 payload 与已处理时间戳，取消定时器；pending 保留
- 幂等：同一 `PositionResult` 时间戳的重复广播（前台复归时的再放送）不重复处理

内部状态：

- 记录开关
- 活跃状态（`_active`，构造函数传入，`changeActive()` 更新）
- pending 列表（未落盘记录）
- 自身 `flushCount`（`ValueNotifier<int>`，落盘进度）
- 自身 `pendingRevision`（`ValueNotifier<int>`，pending 追加）
- 5 分钟窗口定时器、窗口起点 `_pendingSince`（pending 0→1 时刻）与单飞 flush future
- 失败后暂停阈值触发的标志
- 切换基线（`_hasLastHistory` / `_lastHistoryGcd`）
- 会话日期（`int date`，换日判定）
- 最近一次 payload（开关开启时补记用）
- 最近处理的时间戳（幂等）

约束：

- 以常驻 handler 注册：pending 必须在 active handler 之前更新，否则 UI 会读到不含本条记录的缓冲
- flush 单飞：定时器、阈值、stop / 导出 / 导入可能并发触发，共用同一个 future
- 不持有 Coordinator 引用；`pendingRecords` / `pendingRevision` / `flushCount` 由自身发布，Coordinator 只公开引用
- `pendingRevision` / `flushCount` 受 `changeActive()` 门控：非活跃期间不通知，恢复时成对递增，让页面重取 pending 与磁盘
- 由 Coordinator 公开 `historyConsumer`，HomePage 注入 SettingsDialog → HistoryPage
- 写入失败只记录日志，不抛出
- 当天展示由页面合并 `readDay(int date)` 与 `historyConsumer.pendingRecords`，不假设 pending 覆盖整天

不得：

- 直接通知或刷新 UI
- 修改 SettingsManager / StationManager
- 参与通知显示
- 持有当天完整快照（本类只持有未落盘增量）

---

### BackgroundTask（定义于 `ui/home_page.dart`）

职责：

- 隔离平台返回行为的差异
- 仅在原生 Android 环境注册根路由 `PopScope`
- 定位流程进行中（runningStatus 为 starting/running）时拦截 Android 返回，并经 MethodChannel `name.w57.nearest_station_notification/background_task` 调用 `moveTaskToBack`
- iOS、Web、Windows、macOS、Linux 原样返回 `child`

不负责：

- 保存或判断定位业务状态
- 管理 Coordinator、GPS、Notification 或生命周期清理

---

### InfoImportService（定义于 `service/info_import_service.dart`）

职责：

- 接收 InfoDialog 传入的 zip 文件路径（选择由 UI 负责，Service 不接触文件选择器）
- 解压、读取 `SHA256SUMS` 并校验实际存在的 station / event 文件
- 零字节或读取结果不可用的条目视为不存在；仅对实际存在的文件执行 SHA-256 校验
- 以 `StationManager.validate` / `EventManager.validate` 校验格式
- 原子写入 documents（临时文件 → 改名）并重新加载
- 单飞：`busy` 为 true 时忽略新请求
- 通过 `ValueNotifier<InfoImportResult?> last` 发布 `InfoImportResult.success` / `InfoImportResult.failure`

ZIP 限制与规则：

- 文件大小 > 0 且 ≤ 20 MiB；读取长度必须与文件长度一致
- 条目数 ≤ 100；解压总大小 ≤ 50 MiB；单条目 ≤ 10 MiB
- 仅匹配压缩包根目录的固定文件名：`station_data_xyz.bin`、`event_data.ndjson`、`SHA256SUMS`
- 同名条目重复、校验清单缺失、哈希格式错误或重复列出同一文件 → 无效
- `SHA256SUMS` 支持 `sha256sum` 文本格式（BOM、注释行、`*` 前缀、大小写不敏感）
- 允许仅 station、仅 event 或两者都有

结果模型：

- `InfoImportResult.success({station, event})` / `InfoImportResult.failure(error)`
- 私有构造 + 断言保证成功至少携带一个数据、失败不携带数据
- 写入按文件原子，但不是跨文件事务：若 station 写入成功而 event 写入失败，可能只更新 station

不负责：

- UI、Toast、Coordinator 热加载
- 文件选择（由 InfoDialog 负责）
- 判断当前运行状态

---

### SettingsSaveService（定义于 `service/settings_save_service.dart`）

职责：

- 执行 `SettingsManager.save()`
- 单飞：`busy` 为 true 时忽略新请求
- 通过 `ValueNotifier<SettingsSaveResult?> last` 发布 `SettingsSaveResult.success` / `SettingsSaveResult.failure`
- `SettingsSaveResult` 私有构造 + 断言保证 success / failure 互斥

不负责：

- 对话框编辑草稿
- UI、Toast、Coordinator 热加载

---

### HistoryManager（定义于 `manager/history_manager.dart`）

职责：

- 历史文件存储与查询：`appendRecords()`、`readDay(int date)`、`readMonth(int month)`、`listDays(int month)`、`listMonths()`；日期 / 月份入参与返回值均为 `int`（见 `Date Representation`）
- 由 HistoryConsumer 在 flush 时按日分组调用 `appendRecords()`（10 条 / 首条起算 5 分钟）；不注册定位 handler，不持有当天内存记录
- 不提供单条追加入口：单条写入也走 `appendRecords()`，调用方不感知批大小
- 日文件 `history/YYYYMMDD.ndjson` 创建与追加（新文件先写 header）
- 月度合并：启动时扫描早于当前月的未归档月份；3 日前不归档；3–10 日用一个随机值统一决定；10 日后直接补做
- 月度归档 `history/YYYYMM.zip`（内含 `YYYYMM.ndjson` + `SHA256SUMS`），成功后删除该月日文件
- 读取月份/日期；迟到日文件与月度 ZIP 合并、去重
- 全量备份导出：外层 ZIP 根目录放月度 ZIP、日 NDJSON、`MANIFEST`、`SHA256SUMS`；`createBackup()` 返回写入 `MANIFEST` 的 `exportedAt`（epoch ms），供调用方命名文件
- 备份导入：校验外层/内层 `SHA256SUMS` 与 `MANIFEST`；过往月份仅备份条数更多时覆盖；当前月日 NDJSON 合并去重
- 历史目录创建；目录不可用时历史读取返回空并继续运行
- iOS 对历史目录设置 `NSURLIsExcludedFromBackupKey`（经 MethodChannel，失败仅记录日志）

文件格式：

- 首行 header：`{"v":1,"fields":["gcd","lat_e6","lon_e6","epoch"]}`
- 数据行：`[gcd,lat_e6,lon_e6,epoch]`
- `gcd` 必须为非空整数；坐标 ×1e6 四舍五入；版本只在 header
- 读取时校验 header 的 `v` / `fields`；坏行跳过，不导致崩溃
- 月度 ZIP 与备份外层 ZIP 均无子目录；`SHA256SUMS` 为 `sha256sum` 文本格式

约束：

- 所有写入（`appendRecords` / 月度合并 / 备份 / 导入）共用同一把异步串行锁
- 月度归档使用临时 NDJSON → 临时 ZIP → rename → 删除日文件；失败保留日文件
- 不依赖 Coordinator / HistoryConsumer、SettingsManager、UI 或文件对话框
- `appendRecords()` 对同一天的记录只打开一次日文件、一次写入多行、一次 flush 后关闭，避免逐条 open/close 与多次 fsync
- 写入方法只负责落盘；切换判定、开关状态、补记跳过与批量时机由 HistoryConsumer 负责

不负责：

- 车站切换判定、pending 缓冲、当天记录合并、历史总开关
- UI、Toast、文件对话框
- 5 分钟展示合并（属于历史页）
- 删除月度归档、设置条数上限或清空

---

### HistoryBackupService（定义于 `service/history_backup_service.dart`）

职责：

- 由 HomePage 在 `initState` 创建并持有，生命周期独立于 HistoryPage / SettingsDialog
- 不持有 HistoryManager；`createExport(HistoryManager)` / `import(HistoryManager, path)` 由调用方传入
- 导出：生成外层 ZIP 到临时目录并读取字节，返回 `HistoryBackupExport(bytes, fileName)` 供 HistoryPage 经 `FilePicker.saveFile(bytes:)` 保存；临时文件随即删除。调用前由 HistoryPage 执行 `historyConsumer.flush()`
- 导出文件名：`history-backup-<epoch>.zip`，`<epoch>` 取 `HistoryManager.createBackup()` 返回的 `exportedAt`，与包内 `MANIFEST.exportedAt` 严格相等；临时文件名只用调用时刻的 epoch（随后删除），不要求与最终名一致
- 注意：`FilePicker.saveFile` 需要完整字节，导出时 ZIP 会读入内存；大备份需预留内存与临时空间。
- 导入：接收 HistoryPage 选择的 ZIP 路径，调用 `HistoryManager.importBackup()`；调用前由 HistoryPage 执行 `historyConsumer.flush()`，完成后重载月份/日期
- 单飞：`busy` 为 true 时忽略新请求
- 导出为两阶段：`createExport()` 成功返回 payload 并保持 busy；HistoryPage 保存后调用 `finishExport(savedPath / error)` 发布成功 / 取消 / 失败并释放 busy。导入直接发布结果
- 通过 `ValueNotifier<HistoryBackupResult?> last` 发布成功 / 取消 / 失败；由 HomePage 订阅并统一 Toast，HistoryPage 只订阅 `busy` / `progress`
- 通过 `ValueNotifier<double> progress` 发布 0–1 进度（导出按文件、导入按月份/条目）
- 捕获导出生成 / 导入处理异常并转为失败结果

不负责：

- 历史文件格式、条数比较与写入
- 文件选择 / 保存（由 HistoryPage 负责）
- UI、Toast
- 判断当前运行状态

---

### HistoryPage（定义于 `ui/history_page.dart`）

职责：

- 注入 HistoryConsumer、`HistoryManager`、HistoryBackupService、`StationManager` 与 `HistorySettingsManager`
- 日期 / 月份列表 = 落盘枚举 + pending 记录按自身 `epoch` 推导；列表元素为 `int`（日 `date` / 月 `month`）
- 打开或刷新时不再预载当天历史，直接使用 `historyManager.listMonths()` / `listDays(int month)`
- 订阅 `historyConsumer.flushCount`：落盘推进时重读月份 / 日期列表；非活跃期间 Consumer 不通知，恢复时补发
- 订阅 `historyConsumer.pendingRevision`：pending 追加时重建日期列表；门控在 Consumer，页面只判断 `mounted`
- 单日页：`readDay(int date)` 与 `historyConsumer.pendingRecords` 中该日期的记录按 `key` 去重合并（`HistoryRecord.mergeDedup`）
- 读取失败与 Manager 一致：只 `debugPrint`，保持旧数据或显示空状态，不保留页面级 error，也不显示重试页
- 当天与往期使用同一合并路径，不再区分 live / disk
- 站名：展示时通过 `StationManager.getStationNameByGcd(record.gcd)` 获取；查不到显示 `--`
- 月份导航 `< yyyy-MM >`、日期列表、刷新、日历跳转、备份导出/导入入口
- 默认当前月；下一月在当前月禁用，上一月在最早记录月禁用；月份间隙显示空状态
- 单日页逐条展示（默认）或 5 分钟区块展示（`settingsManager.historyMergeView`）
- 区块按首条记录起算的固定 5 分钟窗口；块内按车站首次出现顺序分组、组内时间升序；最新区块在前
- 每组最多显示 5 行，超出时第 5 行右侧箭头展开/收起
- 导出与导入前均调用 `historyConsumer.flush()`
- 使用 `file_picker` 选择导入 ZIP / 保存导出的 ZIP；导出保存结果经 `historyBackupService.finishExport()` 回报
- 订阅 `HistoryBackupService.busy` / `progress`，显示进度；不订阅 `last`
- 备份操作结束后重载自身月份/日期列表；导入后的 Toast 由 HomePage 负责

不负责：

- 记录触发、切换判定、pending 缓冲、文件写入、备份格式
- 5 分钟记录过滤

---

### Dialogs

- `SettingsDialog`：编辑本地草稿，保存调用 `SettingsSaveService.save(_draft)`；订阅 `busy` 与 `last`，仅刷新自身；不自动关闭；左下「关闭」与 X 同职责；含历史记录区块与历史页入口；由 HomePage 注入 `HistoryConsumer` 并转交 HistoryPage
- `InfoDialog`：显示车站数量 / 版本 / 大小与许可证入口、更新提示、导入按钮；订阅 `busy` 与 `last`，仅刷新自身；不自动关闭。
- `LicenseListDialog`：从 `LicenseRegistry` 聚合许可证，应用条目置底；`count > 0` 时显示车站数据信息；条目打开 `LicenseDetailDialog`。
- `HistoryPage` 为独立路由（非 Dialog）：直接接收 HistoryConsumer、HistoryManager、HistoryBackupService、StationManager 与设置草稿的 `HistorySettingsManager` 视图，未保存也立即生效。
- 所有 Service 操作结果的 Toast（导入 / 设置保存 / 历史备份）由 HomePage 统一显示；HistoryPage 只负责进度等自身 UI。

---

## Entry and Interaction

对话框入口（HomePage AppBar 右侧）：

- settings dialog：设置按钮
- info dialog：info 按钮（最右侧）

入口按钮在 `starting` 中禁用，stopped / running 可用（changeXxx 本身任意状态可调用，禁用仅为既有 UI 策略）。

settings dialog：

- 负责设置项编辑（本地草稿 `_draft`）；保存时调用 `SettingsSaveService.save(_draft)`
- 历史记录区块：记录总开关、5 分钟合并展示 checkbox、打开历史记录入口
- 合并展示 checkbox 与记录总开关独立，始终可编辑；打开历史页时传 `_draft.historySettingsManager`
- 历史页入口接收 Coordinator、HistoryManager、HistoryBackupService 与 StationManager；内容可滚动，避免小屏溢出
- 订阅 `SettingsSaveService.busy`：busy 期间禁用保存按钮；X、关闭按钮、系统返回、点击遮罩均允许关闭
- 订阅 `SettingsSaveService.last` 仅用于刷新自身状态；成功/失败都不自动关闭
- 左下按钮为「关闭」（`dialogClose`），行为与 X 相同（`Navigator.pop`）
- 不执行持久化、不弹 Toast、不接收 `manager` 参数

history page：

- 月份选择 + 日期列表；点击日期进入单日页
- 当天日期与往期单日页都按「磁盘 + pending」合并读取，通过 `historyConsumer.pendingRevision` 触发增量重建、`historyConsumer.flushCount` 触发磁盘重读；门控在 Consumer（非活跃不通知，恢复时成对补发），页面只判断 `mounted`
- 单日页默认按时间倒序逐条展示；合并展示开关开启时按固定 5 分钟区块展示
- AppBar：返回、刷新、日历跳转、备份导出、备份导入
- 备份导出前 `historyConsumer.flush()`；无历史时禁用导出；导入前确认覆盖规则；导入后刷新当天来源并重载
- 导出/导入期间显示进度并禁用入口；文件选择/保存阶段绑定 HistoryPage，进入 Service 的导出/导入处理在页面关闭后继续（Service 由 HomePage 持有）

info dialog：

- 结构：标题行（信息）→ 许可证及车站信息框 → 更新提示框 → 按钮行（关闭 / 导入）
- 许可证框：显示车站数 / 版本（`date`，存在修订时附 `pdate`；均为 `yyyyMMdd` 的 `int`）/ 大小 / 许可证入口，点击打开 `LicenseListDialog`
- 更新提示框：正文提示定期更新车站信息 / 事件信息数据，点击框体打开下载网站（`Common.uriInformation`）
- 链接：点击经 `launchUrl(..., mode: LaunchMode.externalApplication)` 打开系统浏览器
- 导入：按钮先用 `file_picker` 选择 zip，再将路径传给 `InfoImportService.import(path)`；Service 完成解析、SHA-256 / 格式校验、写入与加载
- 导入按钮以 `_picking` 守护选择阶段；订阅 `InfoImportService.busy`，`_picking` 或 busy 期间禁用导入按钮
- 订阅 `InfoImportService.lastResult`：仅刷新自身 bin 信息；成功/失败都不自动关闭
- Toast 由 HomePage 统一显示（成功按实际导入内容，失败为「无效的文件」）
- 不执行写盘、不弹 Toast

---

## Android Task Policy

- `MainActivity` 是应用唯一根 Activity。
- 使用 `singleTask`，桌面入口和通知入口应优先复用同一任务。
- 定位流程进行中（starting/running）按返回键不销毁 Activity，而是调用 Android `moveTaskToBack(true)`。
- 系统杀死进程后的冷启动不恢复旧 Coordinator 状态。
- 使用 Android 默认的应用 task affinity（包名 `name.w57.nearest_station_notification`），不额外设置 `taskAffinity`。
- 声明定位、前台服务、通知与 wake lock 权限；注册 Geolocator 前台服务与通知图标元数据。

---

## Data Model

### StationResult

SearchEngine 输出：

- index
- distance（米）
- bearing（度）

Coordinator 补全：

- name
- gcd

派生显示值：

- `distanceInUnit`：< 1000 m 显示米，否则显示千米
- `bearingIndex`：8 方向枚举

SearchEngine 不解析站名。

### PositionResult

- latitude / longitude / speed / accuracy / heading
- timestamp
- 派生显示值：`speedString`、`accuracyString`、`headingIndex`、`timestampString`、`samplingMode`

### Enums

- `RunningStatus`：stopped / starting / running
- `SamplingMode`：staying（0 m/s，filter 4）/ walking（1 m/s，4）/ cycling（4 m/s，4）/ transit（8 m/s，16）
- `Direction`：staying + 8 方向
- `LocationInterval`：s1（1 s / 1024 ms）/ s3（3 s / 3072 ms）/ s5（5 s / 5120 ms）
- `StationCount`：game（12 + 事件 2 + radar 4 + natsume 2）/ max（20）
- `StationCountPart`：friend / event / radar / natsume

`StationCount.count` 为动态值：`friend + (事件期间 ? event : 0) + radar + natsume`；`part(index)` 与 `label` 随事件期间变化。

### Event Data

见 EventManager 的 schema（v2 NDJSON，epoch ms）。仅 header 表示合法空集合；导入后清空 event。

### HistoryRecord

定义于 `common.dart`，与 `StationResult` / `PositionResult` 同处。

- `gcd`：非空 int（车站 ID）
- `latitudeE6` / `longitudeE6`：经纬度 ×1e6 四舍五入的 int
- `epoch`：`PositionResult.timestamp.millisecondsSinceEpoch`；主开关补记使用开启时刻
- `date`：由 `epoch` 经 `Common` 日期入口得到的本地 `yyyyMMdd` int，供分组、比较、排序与文件名共用；不落盘
- 派生显示值：本地时间 `HH:mm:ss.SSS`、坐标 6 位小数
- 记录键：`(gcd, epoch, latitudeE6, longitudeE6)`，用于合并去重
- 站名不落盘；展示时由 HistoryPage 通过 `StationManager.getStationNameByGcd(gcd)` 查询，查不到显示 `--`

历史 NDJSON：

```text
{"v":1,"fields":["gcd","lat_e6","lon_e6","epoch"]}
[1130101,35681236,139767125,1792686228385]
```

- 文件名使用本地日期：日 `YYYYMMDD`（`$date`）、月 `YYYYMM`（`$month`），由上述 `int` 直接插值，见 `Date Representation`。
- 日文件/月度 NDJSON 同一格式；月度 ZIP 内含 `YYYYMM.ndjson` + `SHA256SUMS`。
- 备份外层 ZIP 根目录直接包含 `YYYYMM.zip`、`YYYYMMdd.ndjson`、`MANIFEST`、`SHA256SUMS`，无子目录。

---

## Result Flow

```text
LocationProcessor
        │  PositionResult + 算法结果
        ▼
Coordinator
        │  补全 station metadata / 维护快照
        ├──► 常驻 handlers（前后台均接收）
        │      ├─ HistoryConsumer：判定后加入 pending，10 条 / 首条起算 5 分钟按日批量落盘
        │      └─ NotificationConsumer：更新系统通知
        └──► active handlers（HomePage，仅前台接收）
                 │
                 ▼
              UI 更新（HistoryPage 另经 Consumer 的 pendingRevision / flushCount 更新）
```

原则：

- Dependency flows downward.
- Results flow upward.

Coordinator 通过 Handler 集合广播定位结果；HomePage 以前台消费者（active: true）触发 setState，NotificationConsumer 与 HistoryConsumer 以常驻消费者分别更新通知与待落盘缓冲。历史页不订阅定位结果，改为订阅 `historyConsumer.pendingRevision` / `flushCount`，按日合并 `HistoryManager.readDay()` 与 `pendingRecords`；门控在 Consumer（`changeActive` 由 Coordinator 转发，非活跃不通知，恢复时成对补发），页面只判断 `mounted`；HistoryManager 不接收定位结果。

LocationProcessor 通过单一的 LocationHandler 向 Coordinator 返回算法结果，再由 Coordinator 补全并广播。

停止流程：Coordinator 先停止 LocationProcessor，等待 `HistoryConsumer.flush()`（pending 全部写入）完成，随后调用 NotificationConsumer.cancelAll()，清空自身定位状态和运行状态，最后以 forceNotify 广播 `(null, null)`，使前台 HomePage 清空列表、HistoryConsumer 复位会话并取消定时器。写入失败的 pending 保留在 HistoryConsumer 中。

启动流程：Coordinator 进入 starting → 请求定位权限与通知权限 → 失败则回到 stopped → 成功且仍为 starting 时启动 LocationProcessor → 首个定位结果到达后进入 running；当天的历史记录先进入 pending，满 10 条或自首条入队起满 5 分钟后按日批量落盘。

---

## Running Status

呈现状态机，UI 只读取，不派生：

```text
stopped ──start()──► starting ──首个定位结果──► running
  ▲                    │                          │
  │◄──── 权限被拒 ──────┘                          │
  │◄──────────────── stop() ───────────────────────┘
```

- `stopped`：初始状态。positionResult / stationResults 为 null，GPS 订阅不存在。
- `starting`：start() 调用后立即进入，覆盖权限请求、GPS 订阅建立、直至首个定位结果到达；期间 UI 仅允许停止操作（取消）。
- `running`：首个定位结果到达时由 Coordinator 在结果回调中升级。

不变式：

- `running ⇔ positionResult != null`（升级与赋值在同一同步块完成；stop() 同步清空）
- `stopped ⇒ GPS 订阅不存在`（stop() 先取消订阅再置状态；start() 在权限等待期间被停止则中断，不建立订阅）
- 停止后到达的延迟定位结果被 Coordinator 丢弃

分工：

- UI 呈现（按钮 / 图标 / 列表占位 / keepBackgroundTask）只读取 RunningStatus。
- 是否重启 GPS 流等控制流由 LocationProcessor 依据自身订阅状态（_positionSubscription）自行判断，UI 层不设状态门控。

---

## Hot Reload

changeXxx 家族（外部事件驱动的状态更新）：

- changeLocale：l10n 更新（系统语言变化；传播至 LocationProcessor 与 NotificationConsumer；已订阅时重启流以刷新前台通知文本）
- changeActive：active 更新（前后台切换；LocationProcessor 切换搜索件数；恢复前台时立即重发缓存结果；进入后台不强制 flush，后台写盘依赖 10 条阈值 / 首条起算的 5 分钟窗口 / stop）
- changeSettings：settings 更新（设置项保存；向 LocationProcessor 传 `processorSettingsManager`、向 HistoryConsumer 传 `historySettingsManager`；定位间隔变化时重启流，数量变化时用最后采样点重算；HistoryConsumer 在关→开时补记当前通知车站）
- changeStationData：站点数据更新（导入）
  - `Coordinator._manager`、`LocationProcessor._manager`、`_engine`（重建为 `SearchEngine(新 manager)`）在同一同步块内成对替换；流不中断、队列不清
  - Coordinator 调用 `LocationProcessor.changeData(...)` 完成换链
  - Dart 单线程保证换链不与在途 fix 交错；索引与站名成对换新；UI 列表与通知在下一个定位点（≤ 采样间隔）刷新
- changeEventData：事件数据更新（导入）
  - Coordinator 将 EventManager 的事件期间判定注入 `StationCount.eventPeriod`
  - 下一次定位 / UI 读取即时生效，无需换链

共通语义：

- 即时生效；任意状态（stopped / starting / running）可调用
- 不打断当前流程
- changeXxx 本身不显示提示；导入 / 设置保存 / 历史备份的结果由 HomePage 在调用 changeXxx 之外统一 Toast

---

## Lifecycle

```text
HomePage
↓
didChangeAppLifecycleState()
↓
解析：paused → active=false / resumed → active=true（inactive 等过渡状态忽略）
↓
Coordinator.changeActive()
↓
由 Coordinator 决定是否转发给需要的模块。
```

HomePage.dispose 时：

- 移除生命周期观察者与 Service 监听
- 释放 InfoImportService / SettingsSaveService / HistoryBackupService
- 移除 Coordinator 的 handler 并调用 `stop()`（等待 pending 写入完成）

当天的历史持久化：

- 记录先进入 HistoryConsumer 的 pending；达到 10 条，或自 pending 0→1 时刻起满 5 分钟后按日批量 `appendRecords()`，成功后从 pending 移除
- 窗口起点与落盘时刻解耦：落盘后 pending 清空即清除起点，下一条入队重新起算，因此空闲后的首条记录不会被立即写出
- 写入失败停止本批，等从失败时刻起算的 5 分钟窗口到期重试；期间进程死亡则 pending 全部丢失（已接受）
- `Coordinator.stop()`、导出前、导入前强制 `flush()`
- 进入后台不强制 flush：未达阈值时后台最多积攒 9 条，进程被杀最多丢失这一窗口内的记录；若写入失败，丢失量以失败窗口为准
- 历史页按日合并 `readDay()` 与 `pendingRecords`；`pendingRevision` / `flushCount` 由 Consumer 在活跃时通知、恢复时补发，页面只判断 `mounted`

---

## Locale

```text
HomePage
↓
Coordinator
↓
需要更新文本的模块
```

- 语言解析采用严格匹配：ja、en、zh-Hans（或 zh-CN），不做语言码级宽松回退，无匹配时回退 en。
- MaterialApp 的 localeListResolutionCallback 与 HomePage.didChangeLocales 共用 L10n.resolve()，保证 UI 与通知的语言判定一致。
- 8 方向标签按语言提供；静止时显示 `--`。

---

## Station Data

### Data Sources and Fallback

- 车站数据文件：`station_data_xyz.bin`（assets 与 documents 同名、路径不同）
  - assets：随应用发布的示例 / 过时数据
  - documents（私有目录）：真实数据，由 InfoImportService 写入
- 事件数据文件：`event_data.ndjson`（documents）；缺失 / 无效时为空（无事件期间）
- station 启动选源：只依据 documents 文件（含此前更新版本）的读取结果——读取成功则使用；读取异常 / 文件不存在回退 assets（示例 / 过时数据）；加载后校验失败（含 assets 数据损坏）回退空实例（静默回退策略）
- event 启动加载：与 StationManager 初始化同阶段；documents 优先，读取失败 / 无效回退空实例（静默）
- station 校验：尺寸 / 结构校验在加载后与写入前执行，复用同一 `validate`
- event 校验：NDJSON header `v` / `fields`、数据行是 2 元素整数数组（epoch ms）、start ≤ end；仅 header 为合法空集合；坏行无效
- event 空集合：仅 header 的 event 文件导入后清空 event；ZIP 不包含 event 文件时不更新 event
- 示例数据判定：`count > 0 && count < 50`

event schema：

```text
{"v":2,"fields":["start_epoch","end_epoch"]}
[1777615200000,1780239599000]
```

### Update Flow

更新（导入）写入必须：

- 先校验（station 复用加载校验 / event NDJSON 校验），再写临时文件
- 原子替换（临时文件 → 改名）；失败不覆盖现有私有文件
- 失败不执行 `Coordinator.changeStationData()` / `Coordinator.changeEventData()`；此前更新过的版本继续生效（从未更新过则仍为 assets / 空）
- 单文件原子；多个文件同时导入时不保证跨文件事务

```text
InfoDialog（`file_picker` 选择 zip）
        │  path
        ▼
InfoImportService.import(path)
        │
        ├─ 解析 zip + SHA256SUMS 校验
        └─ 格式校验（station 复用加载校验 / event NDJSON 校验）
        │
        ▼
原子写 documents（临时文件 → 改名）
        │
        ├─ station → StationManager.load()
        └─ event   → EventManager.load()
        │
        ▼
InfoImportService.last = InfoImportResult.success
        │
        ├─ InfoDialog：仅刷新 bin 信息
        └─ HomePage：Coordinator.changeStationData/changeEventData + setState + Toast
```

设置保存：

```text
SettingsDialog → SettingsSaveService.save(_draft)
        │
        ▼
SettingsManager.save()
        │
        ▼
SettingsSaveService.last = SettingsSaveResult.success / failure
        │
        ├─ SettingsDialog：仅刷新自身状态（不关闭）
        └─ HomePage：setState + Coordinator.changeSettings + Toast
```

历史备份：

```text
HistoryPage（`file_picker` 选择 / 保存）
        │  path / HistoryBackupExport
        ▼
HistoryBackupService.createExport / import
        │
        ▼
HistoryBackupService.last = success / cancelled / failure
        │
        ├─ HistoryPage：busy / progress UI；结束后重载列表
        └─ HomePage：Toast（历史页自行重载）
```

### Hosting

- 真实数据由独立网站提供手动下载（背后为另一个 GitHub Release），下载包为 ZIP，内含 `station_data_xyz.bin` / `event_data.ndjson` / `SHA256SUMS`
- URL 为 `Common.uriInformation` 常量
- 不做自动更新检测与应用内下载

### HomePage Guide

- 仅 stopped 且为示例数据时，在「定位停止中...」下一行显示「当前正在使用示例车站信息。点击右上角的信息按钮查看和更新车站信息。」；导入真实车站数据后消失

---

## History Data

### Storage

```text
<documents>/history/
  20261023.ndjson
  202609.zip
```

- 当天记录先进入 HistoryConsumer 的 pending；达到 10 条或自首条入队起满 5 分钟后，按日期分组批量写入 `history/YYYYMMDD.ndjson`，成功即移出 pending。
- 日期 / 月份在代码中均为 `int`（`date` / `month`），字符串只在拼接路径与扫描目录时出现。
- 已归档月份使用 `history/YYYYMM.zip`，内含 `YYYYMM.ndjson` + `SHA256SUMS`。
- 月度 ZIP 成功后删除该月日文件；迟到日文件由 `readDay` / `readMonth` / `listDays` 合并，下次合并并入月度 ZIP 并删除。
- 历史记录不设条数上限，不删除月度归档，不提供清空。
- 当前只有 v1，不存在旧版历史数据迁移；读取时坏行跳过，坏文件保留并记录日志。

### Write and Archive

- 记录由 HistoryConsumer 判定后进入 pending，批量写入时日文件由 HistoryManager 依 epoch 的本地日期（`date`）选择；同一天的多条在一次 `appendRecords()` 中写入（单次 open / write / flush / close）；新日文件先写 header；pending 清空后取消定时器并清除窗口起点。
- 落盘时机契约：计数阈值 10 条，或时间窗口自 pending 0→1 起算满 5 分钟。窗口不等同于“距上次落盘 5 分钟”，空闲期不产生写盘，空闲后的首条记录完整等待 5 分钟。
- 实现（已落地）：窗口起点为 `_pendingSince`（pending 0→1 时刻）；`_flushPending` 按日分组调用 `appendRecords()`，成功后按引用移除该组记录。
- 月度合并目标：所有早于当前月且未归档的月份（`YYYYMM.zip` 缺失或仍有该月日文件）。
- 调度：3 日前不归档；3–10 日生成一个随机值统一决定所有未归档过往月；10 日后直接补做。
- 合并：读取该月所有日文件与现有月度 ZIP 的 NDJSON，去重、按 epoch 升序；写临时 NDJSON → 临时 ZIP → rename → 删除日文件；失败保留日文件。
- 所有写入与读取使用同一把异步串行锁，避免 append / 归档 / 备份 / 导入相互覆盖。

### Backup and Restore

外层 ZIP（根目录）：

```text
202601.zip
...
202609.zip
20261023.ndjson
MANIFEST
SHA256SUMS
```

- 导出前 HistoryPage 调用 `historyConsumer.flush()`，确保 pending 全部落盘。
- 导出文件名 `history-backup-<epoch>.zip`，其中 `<epoch>` 即同包 `MANIFEST.exportedAt`，两者严格相等（由 `createBackup()` 返回同一个值）。
- `MANIFEST`：`v`、`exportedAt`、`archiveMonths`、`dailyFiles`、`fileCount`（含 MANIFEST 与 SHA256SUMS）；先写 MANIFEST 再生成 `SHA256SUMS`（包含 MANIFEST 行）。
- `SHA256SUMS`：与 station/event 包一致的 `sha256sum` 文本、两个空格、小写 hex；覆盖外层 ZIP 内全部文件。
- 导入先验外层 `SHA256SUMS` 与 `MANIFEST`，拒绝子目录 / 路径穿越 / 重复条目 / 超限条目；使用流式 `InputFileStream` + `decodeStream`。
- 月度 ZIP 先处理：校验内部 `SHA256SUMS` 与 NDJSON；备份条数多于本地该月总条数时覆盖 ZIP 并删除本地该月日文件；否则保留本地。
- 日 NDJSON 后处理：与本地同日文件按记录键合并去重、按 epoch 排序后原子写回。
- 备份中未包含的本地月份保留；失败时已完成的月度覆盖保留，可重试。
- 备份用于设备迁移，不做多设备内容合并。

### System Backup Exclusion

- Android：`backup_rules.xml` / `data_extraction_rules.xml` 排除 `app_flutter/history`（path_provider documents 实际为应用私有 `app_flutter/`）；manifest 增加 `fullBackupContent` / `dataExtractionRules`。
- iOS：`HistoryManager.load()` 创建目录后经 MethodChannel `name.w57.nearest_station_notification/backup` 设置 `NSURLIsExcludedFromBackupKey`；失败仅记录日志。
- 原因：系统备份配额（Android Auto Backup 约 25 MB）远小于历史归档体积，历史备份应通过应用内导出迁移。

---

## Future

未来计划：

- Voronoi 图着色

新增功能应作为定位结果消费者。
不得修改现有职责划分。

定位结果与运行状态通过 Coordinator 的 Handler 扩展：

- addLocationResultHandler() / removeLocationResultHandler()
- addRunningStatusHandler() / removeRunningStatusHandler()

新增消费者不得覆盖既有 Handler。
需要后台消费定位结果的消费者应注册普通 location result received handler。
只需要前台更新的消费者应注册 active location result received handler。

Coordinator 对常驻消费者的控制面调用（`init` / `requestPermissions` / `changeLocale` / `cancelAll`、`changeSettings` / `flush`）是既定模式：数据面走 handler 广播，控制面走 Coordinator 直调；新增消费者沿用该形态。

---

## Refactoring Policy

对于一次已经确定目标的重构：

- 不新增任何设计
- 不改变功能
- 不改变业务逻辑
- 不改变算法
- 不主动优化代码风格
- 不主动统一命名（架构调整除外）
- 不引入新的设计模式
- 不增加新的依赖

新的设计想法：

```text
Discussion
↓
Update architecture.md
↓
下一轮实现
```

设计与实现保持分离。
