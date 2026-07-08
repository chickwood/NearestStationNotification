# Nearest Station Notification 🚉

> Locates the nearest station based on your current position.

无论用户身处何地距离远近，始终实时定位并指向物理距离最近的车站并显示通知。

## 项目结构

```
nearest_station_notification/
├── lib/
│   ├── app_settings.dart           # 应用设置（持久化存储）
│   ├── common.dart                 # 共用类、枚举与工具函数
│   ├── home_page.dart              # UI 主页面
│   ├── l10n.dart                   # 多语言（中/日/英）
│   ├── licenses_dialog.dart        # 许可证列表及详情对话框
│   ├── location_processor.dart     # 位置处理（GPS 流 + 漂移过滤 + 搜索算法）
│   ├── main.dart                   # App 入口
│   ├── notification_service.dart   # 通知及 UI 回调管理
│   ├── search_engine.dart          # 最近车站搜索算法
│   ├── settings_dialog.dart        # 设置对话框
│   └── station_manager.dart        # 车站信息管理器（BIN 文件解析）
├── assets/
│   ├── ADDITIONAL_NOTICE           # 车站信息免责声明
│   ├── LICENSE                     # MIT License
│   └── station_data_xyz.bin        # 直角坐标系形式（XYZ）的车站信息（日本全境电车站信息，含部分废线废站）
├── android/
│   └── app/src/main/AndroidManifest.xml
└── pubspec.yaml
```

## 核心设计原则

- **始终有效**：无论距离远近，始终指向最近的车站
- **切换即通知**：最近的车站发生变化时自动推送，通知显示"最近的是 A 站，距离 10 km"
- **无预设范围**：最近的车站自然变化时触发，而非固定距离阈值范围
- **减少打扰**：通知默认只显示，无声、无振动、无额外交互

## 核心算法（search_engine.dart）

两阶段定位：

1. **粗筛**：弦长平方距离，KD-Tree 查找 Top-K * 2
2. **精算**：根据所在区域选择距离公式，对 Top-K 候选精确计算并排序
   - **日本全境及近海区域**：采用勾股定理计算等距长方投影距离
   - **区域外**：采用 Haversine 公式计算大圆距离

数据结构：利用生成脚本将 `Float64List` 平铺数组分区存储（纬度区 / 经度区 / XYZ 区 / KD-Tree 左右子节点区 / 车站名偏移区）
- 内存连续，CPU 缓存友好
- 约 1 万站点 ≈ 600 KB，完全适合内存

## GPS 流处理（location_processor.dart）

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
       ├─ LocationProcessor（GPS 流 + 漂移过滤 + 搜索算法）
       ｜  ├─ Geolocator GPS Stream（自适应采样）
       ｜  ├─ GPS 漂移过滤（方形过滤 + 观察者模式）
       ｜  └─ SearchEngine.locate()
       └─ FlutterLocalNotifications（业务通知 + UI 回调）
```

- **Geolocator 前台通知**：系统前台服务常驻通知
- **FLN 通知**：最近车站变动时更新的业务通知（无声、无振动）

## 依赖

| 包 | 用途 |
|----|------|
| `flutter_localizations` | 多语言支持 |
| `flutter_local_notifications` | 业务通知显示 |
| `geolocator` | GPS 定位流 + 前台服务 |
| `package_info_plus` | 包名及许可证详情获取 |
| `shared_preferences` | 设置持久化 |

## 多语言支持

| 语言 | Locale |
|------|--------|
| 简体中文 | `zh-Hans` / `zh-CN` |
| 日语 | `ja` |
| 英语 | `en` |

默认为系统当前语言

## 许可证及车站信息

本项目代码基于 [MIT License](LICENSE) 开源。

车站信息（`station_data_xyz.bin`）衍生于 [駅データ.jp](https://ekidata.jp/) 所公开的数据。  
根据 駅データ.jp 的[使用条款](https://ekidata.jp/agreement.php)，本项目不包含原始数据集，如有需要请参考原网站。

## 车站信息（`station_data_xyz.bin`）生成工具
车站信息生成工具（脚本）在以下仓库公开：  
[ConvertStationBin](https://github.com/chickwood/ConvertStationBin)
