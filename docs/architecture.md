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
  - 会随外部事件变化、但变化后即代表「当前状态」、且被对象内部多处方法读取的值
  - 判断标准不是「是否会变」，而是「变化的来源是否属于该对象所处的环境状态」
  - 例：`l10n`（系统语言变化）、`active`（前后台切换）、`settings`（设置弹窗保存）、`manager`（初始资源）均属此类，四者生命周期模式相同：HomePage 初始化产生初值 → 传入 → 运行期间由外部事件驱动变化 → 通知更新
  - 私有字段（下划线开头）不能使用命名参数（Dart 语言限制），故统一使用位置参数

- **方法参数传参**：
  - 与某次具体操作绑定、操作结束后该值即完成使命的数据
  - 不需要被对象在多处内部方法间保存和复用

- 更新「当前状态」类字段时，使用专门的 `changeXxx()` 方法，不通过构造函数重新赋值
- `start()` / `stop()` 等生命周期方法尽量保持无参数、成对存在，所需状态在构造函数或 `changeXxx()` 中已经就绪

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
- StationManager 是共享 Repository。
- HomePage 可直接依赖 StationManager（Dialog、站点信息显示）。
- Coordinator 不负责站点数据的加载实现。

---

## Responsibilities

### HomePage

职责：

- UI
- WidgetsBindingObserver
- 生命周期
- locale 更新
- Settings 加载
- StationManager 初始化
- 创建并持有 Coordinator
- 通过 Coordinator 的 handler 触发 UI 重建，并通过 getter 读取当前结果和运行状态
- 向 BackgroundTask 提供 Coordinator.runningStatus == RunningStatus.running 的状态

可直接使用：

- StationManager（站点信息显示）

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
- 生命周期转发
- locale 更新
- settings 更新
- 接收定位结果
- 根据 StationManager 补全 station metadata
- 广播完整定位结果

不负责：

- GPS
- SearchEngine
- StationManager 的加载实现
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

- BIN 加载
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

---

### BackgroundTask

职责：

- 隔离平台返回行为的差异
- 仅在原生 Android 环境注册根路由 `PopScope`
- 定位运行时拦截 Android 返回，并请求 Android 将任务移至后台
- iOS、Web、Windows、macOS、Linux 原样返回 `child`

不负责：

- 保存或判断定位业务状态
- 管理 Coordinator、GPS、Notification 或生命周期清理

---

## Android Task Policy

- `MainActivity` 是应用唯一根 Activity。
- 使用 `singleTask`，桌面入口和通知入口应优先复用同一任务。
- 定位运行时按返回键不销毁 Activity，而是调用 Android `moveTaskToBack(true)`。
- 系统杀死进程后的冷启动不恢复旧 Coordinator 状态。
- 使用 Android 默认的应用 task affinity（包名 `name.w57.nearest_station_notification`），不额外设置 `taskAffinity`。

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

Coordinator 通过事件处理器（Event Handler）广播结果。
Handler 通过 add/remove 注册与解除。
Coordinator 不关心具体有哪些 Handler。
HomePage 作为前台消费者监听定位结果并更新 UI。
NotificationService 作为常驻消费者监听定位结果并更新通知。

LocationProcessor 内部通过单一的 LocationHandler 向 Coordinator 返回算法结果；Coordinator 在构造完成后通过 setLocationHandler() 注册该 handler，再将补全后的结果广播给多个消费者。
HomePage 注册 active: true，只在前台收到定位结果；NotificationService 注册普通 handler，因此前后台都能收到结果。

停止流程：Coordinator 先停止 LocationProcessor，再直接调用 NotificationService.cancelAll()，清空自身缓存的定位结果和运行状态，最后广播 (null, null)，使前台 HomePage 清空列表。

---

## Lifecycle

```text
HomePage
↓
didChangeAppLifecycleState()
↓
Coordinator.onLifecycleChanged()
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

## Workflow

固定流程：

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
