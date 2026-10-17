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
- NotificationService 保持纯通知
- StationManager 是唯一站点数据来源（Single Source of Truth）
- Coordinator 只负责协调，不负责业务实现
- 不为了设计而设计
- 当前项目规模优先保持职责清晰、依赖简单、易维护

---

## Constructor Parameter Convention

区分「构造函数传参」与「方法执行时传参」的判断基准：

- **构造函数传参（位置参数 + `this.x` 直接赋值）**：
  - 对象生命周期内代表其依赖关系的值（如回调函数）
  - 判断标准不是「是否会变」，而是「变化的来源是否属于该对象所处的环境状态」；此类值变化后即代表「当前状态」、并被对象内部多处方法读取
  - 例：`l10n`（系统语言变化）、`active`（前后台切换）、`settings`（设置项保存）、`manager`（站点数据管理）均属此类，四者生命周期模式相同：HomePage 初始化产生初值 → 传入 → 运行期间由外部事件驱动变化 → 通知更新
  - 私有字段（下划线开头）不能使用命名参数（Dart 语言限制），故统一使用位置参数

- **方法参数传参**：
  - 与某次具体操作绑定、操作结束后该值即完成使命的数据
  - 不需要被对象在多处内部方法间保存和复用

- 更新「当前状态」类字段时，使用专门的 `changeXxx()` 方法，不通过构造函数重新赋值
- `start()` / `stop()` 等生命周期方法尽量保持无参数、成对存在，所需状态在构造函数或 `changeXxx()` 中已经就绪

---

## Field Visibility

「构造传参」只约束参数的传递方式，不规定字段可见性。字段可见性按对象类型区分：

- **普通/服务类**（如 `Coordinator`、`LocationProcessor`、`NotificationService`）：字段是内部状态，私有且可重新赋值，只能经 `changeXxx()` 等专用方法变更
- **UI 组件（Widget）**：Widget 为不可变描述（immutable），字段须 `final` 且公开（`State` 经 `widget.x` 读取）；可变性由配套的 `State` 承接并反映到 UI

---

## Dependency

```text
                 main.dart
                     │
                     ▼
                 HomePage
                 │      ▲
                 │      │
                 ▼      │
            Coordinator
                 │
        ┌────────┴────────┐
        ▼                 ▼
LocationProcessor   NotificationService
        │
        ▼
 SearchEngine
        │
        ▼
  StationManager
        ▲
        │
        └────────────── HomePage

后台任务适配链：

```text
HomePage
   │
   ▼
BackgroundTask
   │ Android only
   ▼
MainActivity / MethodChannel
```

约束：

- SearchEngine 是 LocationProcessor 的内部依赖。
- StationManager 是共享 Repository；HomePage 可直接依赖（Dialog、站点信息显示、站点数据管理）。
- EventManager 是事件数据来源，独立于定位结果流；HomePage 可直接依赖（初始化、Dialog、事件数据管理）。
- Coordinator 不负责站点数据的加载与写入实现。

---

## Responsibilities

### HomePage

职责：

- UI
- WidgetsBindingObserver
- 生命周期
- locale 更新
- Settings 加载
- 设置入口（settings dialog：设置项编辑与保存）
- StationManager / EventManager 初始化
- 站点数据管理入口（info dialog：bin 信息 / 提示 / 导入 / 许可证入口）
- 真实数据获取引导提示（stopped 且为示例数据时）
- 创建并持有 Coordinator
- 通过 Coordinator 的 handler 触发 UI 重建，并通过 getter 读取当前结果和运行状态
- 向 BackgroundTask 提供 Coordinator.runningStatus != RunningStatus.stopped 的状态（starting/running 时保持后台任务）

可直接使用：

- StationManager / EventManager（站点信息显示、站点与事件数据管理）

不负责：

- GPS
- 搜索
- Notification
- 权限

---

### Coordinator

职责：

- 协调业务流程
- start()
- stop()
- 生命周期转发（changeActive）
- locale 更新（changeLocale）
- settings 更新（changeSettings）
- station data 更新（changeData）
- 接收定位结果
- 根据 StationManager 补全 station metadata
- 广播完整定位结果

不负责：

- GPS
- SearchEngine
- StationManager 的加载与写入实现
- Notification
- UI

Coordinator 只负责协调（Coordinate），不负责业务实现（Implement）。

---

### LocationProcessor

职责：

- Geolocator Stream
- 定位过滤
- 调用 SearchEngine

必须：

- 仅返回算法结果

不负责：

- station metadata
- UI
- Notification
- 生命周期
- 权限

SearchEngine 属于 LocationProcessor 的内部依赖。

---

### SearchEngine

必须：

- 保持纯算法
- XYZ 初筛
- 距离计算
- 方位角计算

不得：

- 查询 station name
- 查询 gcd
- 查询 metadata
- 更新 Notification
- 更新 UI

SearchEngine 只负责计算。

---

### StationManager

职责：

- BIN 校验（尺寸 / 结构；加载与写入共用；加载校验失败后回退空实例）
- BIN 加载（documents 优先；读取失败 / 文件不存在回退 assets（示例 / 过时数据））
- BIN 写入（原子替换：临时文件 → 改名）
- XYZ
- 经纬度
- station metadata（name、gcd）

当前消费者：

- HomePage
- SearchEngine
- Coordinator

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

### EventManager

职责：

- 事件数据校验（JSON 可解析 / periods 数组 / start ≤ end；加载与写入共用）
- 事件数据加载（documents 优先；读取失败 / 无效回退空实例）
- 事件数据写入（原子替换：临时文件 → 改名）
- 事件期间判定

事件期间判定在加载时注入给 StationCount，使 StationCount 不直接依赖 EventManager。

当前消费者：

- StationCount

必须：

- 项目唯一事件数据来源

不得：

- 搜索
- 定位
- Notification
- UI

---

### NotificationService

职责：

- Flutter Local Notifications 初始化
- Notification 权限
- 作为 Coordinator 的普通定位结果消费者
- show()
- cancelAll()

不得：

- 管理 UI
- 管理 GPS
- 查询站点数据
- 持有业务逻辑

NotificationService 不拥有定位或站点业务的主状态，但会持有通知显示所需的内部状态：当前语言、最近一次站点结果、通知更新锁及最近结果缓存。
定位结果通常通过 handleLocationResultReceived() 进入 NotificationService；Coordinator 当前仍直接调用其 cancelAll() 和 changeLocale()。NotificationService.changeLocale() 在已有结果时负责刷新通知。
收到定位结果时 show()，收到 null 结果时 cancelAll()。

---

### BackgroundTask

职责：

- 隔离平台返回行为的差异
- 仅在原生 Android 环境注册根路由 `PopScope`
- 定位流程进行中（runningStatus 为 starting/running）时拦截 Android 返回，并请求 Android 将任务移至后台
- iOS、Web、Windows、macOS、Linux 原样返回 `child`

不负责：

- 保存或判断定位业务状态
- 管理 Coordinator、GPS、Notification 或生命周期清理

---

## Entry and Interaction

对话框入口（HomePage AppBar 右侧）：

- settings dialog：设置按钮
- info dialog：info 按钮（最右侧）

入口按钮在 `starting` 中禁用，stopped / running 可用（changeXxx 本身任意状态可调用，禁用仅为既有 UI 策略）。

settings dialog：

- 只负责设置项（无分隔线、保存按钮行位于最下方）；不接收 `manager` 参数

info dialog：

- 结构：标题行 → 许可证框 → 提示框 → 状态行（有内容时）→ 按钮行（取消 / 导入）
- 许可证框：小节标签 + bin 信息（车站数 / 大小 / 版本 = date）与许可证入口，点击打开 `LicenseListDialog`
- 提示框：与许可证框同外观（带小节标签）；正文提示定期更新车站数据 / 事件数据；点击框体打开下载网站（`Common` 常量）
- 链接：点击经 `launchUrl(..., mode: LaunchMode.externalApplication)` 打开系统浏览器
- 导入：`file_selector` 单选（限 bin / json）；按内容路由（station 走 `StationManager.validate`，event 走 JSON 校验，无法识别视为无效）；成功后状态行提示导入的是哪一边，失败显示红色文案

---

## Android Task Policy

- `MainActivity` 是应用唯一根 Activity。
- 使用 `singleTask`，桌面入口和通知入口应优先复用同一任务。
- 定位流程进行中（starting/running）按返回键不销毁 Activity，而是调用 Android `moveTaskToBack(true)`。
- 系统杀死进程后的冷启动不恢复旧 Coordinator 状态。
- 使用 Android 默认的应用 task affinity（包名 `name.w57.nearest_station_notification`），不额外设置 `taskAffinity`。

---

## Data Model

### StationResult

SearchEngine 输出：

- index
- distance
- bearing

Coordinator 补全：

- name
- gcd

SearchEngine 不解析站名。

---

## Result Flow

```text
LocationProcessor
        │
        ▼
Coordinator
        │
        ├──► StationManager
        │        补全 station metadata
        │
        ├──► HomePage
        │        更新 UI
        │
        └──► NotificationService
                 更新通知
```

原则：

- Dependency flows downward.
- Results flow upward.

Coordinator 通过 Handler（add/remove 注册与解除）广播结果，不关心具体有哪些消费者；HomePage 以前台消费者（active: true，只在前台收到）更新 UI，NotificationService 以常驻消费者（普通 handler，前后台均收到）更新通知。

LocationProcessor 通过单一的 LocationHandler 向 Coordinator 返回算法结果（Coordinator 构造完成后经 setLocationHandler() 注册），再由 Coordinator 补全并广播。

停止流程：Coordinator 先停止 LocationProcessor，再直接调用 NotificationService.cancelAll()，清空自身缓存的定位结果和运行状态，最后广播 (null, null)，使前台 HomePage 清空列表。

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

分工：

- UI 呈现（按钮 / 图标 / 列表占位 / keepBackgroundTask）只读取 RunningStatus。
- 是否重启 GPS 流等控制流由 LocationProcessor 依据自身订阅状态（_positionSubscription）自行判断，UI 层不设状态门控。

---

## Hot Reload

changeXxx 家族（外部事件驱动的状态更新）：

- changeLocale：l10n 更新（系统语言变化；传播至 LocationProcessor 与 NotificationService）
- changeActive：active 更新（前后台切换；LocationProcessor 切换搜索件数）
- changeSettings：settings 更新（设置项保存）
- changeData：站点数据更新（导入）
  - `Coordinator._manager`、`LocationProcessor._manager`、`_engine`（重建为 `SearchEngine(新 manager)`）在同一同步块内成对替换；流不中断、队列不清
  - Dart 单线程保证换链不与在途 fix 交错；索引与站名成对换新；UI 列表与通知在下一个定位点（≤ 采样间隔）刷新

共通语义：

- 即时生效；任意状态（stopped / starting / running）可调用
- 不打断当前流程
- 无任何提示（SnackBar 等）

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

---

## Station Data

### Data Sources and Fallback

- 车站数据文件：`station_data_xyz.bin`（assets 与 documents 同名、路径不同）
  - assets：随应用发布的示例 / 过时数据
  - documents（私有目录）：真实数据，由导入写入
- 事件数据文件：`event_data.json`（documents）；缺失 / 无效时为空（无事件期间）
- station 启动选源：只依据 documents 文件（含此前更新版本）的读取结果——读取成功则使用；读取异常 / 文件不存在回退 assets（示例 / 过时数据）；加载后校验失败（含 assets 数据损坏）回退空实例（静默回退策略）
- event 启动加载：与 StationManager 初始化同阶段；documents 优先，读取失败 / 无效回退空实例（静默）
- station 校验：尺寸 / 结构校验在加载后与写入前执行，复用同一 `validate`
- event 校验：JSON 可解析、`periods` 为数组、各元素 `start` / `end` 为可解析的本地时间且 start ≤ end、空数组合法

event schema：

```json
{"periods": [{"start": "2026-05-01T15:00:00", "end": "2026-05-31T23:59:59"}]}
```

### Update Flow

更新（导入）写入必须：

- 先校验（station 复用加载校验 / event JSON 校验），再写临时文件
- 原子替换（临时文件 → 改名）；失败不覆盖现有私有文件
- 失败不执行 `Coordinator.changeData()` / 不刷新 event 内存；此前更新过的版本继续生效（从未更新过则仍为 assets / 空）

```text
info dialog（导入）获取字节
        │
        ▼
校验（station 复用加载校验 / event JSON 校验）
        │
        ▼
原子写 documents（临时文件 → 改名）
        │
        ├─ station → StationManager.load()
        │              │
        │              ▼
        │        info dialog 刷新 bin 信息 + 回调 HomePage
        │              │
        │              ▼
        │        Coordinator.changeData() + HomePage setState
        │
        └─ event → 刷新内存 periods（即时生效）
```

### Hosting

- 真实数据由独立网站提供手动下载（背后为另一个 GitHub Release），页面提供 `station_data_xyz.bin` / `event_data.json` 两个文件
- URL 为 `Common` 常量

### HomePage Guide

- 仅 stopped 且为示例数据时，在「定位停止中」下一行显示引导提示；导入真实车站数据后消失

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

当前 Coordinator 仍在 changeLocale() 和 stop() 中直接操作 NotificationService；是否进一步收敛这条路径，待后续讨论。

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
