# Nearest Station Notification 🚉

> Locates the nearest station based on your current position.

无论用户身处何地，永远实时定位并指向物理距离最近的车站显示通知。

## 项目结构

```
nearest_station_notification/
├── lib/
│   ├── app_settings.dart           # 应用设置（持久化存储）
│   ├── common.dart                 # 共用类、枚举与工具函数
│   ├── home_page.dart              # UI 主页面
│   ├── l10n.dart                   # 多语言（中 / 日 / 英）
│   ├── location_task_handler.dart  # Task Isolate 处理器（GPS 流 + 搜索算法）
│   ├── main.dart                   # App 入口
│   ├── notification_service.dart   # 主线程服务（FGT/FLN 管理 + UI 回调）
│   ├── search_engine.dart          # 最近车站搜索算法
│   └── station_manager.dart        # 车站信息管理器（BIN 文件解析）
├── assets/
│   └── station_data_xyz.bin        # 直角坐标系形式（XYZ）的车站信息（全日本电车站信息，含部分废线废站）
├── android/
│   └── app/src/main/AndroidManifest.xml
└── pubspec.yaml
```

## 核心设计原则

- **没有距离限制**：无论多远，始终显示最近的车站
- **没有范围提醒**：只显示"最近的是 A 站，距离 10 km"
- **没有多余负担**：纯工具属性，极简交互

## 核心算法（search_engine.dart）

两阶段定位：

1. **粗筛**：弦长平方距离，KD-Tree 查找 Top-K * 2
2. **精算**：根据所在区域选择距离公式，对 Top-K 候选精确计算并排序
   - **日本全境及近海**：采用勾股定理计算等距长方投影距离
   - **境外**：采用 Haversine 公式计算大圆距离

数据结构：利用生成脚本将 `Float64List` 平铺数组分区存储（纬度区 / 经度区 / XYZ 区 / KD-Tree 左右子节点区 / 车站名偏移区）
- 内存连续，CPU 缓存友好
- 约 1 万站点 ≈ 400 KB，完全适合内存

## 自适应采样（location_task_handler.dart）

根据实时速度动态切换 GPS 采样策略，在精度与功耗之间取得平衡：

| 模式 | 速度阈值 | distanceFilter |
|------|----------|----------------|
| 静止 🧍 | < 1 m/s | 4 m |
| 步行 🚶 | ≥ 1 m/s | 4 m |
| 骑行 🚲 | ≥ 4 m/s | 4 m |
| 乘车 🚃 | ≥ 8 m/s | 16 m |

除 `distanceFilter` 自适应外，还内置了两阶段 GPS 漂移过滤：

- **方形过滤**：位移过小（< `nearCoord`）直接丢弃
- **观察者模式**：在高更新频率下，对速度骤升骤降或方向突变（> 45°）的采样点进行二次校验，防止 GPS 漂移的误判

## 架构说明

```
主线程 (UI)
  └─ NotificationService
       ├─ 启停 FlutterForegroundTask (FGT)
       ├─ 管理 FlutterLocalNotifications (FLN) 业务通知
       └─ 接收 Task Isolate 数据 → 更新通知栏 + 驱动 UI 重绘

Task Isolate
  └─ LocationTaskHandler
       ├─ Geolocator GPS Stream（自适应采样）
       ├─ GPS 漂移过滤（方形过滤 + 观察者模式）
       └─ SearchEngine.locate() → sendDataToMain()
```

- **FGT 通知**：系统前台服务常驻通知（提示用户长按关闭）
- **FLN 通知**：最近车站变动时更新的业务通知（无声、无振动）

## 依赖

| 包 | 用途 |
|----|------|
| `flutter_foreground_task` | 前台服务 + Task Isolate 通信 |
| `flutter_local_notifications` | 业务通知显示 |
| `geolocator` | GPS 定位流 |
| `shared_preferences` | 设置持久化 |
| `flutter_localizations` | 多语言支持 |

## 多语言支持

| 语言 | Locale |
|------|--------|
| 日语 | `ja` |
| 简体中文 | `zh-Hans` / `zh-CN` |
| 英语（默认） | `en` |

## License

本项目代码基于 [MIT License](LICENSE) 开源。  
车站信息（`station_data_xyz.bin`）衍生自 [駅データ.jp](https://ekidata.jp/)，使用须遵循其原始许可条款。
