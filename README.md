# EDIFIER Fit Control

针对 **漫步者 Fit900NB Turbo** 的第三方蓝牙控制台，一套 Flutter 代码同时产出 **Windows 桌面程序** 与 **Android APK（arm64-v8a）**。

灵感来自 [SpriteOvO/AirPodsDesktop](https://github.com/SpriteOvO/AirPodsDesktop)（Windows 上的 AirPods 电量/降噪面板）。原项目是 Qt/C++ 且只做 Windows；这里换成为 Flutter，因为需求是 **Win + Android 双端**，而且希望「源码推到 GitHub 就能自动构建」，不需要本地装 Qt/Visual Studio。

> 非官方工具，与漫步者（EDIFIER）没有任何关系。协议来自社区逆向工程，并由本项目用真机抓包核对；按现状提供，风险自负。

![icon](assets/branding/icon_256.png)

**作者 / Author：** infinite

---

## 它能做什么

| 功能 | 说明 |
| --- | --- |
| 电量 | 连接后读取，主页大圆环展示，可手动刷新 |
| 降噪 | 深度 / 舒适 / 防风噪 / 环境声 / 关闭（真机确认，槽位 `0x2F`） |
| 环境声等级 | 突出人声 / 平衡 / 突出背景声（真机确认） |
| 场景 | 音乐 / 游戏 / 空间音效（真机确认；非音乐时音效被接管并置灰） |
| 音效预设 | 人声 / 低音增强 / 动感 / 纯正 / 高音增强 / 发烧友（真机确认） |
| LDAC | 关闭 / 44.1–48 kHz / 96 kHz（切换后耳机会重连，属正常） |
| 设备信息 | 固件版本、MAC、蓝牙名称、帧格式（固定 v2）、服务 UUID、MTU |
| 重命名 | 改耳机蓝牙名称（≤30 字节） |
| 关机 / 断开 | 关机前有确认 |
| 实验室 | 手动发任意命令字、十六进制数据，查看原始收发日志，一键复制 |
| 退出 | 设置 →「退出应用」或 Windows 右上角 ×：断开耳机并结束进程（最多等 8 秒，一定会退） |
| 单实例 | 重复启动不会去抢蓝牙连接，而是提示「程序已经在运行」 |
| 扫不到时 | 系统设备列表 / 按 MAC 直连（固定一台耳机，不依赖广播） |

界面中英双语，深浅色主题跟随系统，Windows 宽屏自动切换侧边栏布局。主色取自新版漫步者图标（`#0088C9`），红色只用于危险操作。

**只支持这一只耳机**：0.8.8 起删掉了多型号档案与型号识别。不管连到的是什么设备，都按 **Fit900NB Turbo** 处理，发出去的每一条命令都是这台机器上抓包确认过的那一条（BES v2 明文帧、降噪槽位 `0x2F`），不会再去试探别的帧格式或降噪槽位。

协议来自 2026-11-08 的真机 HCI 抓包（固件 1.0.3），命令表与原始字节见 [docs/PROTOCOL.md](docs/PROTOCOL.md)。

---

## 扫不到耳机怎么办

> 只为一台耳机做的：**EDIFIER Fit900NB Turbo**。
> 它的 BLE 地址 `6c:16:29:e7:b5:41` 已内置成默认值，装上就直连，不依赖扫描。
> 注意设备属性里的「唯一标识符」是**经典蓝牙**地址 `6c:16:29:e7:b5:14`，填那个连不上。

BLE 扫描靠的是**广播**。耳机一旦被 Windows 当成音频设备连上，通常就不再广播，
于是「系统里看得见、这里扫不到」。按可靠性从高到低有三条路：

1. **按 MAC 直连（推荐）**
   设置 →「我的耳机」填入地址 → 保存并连接；或者扫描页右上角「MAC 直连」当场填。
   这条路不发广播、不看列表，直接向该地址发起 GATT 连接。
   连成功一次后地址会自动固定，以后启动直接重连。
2. **系统设备**
   扫描页把来源切到「系统设备」。它列的是 WinRT 里 `ConnectionStatus = Connected`
   的设备，即 Windows 当前握着的那些，不受广播影响。
3. **蓝牙扫描**
   切到「系统设备」以外的默认来源。列表默认**不过滤**（「只看漫步者」默认关），
   每行都带地址——Windows 的广播里经常没有名字，看地址更准。

怎么拿 MAC：控制面板 → 设备和打印机 → 右键耳机 → 属性，或 PowerShell：

```powershell
Get-PnpDevice -FriendlyName '*Fit900*' | Select-Object FriendlyName, InstanceId
```

`InstanceId` 里那串 12 位十六进制是**经典蓝牙**地址（形如 `DEV_6C1629E7B514` → `6c:16:29:e7:b5:14`），
它和 BLE 地址不是一回事，**不要**拿它去连。BLE 地址在扫描列表里直接显示
（这台是 `6c:16:29:e7:b5:41`），应用也会在扫描时自动认出来并固定。

更细的排查（经典蓝牙 vs BLE 绑定、`BTHLE` 节点怎么看）见 **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**。

## 直接构建（GitHub Actions）

1. 把本目录推到你的 GitHub 仓库（`main` / `master` / 任意分支都行）。
2. 打开仓库的 **Actions** 页面，两个工作流会自动开始：
   - **Android APK (arm64-v8a)** → 产出 `EdifierFitControl-<run>-arm64-v8a.apk`
   - **Windows EXE (x64)** → 产出 `EdifierFitControl-<run>-windows-x64.zip`
3. 构建完成后在该次运行的 **Artifacts** 区域下载。

也可以在 Actions 页面点 **Run workflow** 手动触发；推 `v*` 标签同样会触发。

构建机每次都会先运行 `dart tool/bootstrap.dart`，用当前 Flutter 版本**生成缺失的 `android/` 与 `windows/` 目录**，再注入蓝牙权限、应用名与图标。因此仓库里不需要提交这两套平台样板文件，也就不会出现「模板版本和 SDK 对不上」的问题。

固定的 Flutter 版本是 **3.47.7**（stable）。想换版本，改 `.github/workflows/*.yml` 里的 `flutter-version` 即可。

---

## 本地开发

```bash
# 1. 安装 Flutter 3.47.x（含 Dart 3.13）
flutter --version

# 2. 生成 android/ 与 windows/，并打好补丁
dart tool/bootstrap.dart

# 3. 拉依赖并运行
flutter pub get
flutter run -d windows     # Windows 桌面
flutter run -d android     # 连着真机 / 模拟器（BLE 需要真机）
```

打包：

```bash
flutter build windows --release
flutter build apk --release --target-platform android-arm64
```

产物位置：
- `build/windows/x64/runner/Release/`（整个目录一起分发，缺 DLL 跑不起来）
- `build/app/outputs/flutter-apk/app-release.apk`

重新生成图标（可选，需要 Pillow）：

```bash
python3 -m pip install pillow
python3 tool/make_icons.py
```

---

## 使用步骤

1. 耳机开机，**先在系统蓝牙设置里断开它**（Windows / Android 都只允许一个进程持有 BLE 连接）。
2. 打开应用 → 「扫描」→ 点你的设备。设备名里带 `EDIFIER` / `Fit900` 的会排在最前并标蓝。
3. 连接成功后自动读电量、设备信息与全部控制项（降噪 / 场景 / 音效 / LDAC）。哪一项是「未知」，到「设备」页点 **重新读取** 再试一次。

### 平台要求

| 平台 | 要求 |
| --- | --- |
| Windows | Windows 10 1809+ / Windows 11，蓝牙 4.0+ 适配器，x64 |
| Android | Android 7.0+（API 24，Flutter 3.47 的默认下限），**arm64-v8a**，蓝牙 4.0+ |
| 权限 | Android 12+ 需要「附近的设备」；Android 11 及以下需要定位权限（系统扫描 BLE 的硬性要求） |

APK 使用 Flutter 模板的 debug 签名（可直接安装，不适合上架）。要发布自己的版本，请按 Flutter 官方文档配置 `signingConfig`。

---

## 已知限制

- **只支持 Fit900NB Turbo**：换别的耳机（哪怕是同门型号）连上也可能完全不可用 —— 应用不会识别型号，也不会换协议。
- 只能连一台设备；不支持多点连接管理、固件升级、EQ 自定义曲线。
- 切换 LDAC 会触发耳机重连，应用会短暂显示断开，重连后自动重新读取状态。
- 所有控制命令都按 Fit900NB Turbo 发送；接别的设备时若它不认识这些命令字，可能出现无响应或掉线，这是预期内的。
- Windows 的 MTU 由系统决定，长命令会按 20 字节分片写出。
- 源码是在没有 Flutter SDK 的环境里整理的，未做本地编译验证；构建以 Actions 日志为准。若首次构建报错，多半是 Flutter 小版本差异，改 `.github/workflows/*.yml` 里的 `flutter-version` 即可。

## 反馈 / 排障

「实验室」页有完整的收发日志：

1. 复现问题；
2. 点右上角 **复制**；
3. 附上耳机型号、固件版本（设备页可看）和你期望的功能。

日志里只有蓝牙字节，不包含音频、位置或账号信息。

### 已经验证过了

Fit900NB Turbo 的协议已由真机抓包确认（见 [docs/PROTOCOL.md](docs/PROTOCOL.md)）。
本版本刻意只保留这一套协议：没有型号表，也没有运行时试探，任何改动都会直接体现在这台机器的行为上。

## 隐私

应用**不联网**：没有分析 SDK、没有账号、没有云同步。所有数据（上次连接的设备、语言、主题）只保存在本机的 `shared_preferences` 里。

## 目录结构

```
lib/
  main.dart                 入口
  protocol/                 与设备无关的协议层（可单测）
    frame.dart              v1 / v2 帧编解码、增量解码器
    opcodes.dart            命令字与降噪槽位
    models.dart             降噪档位、音效预设、能力、设备状态
    engine.dart             读取状态、命令队列、状态机、日志
  ble/
    ble_controller.dart     扫描 / 连接 / GATT 选择（universal_ble）
  state/session.dart        应用状态与偏好
  ui/                       四个页面 + 主题 + 通用组件
  i18n/l10n.dart            中英文案
test/                       帧编解码与读取流程的单元测试
tool/
  bootstrap.dart            生成平台目录并打补丁（CI 与本地共用）
  make_icons.py             生成 PNG / ICO 图标
  decode_btsnoop.py         Android HCI 抓包解码器
docs/PROTOCOL.md            协议笔记（含 2026-11-08 真机抓包结论）
docs/CAPTURE.md             抓包手册：已确认命令与抓包方法
```

## 致谢

协议与实现参考了这些公开的社区项目：

- [wh201906/mEDIFIER](https://github.com/wh201906/mEDIFIER)（MIT，Qt/C++，v1 帧与命令表）
- [GlitchPunkWTF/edifier-proto](https://github.com/GlitchPunkWTF/edifier-proto)（Dart，W820NB 命令表）
- [TIANLI0/EncoDeck](https://github.com/TIANLI0/EncoDeck)（C#，BES v2 帧、降噪槽位）
- [Navideck/universal_ble](https://github.com/Navideck/universal_ble)（BSD-3，跨平台 BLE）

## 许可证

[MIT](LICENSE)
