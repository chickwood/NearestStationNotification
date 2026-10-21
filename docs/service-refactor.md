# Service 化改造计划（Save / Import）

> 状态：已实现
>
> 目标：把 save/import 的异步执行与结果从 Dialog 生命周期中移出，由 HomePage 持有的 Service 执行；Toast 由 HomePage 显示；Dialog 订阅 Service 结果以刷新自身显示。

---

## 0. 定案摘要

| 项 | 定案 |
|---|---|
| Service 形态 | 拆分为 `InfoService` + `SettingsService` |
| 持有层级 | HomePage 创建并持有，`dispose` 释放 |
| 单飞 | 各自独立 `busy`；busy 为 true 时忽略新请求 |
| 结果通道 | 各自 `ValueNotifier lastResult`；订阅时忽略订阅前的旧值 |
| 成功后对话框 | 保存、导入成功都不关闭 |
| busy 时关闭 | X、关闭按钮、系统返回、点击遮罩全部允许 |
| 保存失败提示 | 与导入一致：Toast，红色；成功也 Toast |
| 关闭按钮 | 取消 → `dialogClose`（与 X 同职责），删除 `settingsCancel` |

---

## 1. 改造前现状

- `InfoDialog._import()` 在对话框内完成 zip 选择、解压、SHA-256、写入、`StationManager.load` / `EventManager.load`，然后调用 `onImported`。
- `SettingsDialog._save()` 在对话框内完成 `_draft.save()`，成功后关闭并调用 `onSaved`。
- `HomePage._showInfoDialog` / `_showSettingsDialog` 通过回调接收结果，执行 `Coordinator.changeStationData` / `changeEventData` / `changeSettings` 与 `setState`。
- Toast 由 `InfoDialog._showToast` / `HomePage._showToast` 通过应用级 `flutter_styled_toast` 显示。
- 当前问题：异步操作绑定在对话框 State 上；操作进行中关闭对话框会导致“磁盘已更新、内存未同步”。

---

## 2. 目标结构

```text
HomePage
  ├─ 持有 InfoService / SettingsService（生命周期跟随 HomePage）
  ├─ 订阅结果：Toast + Coordinator 热加载 + setState
  ├─ SettingsDialog(settings, settingsService)
  └─ InfoDialog(stationManager, eventManager, infoService)

InfoService
  ├─ import()        // 选择 zip → 解析 → SHA-256 → 写入 → load
  ├─ busy / lastResult
  └─ success / failure

SettingsService
  ├─ save()     // Settings.save()
  ├─ busy / lastResult
  └─ success / failure

Dialog
  ├─ 触发 service.import() / service.save(draft)
  ├─ 订阅结果：仅更新自身显示（bin 信息 / 自身状态），不关闭
  └─ 不再执行持久化 / 导入写盘 / 全局 Toast
```

### 结果模型（实现）

```dart
class InfoImportResult {
  final StationManager? station;
  final EventManager? event;
  final Object? error;

  const InfoImportResult._({this.station, this.event, this.error});
  factory InfoImportResult.success({...}) => ...;
  factory InfoImportResult.failure(Object error) => ...;

  bool get succeeded => error == null;
}

class SettingsSaveResult {
  final Settings? settings;
  final Object? error;

  const SettingsSaveResult._({this.settings, this.error});
  factory SettingsSaveResult.success(Settings settings) => ...;
  factory SettingsSaveResult.failure(Object error) => ...;

  bool get succeeded => error == null;
}
```

私有构造函数 + `success` / `failure` 工厂保证成功与失败互斥；`InfoImportResult` 的断言同时保证 success 至少带 station / event 之一、failure 不带数据。

Service 对外暴露：

- `ValueNotifier<InfoImportResult?> lastResult` / `ValueNotifier<SettingsSaveResult?> lastResult`；
- `ValueNotifier<bool> busy`；
- `Future<void> import()`；
- `Future<void> save(Settings settings)`；
- `void dispose()`。

订阅方在 `initState` 记录订阅时的 `lastResult.value`，只响应该值之后的新结果；HomePage 在 `initState` 即订阅，因此不会漏掉任何新结果。

---

## 3. 任务列表

1. **在 `lib/info_dialog.dart` 内定义 `InfoService`**
   - 定义 `InfoImportResult`（私有构造 + `success` / `failure` 工厂 + `succeeded`）。
   - 持有 `ValueNotifier<InfoImportResult?> lastResult`、`ValueNotifier<bool> busy`。
   - 实现 `import()`：`file_selector`、zip 解压、`SHA256SUMS` 校验、`StationManager.write/load`、`EventManager.write/load`。
   - 单飞：`busy` 为 true 时忽略并返回。
   - 异常转为 `InfoImportResult.failure`，`debugPrint` 细节，不直接显示 UI。

2. **在 `lib/settings_dialog.dart` 内定义 `SettingsService`**
   - 定义 `SettingsSaveResult`（私有构造 + `success` / `failure` 工厂 + `succeeded`）。
   - 持有 `ValueNotifier<SettingsSaveResult?> lastResult`、`ValueNotifier<bool> busy`。
   - 实现 `save(Settings)`：`await settings.save()`。
   - 单飞与异常处理同 `InfoService`。

3. **迁移 zip 处理逻辑**
   - 把 `info_dialog.dart` 中的 `_parseImportArchive`、`_ImportArchive`、`_InvalidImportException`、`_readUniqueEntry`、`_verifyChecksum`、`_lookupChecksum` 保留在 `info_dialog.dart`，与 `InfoService` 同文件。
   - `InfoDialog` 不再 import `archive` / `crypto` / `dart:typed_data` / `dart:io` / `file_selector`。

4. **改造 `InfoDialog`**
   - 构造函数改为 `InfoDialog(stationManager, eventManager, {required this.infoService})`。
   - Import 按钮调用 `infoService.import()`，按 `busy` 置灰。
   - 订阅 `infoService.lastResult`：`result.succeeded` 时更新 bin 信息；不弹 Toast。
   - `dispose` 取消订阅。
   - 删除 `onImported` 与对话框内全部导入写盘逻辑。

5. **改造 `SettingsDialog`**
   - 构造函数改为 `SettingsDialog(settings, {required this.settingsService})`。
   - Save 调用 `settingsService.save(_draft)`，按 `busy` 置灰。
   - 成功/失败都不关闭对话框；订阅结果仅刷新自身状态。
   - 删除 `onSaved`、`_saving` 与 `_draft.save()`。

6. **改造 `HomePage`**
   - `late final InfoService _infoService; late final SettingsService _settingsService;` 在 `initState` 创建并订阅。
   - `dispose` 取消订阅并释放 Service。
   - 结果处理：
      - `InfoImportResult.success`：`changeStationData/changeEventData` + `setState` + 按实际内容 Toast。
      - `InfoImportResult.failure`：红色「无效的文件」Toast。
      - `SettingsSaveResult.success`：`setState(_settings)` + `changeSettings` + `settingsSaveSucceeded` Toast。
      - `SettingsSaveResult.failure`：红色 `settingsSaveFailed` Toast。
   - `_showInfoDialog` / `_showSettingsDialog` 传入 Service，移除 `onImported` / `onSaved` 回调。

7. **l10n**
   - 新增 `dialogClose`、`settingsSaveSucceeded`、`settingsSaveFailed`。
   - 删除 `settingsCancel`。

8. **文档同步**
   - `docs/architecture.md`：InfoService / SettingsService、HomePage 订阅、Dialog 职责、Update Flow、Toast 归属。
   - `docs/station-data-refactor.md`：导入流程、按钮文案、变更文件清单、测试项。

9. **测试**
   - 仅 bin、仅 event、两者都有的 zip。
   - 错误 zip、缺失/错误 `SHA256SUMS`、格式非法。
   - 导入进行中关闭对话框：结果仍由 HomePage 接收并 Toast/热加载。
   - 保存进行中关闭对话框：设置仍持久化，HomePage 收到结果并更新。
   - 保存成功/失败 Toast 与导入同配色；保存、导入成功后对话框都不关闭。
   - 重复点击 Save/Import：Service 单飞生效。
   - HomePage 销毁/重建：Service 生命周期与订阅正确释放。

---

## 4. Toast 是否会被 Dialog 遮挡/覆盖

### 结论

使用当前 `flutter_styled_toast` 的应用级 `StyledToast`（`main.dart` 包住 `MaterialApp`）时，**HomePage 显示的 Toast 不会被 Dialog 遮挡**，因为 Toast 渲染在应用级 Overlay 上，层级高于 Navigator 的 Dialog 路由。它可能在视觉上覆盖 Dialog 的内容，但不会被 Dialog 盖住。

### 原因

- `main.dart` 中 `StyledToast(child: MaterialApp(...))` 位于 `MaterialApp` 外层。
- `showToast` 使用该应用级 Overlay 的 context，Toast 条目插入到 Dialog 路由之上。
- 当前 HomePage `_showToast` 正是调用应用级 `showToast`，因此 Toast 在 Dialog 之上。

### 对比

- 若改用 `ScaffoldMessenger.of(context).showSnackBar`，SnackBar 属于 HomePage 的 Scaffold，位于 Dialog 路由**之下**，会被模态遮罩压暗/遮挡。
- 若 Toast 只在 Dialog 内用局部 Overlay 显示，则它属于 Dialog 生命周期，关闭后无法继续提示。

### 可能的处理方式

1. **保持应用级 `showToast`（推荐）**：层级正确，Dialog 关闭后仍可显示。
2. **调整 Toast 位置**：当前默认位置在屏幕底部；若 Dialog 居中且 Toast 在中心，可能覆盖 Dialog 内容。可改为顶部/底部，或在结果返回时选择不与 Dialog 重叠的位置。
3. **避免重复提示**：HomePage 负责全局 Toast；Dialog 订阅结果只更新自身显示，不再调用 Toast，避免两层提示。
4. **若确实需要“Dialog 内提示”**：使用 Dialog 内 `OverlayPortal`/`Stack`，但那是 Dialog 生命周期内的提示，不能替代 HomePage 的全局结果提示。

---

## 5. 开放问题（已定案）

| # | 问题 | 定案 |
|---|---|---|
| 1 | Service 命名 | 拆分为 `InfoService` + `SettingsService` |
| 2 | 单飞策略 | busy 时忽略新请求 |
| 3 | `lastResult` 类型 | `ValueNotifier`，订阅方忽略订阅前的旧值 |
| 4 | 成功后对话框 | 保存、导入成功都不关闭；取消改为「关闭」 |
| 5 | busy 时关闭 | X、关闭按钮、系统返回、点击遮罩全部允许 |
| 6 | 失败提示 | 保存成功/失败都 Toast，配色与导入一致；新增 `settingsSaveSucceeded` / `settingsSaveFailed` |
| 7 | 持有层级 | HomePage 持有（当前 HomePage 生命周期≈应用；后台驻留不销毁） |

---

## 6. 风险与注意事项

- Service 由 HomePage 持有时，HomePage 销毁会丢失结果；当前以 HomePage 生命周期≈应用为前提接受该风险。
- `BackgroundTask` 只是 Android 返回键包装，不持有 Service，也不改变 Service 层级选择。
- Dialog 订阅必须在 `dispose` 取消，避免泄漏。
- 只有 HomePage 负责 Coordinator 热加载与 Toast，Dialog 只刷新本地显示，避免重复。
- 导入结果中的 `StationManager` / `EventManager` 是已加载实例，HomePage 直接用于热加载，不需要再次 `load`。
- `flutter_styled_toast` 的应用级 Overlay 是 Toast 能盖在 Dialog 之上的前提，不要改成 `ScaffoldMessenger`。
