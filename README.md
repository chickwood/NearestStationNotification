# Nearest Station Notification

> Locates the nearest station based on the current position.

无论距离远近，应用都会持续搜索物理距离最近的车站，并在最近车站发生变化时更新通知。

## 面向用户

- 始终指向当前物理距离最近的车站，不设固定搜索半径。
- 最近车站发生变化时更新业务通知。
- 业务通知默认无声、无振动，并保持显示。
- 支持简体中文、日语和英语，默认跟随系统语言。
- 支持前台和后台定位；后台运行需要系统授予相应的定位权限。

通知当前显示最近车站名称和线路信息（gcd）。距离计算结果主要用于应用内车站列表和排序。

## 项目结构

```text
nearest_station_notification/
├── lib/
│   ├── common.dart                 # 共用模型、枚举与工具函数
│   ├── coordinator.dart             # 业务协调、状态保存与结果分发
│   ├── home_page.dart               # 主页面和生命周期处理
│   ├── l10n.dart                    # 多语言文本
│   ├── licenses_dialog.dart         # 许可证列表及详情
│   ├── location_processor.dart      # GPS 流、漂移过滤和搜索调用
│   ├── main.dart                    # Flutter 入口
│   ├── notification_service.dart   # 本地通知服务
│   ├── search_engine.dart           # 最近车站搜索算法
│   ├── settings.dart                # 设置持久化
│   ├── settings_dialog.dart         # 设置对话框
│   └── station_manager.dart         # BIN 站点数据管理
├── assets/
│   ├── icon/                       # 应用图标源文件
│   └── station_data_xyz.bin        # 站点数据
├── android/                        # Android 原生配置和资源
├── ios/                            # iOS 原生配置和 AppIcon
├── docs/architecture.md            # 当前架构契约
└── pubspec.yaml
```

`LICENSE`、`ADDITIONAL_NOTICE` 和站点数据会作为 Flutter asset 加载。应用桌面图标由 `flutter_launcher_icons` 根据 `assets/icon/` 生成；Android 通知使用单独的 `ic_notification` 资源。

## 核心流程

```text
Geolocator GPS Stream
        ↓
LocationProcessor
  漂移过滤 + SearchEngine.locate()
        ↓ 单一 LocationHandler
Coordinator
  补全站点名称和 gcd，保存当前结果
        ↓ 多个 Handler
  ┌───────────────┬────────────────────┐
  ↓               ↓                    ↓
HomePage      NotificationService   未来消费者
```

`LocationProcessor` 只向 `Coordinator` 输出算法结果。它在构造完成后通过 `setLocationHandler()` 设置唯一的结果处理函数。

`Coordinator` 对外提供多消费者 Handler：

- `addLocationResultHandler()` / `removeLocationResultHandler()`：定位结果分发。
- `addRunningStatusHandler()` / `removeRunningStatusHandler()`：运行状态分发。
- 定位结果 Handler 使用 `Set` 管理，重复注册不会产生重复通知。
- `HomePage` 使用 active 模式，只在前台接收定位结果。
- `NotificationService` 使用普通模式，前后台都接收定位结果。

HomePage 不复制定位结果或运行状态，而是通过 `Coordinator` 的 getter 读取当前状态。停止时 Coordinator 停止定位、取消通知、清空结果，并向前台消费者发送空结果。

## 搜索算法

`SearchEngine` 使用两阶段搜索：

1. 使用弦长平方距离和 KD-Tree 对候选站点进行粗筛。
2. 根据区域选择距离公式，对候选站点进行精算、排序。

日本全境及近海区域使用等距长方投影近似距离，区域外使用 Haversine 大圆距离。站点坐标和 KD-Tree 数据由 `StationManager` 从 BIN 文件加载，搜索算法本身不负责解析站名和其他 metadata。

## GPS 流处理

`LocationProcessor` 根据速度动态调整 GPS 采样策略：

| 模式 | 速度阈值 | distanceFilter |
|------|----------|----------------|
| 静止 | < 1 m/s | 4 m |
| 步行 | ≥ 1 m/s | 4 m |
| 骑行 | ≥ 4 m/s | 4 m |
| 乘车 | ≥ 8 m/s | 16 m |

此外还包含：

- 方形过滤：位移小于 `nearCoord` 时丢弃采样点。
- 观察者模式：检查高速移动后的速度变化和方向突变，减少 GPS 漂移误判。
- 前后台差异：后台搜索较少的站点结果，保证通知消费所需的最小数据；回到前台时重新搜索完整数量。

## 通知与平台配置

系统前台服务通知由 `geolocator` 使用，业务通知由 `flutter_local_notifications` 使用。两者使用不同的图标资源：

- Android 应用图标：`@mipmap/ic_launcher`。
- Android 业务通知图标：`@drawable/ic_notification`。
- iOS 应用图标：`ios/Runner/Assets.xcassets/AppIcon.appiconset/`。

Android 需要定位、前台定位服务、唤醒锁和通知权限。iOS 在 `Info.plist` 中声明了前台和后台定位用途及相关权限。实际权限状态仍由系统和用户设置决定。

## 依赖

| 包 | 用途 |
|----|------|
| `flutter_localizations` | 多语言支持 |
| `flutter_local_notifications` | 业务通知 |
| `geolocator` | GPS 定位流和前台定位服务 |
| `package_info_plus` | 包名和许可证信息 |
| `shared_preferences` | 设置持久化 |
| `flutter_launcher_icons` | 生成 Android/iOS 应用图标 |

## 开发说明

架构契约位于 [`docs/architecture.md`](docs/architecture.md)。较大的修改应先讨论并更新架构文档，再实现和测试。

当前项目的主要初始化顺序是：

```text
HomePage 加载 Settings 和 StationManager
        ↓
创建 Coordinator 并设置 LocationProcessor handler
        ↓
初始化 NotificationService
        ↓
HomePage 发布 UI 状态并显示主界面
```

## 多语言

| 语言 | Locale |
|------|--------|
| 简体中文 | `zh-Hans` / `zh-CN` |
| 日语 | `ja` |
| 英语 | `en` |

## 许可证及车站信息

本项目代码基于 [MIT License](LICENSE) 开源。

车站信息 BIN 文件衍生于 [駅データ.jp](https://ekidata.jp/) 公开的数据。根据駅データ.jp 的[使用条款](https://ekidata.jp/agreement.php)，本项目不包含原始数据集，如有需要请参考原网站。

站点信息生成工具在 [ConvertStationBin](https://github.com/chickwood/ConvertStationBin) 仓库公开。