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
- NotificationGateway 保持纯通知
- StationManager 是唯一站点数据来源（Single Source of Truth）
- EventManager 是唯一事件数据来源
- Coordinator 只负责协调，不负责业务实现
- 持久化与导入的异步执行从 Dialog 生命周期中解耦（InfoImportService / SettingsSaveService）
- 不为了设计而设计
- 当前项目规模优先保持职责清晰、依赖简单、易维护

---

## Project Layout

| 文件 | 职责 |
|---|---|
| `lib/main.dart` | 应用引导：注入包名、注册 ADDITIONAL_NOTICE 许可证、创建 `StyledToast` / `MaterialApp` |
| `lib/ui/home_page.dart` | 主 UI、生命周期、初始化编排、Service 持有与结果处理、对话框入口、BackgroundTask |
| `lib/coordinator.dart` | 业务流程协调、权限请求、定位结果补全与广播、运行状态机 |
| `lib/location_processor.dart` | GPS 流、采样策略、漂移过滤、SearchEngine 调用 |
| `lib/search_engine.dart` | KD-Tree 最近车站搜索、距离与方位角计算 |
| `lib/manager/station_manager.dart` | 车站 BIN 数据校验、加载、原子写入、按索引访问 |
| `lib/manager/event_manager.dart` | 事件 NDJSON 数据校验、加载、原子写入、事件期间判定 |
| `lib/manager/settings_manager.dart` | `SettingsManager` 模型与 SharedPreferences 持久化 |
| `lib/notification_gateway.dart` | Flutter Local Notifications 封装与业务通知显示 |
| `lib/service/info_import_service.dart` | `InfoImportService`、ZIP 导入解析与校验 |
| `lib/service/settings_save_service.dart` | `SettingsSaveService` |
| `lib/ui/settings_dialog.dart` | 设置对话框 |
| `lib/ui/info_dialog.dart` | 信息对话框 |
| `lib/ui/license_dialog.dart` | 许可证列表与详情对话框 |
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
├── notification_gateway.dart
├── manager/
│   ├── station_manager.dart
│   ├── event_manager.dart
│   └── settings_manager.dart
├── service/
│   ├── info_import_service.dart
│   └── settings_save_service.dart
└── ui/
    ├── home_page.dart
    ├── settings_dialog.dart
    ├── info_dialog.dart
    └── license_dialog.dart
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
  - `InfoImportService` / `SettingsSaveService` 由 HomePage 创建并持有，经命名参数传给对话框；其公开字段为 `final`
  - Widget 为不可变描述，字段公开且 `final`；可变性由配套 `State` 承接
  - 更新「当前状态」类字段时，使用专门的 `changeXxx()` 方法，不通过构造函数重新赋值
  - `start()` / `stop()` 等生命周期方法尽量保持无参数、成对存在，所需状态在构造函数或 `changeXxx()` 中已经就绪

---

## Field Visibility

「构造传参」只约束参数的传递方式，不规定字段可见性。字段可见性按对象类型区分：

- **协调 / 处理类**（`Coordinator`、`LocationProcessor`、`NotificationGateway`）：字段是内部状态，私有且可重新赋值，只能经 `changeXxx()` 等专用方法变更
- **数据快照**（`StationManager`、`EventManager`）：加载后只读；`StationManager` 的数组与元数据、`EventManager` 的期间数据（epoch ms）均不再修改
- **可变设置**（`SettingsManager`）：字段公开可写；对话框使用 `copyWith()` 生成草稿，保存后由 Service 持久化
- **结果服务**（`InfoImportService`、`SettingsSaveService`）：对外暴露 `final ValueNotifier lastResult` 与 `final ValueNotifier<bool> busy`，内部不使用 `changeXxx`
- **UI 组件（Widget）**：字段须 `final` 且公开（`State` 经 `widget.x` 读取）；可变性由配套的 `State` 承接并反映到 UI

---

## Dependency

```text
                        main.dart
                            │
                            ▼
                        HomePage
        ┌───────────────┬───────────────┬───────────────┐
        ▼               ▼               ▼               ▼
   Coordinator   StationManager   EventManager   InfoImportService / SettingsSaveService
        │               ▲               ▲               │
        │               │               │               ▼
        │               │               │        InfoDialog / SettingsDialog
        │               │               │
        ├───────────────┘               │
        │                               │
        ▼                               │
 LocationProcessor ──► SearchEngine ──► StationManager
        │
        ▼
   NotificationGateway

HomePage 另持有 SettingsManager，并将其传入 Coordinator / LocationProcessor；
BackgroundTask 包裹 HomePage（Android only）。
```

约束：

- SearchEngine 是 LocationProcessor 的内部依赖。
- StationManager 是共享 Repository；HomePage、LocationProcessor、SearchEngine、Coordinator、InfoImportService、InfoDialog、LicenseListDialog 均可依赖。
- EventManager 是事件数据来源，独立于定位结果流；HomePage、Coordinator、InfoDialog、LicenseListDialog 可直接依赖。
- Coordinator 通过 `changeEventData` 将事件期间判定注入 `StationCount.eventPeriod`。
- Coordinator 不负责 StationManager / EventManager 的加载与写入实现。
- InfoImportService / SettingsSaveService 不依赖 UI，不直接调用 Coordinator 或 Toast。
- Dialog 只依赖其显示所需的管理器与 Service。

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
- 并行加载 SettingsManager / StationManager / EventManager（`Future.wait`）
- 创建 Coordinator，注册定位结果 / 运行状态 handler，调用 `coordinator.init()`
- 创建并持有 InfoImportService / SettingsSaveService（生命周期跟随 HomePage；dispose 时释放）
- 订阅 Service 结果：导入 / 设置保存的 Toast、Coordinator 热加载与 `setState`
- 设置入口（settings dialog：设置项编辑与保存）
- 站点数据管理入口（info dialog：bin 信息 / 提示 / 导入 / 许可证入口）
- 示例数据引导提示（stopped 且为示例数据时）
- 通过 Coordinator 的 handler 触发 UI 重建，并通过 getter 读取当前结果和运行状态
- 向 BackgroundTask 提供 `Coordinator.runningStatus != RunningStatus.stopped` 的 keepBackgroundTask
- 坐标详情三态显示切换（隐藏 / 经纬度 / 经纬度 + 速度、精度、方向、时刻）
- 初始化失败时 `debugPrint` 并显示错误 Toast

可直接使用：

- StationManager / EventManager（站点信息显示、站点与事件数据管理）
- SettingsManager（站点显示数量、定位间隔）

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
- 创建 LocationProcessor / NotificationGateway，并注册 NotificationGateway 的常驻定位结果 handler
- 注入事件期间判定到 `StationCount.eventPeriod`
- start()
- stop()
- 生命周期转发（changeActive）
- locale 更新（changeLocale）
- settings 更新（changeSettings）
- station data 更新（changeStationData）
- event data 更新（changeEventData）
- 请求定位权限与通知权限
- 接收定位结果、丢弃停止后到达的延迟结果
- 根据 StationManager 补全 station metadata（gcd / name）
- 维护 PositionResult / StationResults / RunningStatus
- 通过 handler 集合广播完整定位结果与运行状态
- 停止时清空状态、取消通知并广播 `(null, null)`

不负责：

- GPS 流实现
- SearchEngine
- StationManager / EventManager 的加载与写入实现
- 本地通知内容与样式
- UI

Coordinator 只负责协调（Coordinate），不负责业务实现（Implement）。

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
- 示例数据判定（`count > 0 && count < sampleThreshold`，阈值 50）
- 加载状态判定（`isLoaded`）

BIN 布局：

- `Float64List`：纬度、经度、X、Y、Z（各 `count` 项）
- `Uint32List`：KD-Tree 左 / 右子节点（各 `mcount` 项）、车站名偏移（`count` 项）
- `Uint8List`：车站名原始数据（变长）
- 尾部 20 字节：root、mcount、count、date、pdate

选择规则：

- documents 文件读取成功 → 使用其字节；若校验失败 → 空实例（不回退 assets）
- documents 读取异常 / 文件不存在 → 读取 assets；assets 校验失败 → 空实例

当前消费者：

- HomePage、Coordinator、LocationProcessor、SearchEngine、InfoImportService、InfoDialog、LicenseListDialog

未来消费者：

- HistoryManager
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

- 保存站点检出数量（`StationCount`）与定位间隔（`LocationInterval`）
- 通过 SharedPreferences 持久化：

| 键 | 值 |
|---|---|
| `settings_station_count` | `StationCount.index` |
| `settings_location_interval` | `LocationInterval.index` |

- 读取时对越界索引回退默认值（`StationCount.game` / `LocationInterval.s1`）
- `copyWith()` 生成对话框草稿；`save()` 写入全部键

默认值：`StationCount.game`、`LocationInterval.s1`。

---

### NotificationGateway（定义于 `notification_gateway.dart`）

职责：

- Flutter Local Notifications 初始化
- Notification 权限（Android；返回值当前恒为 true）
- 作为 Coordinator 的普通定位结果消费者（前后台均接收）
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

- 选择 zip（`file_selector` 单选，扩展名 zip，含 MIME / UTI 过滤）
- 解压、读取 `SHA256SUMS` 并校验实际存在的 station / event 文件
- 零字节或读取结果不可用的条目视为不存在；仅对实际存在的文件执行 SHA-256 校验
- 以 `StationManager.validate` / `EventManager.validate` 校验格式
- 原子写入 documents（临时文件 → 改名）并重新加载
- 单飞：`busy` 为 true 时忽略新请求
- 通过 `ValueNotifier<InfoImportResult?> lastResult` 发布 `InfoImportResult.success` / `InfoImportResult.failure`

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
- 判断当前运行状态

---

### SettingsSaveService（定义于 `service/settings_save_service.dart`）

职责：

- 执行 `SettingsManager.save()`
- 单飞：`busy` 为 true 时忽略新请求
- 通过 `ValueNotifier<SettingsSaveResult?> lastResult` 发布 `SettingsSaveResult.success` / `SettingsSaveResult.failure`
- `SettingsSaveResult` 私有构造 + 断言保证 success / failure 互斥

不负责：

- 对话框编辑草稿
- UI、Toast、Coordinator 热加载

---

### Dialogs

- `SettingsDialog`：编辑本地草稿，保存调用 `SettingsSaveService.save(_draft)`；订阅 `busy` 与 `lastResult`，仅刷新自身；不自动关闭；左下「关闭」与 X 同职责。
- `InfoDialog`：显示车站数量 / 版本 / 大小与许可证入口、更新提示、导入按钮；订阅 `busy` 与 `lastResult`，仅刷新自身；不自动关闭。
- `LicenseListDialog`：从 `LicenseRegistry` 聚合许可证，应用条目置底；`count > 0` 时显示车站数据信息；条目打开 `LicenseDetailDialog`。
- 所有对话框的全局 Toast 由 HomePage 统一显示。

---

## Entry and Interaction

对话框入口（HomePage AppBar 右侧）：

- settings dialog：设置按钮
- info dialog：info 按钮（最右侧）

入口按钮在 `starting` 中禁用，stopped / running 可用（changeXxx 本身任意状态可调用，禁用仅为既有 UI 策略）。

settings dialog：

- 负责设置项编辑（本地草稿 `_draft`）；保存时调用 `SettingsSaveService.save(_draft)`
- 订阅 `SettingsSaveService.busy`：busy 期间禁用保存按钮；X、关闭按钮、系统返回、点击遮罩均允许关闭
- 订阅 `SettingsSaveService.lastResult` 仅用于刷新自身状态；成功/失败都不自动关闭
- 左下按钮为「关闭」（`dialogClose`），行为与 X 相同（`Navigator.pop`）
- 不执行持久化、不弹 Toast、不接收 `manager` 参数

info dialog：

- 结构：标题行（信息）→ 许可证及车站信息框 → 更新提示框 → 按钮行（关闭 / 导入）
- 许可证框：显示车站数 / 版本（date，存在修订时附 pdate）/ 大小 / 许可证入口，点击打开 `LicenseListDialog`
- 更新提示框：正文提示定期更新车站信息 / 事件信息数据，点击框体打开下载网站（`Common.uriInformation`）
- 链接：点击经 `launchUrl(..., mode: LaunchMode.externalApplication)` 打开系统浏览器
- 导入：按钮调用 `InfoImportService.import()`；Service 内部完成 zip 选择、解析、SHA-256 / 格式校验、写入与加载
- 订阅 `InfoImportService.busy`：busy 期间禁用导入按钮
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

---

## Result Flow

```text
LocationProcessor
        │  PositionResult + 算法结果
        ▼
Coordinator
        │  补全 station metadata / 维护状态
        ├──► 常驻 handlers（NotificationGateway 等，前后台均接收）
        │
        └──► active handlers（HomePage，仅前台接收）
                 │
                 ▼
              UI 更新
```

原则：

- Dependency flows downward.
- Results flow upward.

Coordinator 通过 Handler（add/remove 注册与解除）广播结果，不关心具体有哪些消费者；HomePage 以前台消费者（active: true，只在前台收到）更新 UI，NotificationGateway 以常驻消费者（普通 handler，前后台均收到）更新通知。

LocationProcessor 通过单一的 LocationHandler 向 Coordinator 返回算法结果（Coordinator 构造完成后经 setLocationHandler() 注册），再由 Coordinator 补全并广播。

停止流程：Coordinator 先停止 LocationProcessor，再直接调用 NotificationGateway.cancelAll()，清空自身缓存的定位结果和运行状态，最后以 forceNotify 广播 `(null, null)`，使前台 HomePage 清空列表。

启动流程：Coordinator 进入 starting → 请求定位权限与通知权限 → 失败则回到 stopped → 成功且仍为 starting 时启动 LocationProcessor → 首个定位结果到达后进入 running。

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

- changeLocale：l10n 更新（系统语言变化；传播至 LocationProcessor 与 NotificationGateway；已订阅时重启流以刷新前台通知文本）
- changeActive：active 更新（前后台切换；LocationProcessor 切换搜索件数；恢复前台时立即重发缓存结果）
- changeSettings：settings 更新（设置项保存；定位间隔变化时重启流，数量变化时用最后采样点重算）
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
- changeXxx 本身不显示提示；导入 / 设置保存的结果由 HomePage 在调用 changeXxx 之外统一 Toast

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
- 释放 InfoImportService / SettingsSaveService
- 移除 Coordinator 的 handler 并调用 `stop()`

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
HomePage（对话框触发）→ InfoImportService.import()
        │
        ├─ file_selector 选择 zip
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
InfoImportService.lastResult = InfoImportResult.success
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
SettingsSaveService.lastResult = SettingsSaveResult.success / failure
        │
        ├─ SettingsDialog：仅刷新自身状态（不关闭）
        └─ HomePage：setState + Coordinator.changeSettings + Toast
```

### Hosting

- 真实数据由独立网站提供手动下载（背后为另一个 GitHub Release），下载包为 ZIP，内含 `station_data_xyz.bin` / `event_data.ndjson` / `SHA256SUMS`
- URL 为 `Common.uriInformation` 常量
- 不做自动更新检测与应用内下载

### HomePage Guide

- 仅 stopped 且为示例数据时，在「定位停止中...」下一行显示「当前正在使用示例车站信息。点击右上角的信息按钮查看和更新车站信息。」；导入真实车站数据后消失

---

## Future

未来计划：

- History（定位历史记录）
- Voronoi 图着色

新增功能应作为定位结果消费者。
不得修改现有职责划分。

定位结果与运行状态通过 Coordinator 的 Handler 扩展：

- addLocationResultHandler() / removeLocationResultHandler()
- addRunningStatusHandler() / removeRunningStatusHandler()

新增消费者不得覆盖既有 Handler。
需要后台消费定位结果的消费者应注册普通 location result received handler。
只需要前台更新的消费者应注册 active location result received handler。

当前 Coordinator 仍在 changeLocale() 和 stop() 中直接操作 NotificationGateway；是否进一步收敛这条路径，待后续讨论。

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
