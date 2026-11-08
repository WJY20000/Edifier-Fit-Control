# 扫不到耳机？先看这里

目标设备：**EDIFIER Fit900NB Turbo**，MAC `6C:16:29:E7:B5:14`（0.6.1 起内置为默认地址）。

## 一句话结论

> Windows 蓝牙面板里"看得见 / 已连接"，和"BLE 能扫到 / 能连上"是**两件不同的事**。
> 这只耳机在 Windows 里建的是**经典蓝牙**（A2DP + HFP + AVRCP）绑定，
> BLE 那一侧可以不广播、甚至没绑定 —— 于是系统里一切正常，本应用却扫出空列表。

## 怎么从设备管理器输出里读出 MAC

```powershell
Get-PnpDevice -FriendlyName '*Fit900*' | Select-Object FriendlyName, InstanceId
```

```
EDIFIER Fit900NB Turbo   BTHENUM\DEV_6C1629E7B514\7&3625B630&0&BLUETOOTHDEVICE_6C1629E7B514
```

`DEV_` 后面那 12 位十六进制就是地址：

```
6C 16 29 E7 B5 14  →  6c:16:29:e7:b5:14
```

其它几条（`BTHENUM\{0000110B-…}` / `{0000110E-…}` / `{0000110C-…}` / `{0000111E-…}`）
分别是 A2DP 音频、AVRCP 控制/传输、免提（HFP）—— 全是**经典蓝牙**的 profile GUID。
`SWD\MMDEVAPI\{…}` 是 Windows 的音频端点，也不是设备本身。

## BLE 到底绑没绑？看这两个地方

| 看到的 | 含义 |
| --- | --- |
| `BTHENUM\DEV_<mac>\…` | 经典蓝牙已配对（音频能用） |
| `BTHLE\DEV_<mac>\…` | **BLE 已绑定** —— 有这条，直连基本必成 |
| `Get-PnpDevice -Class BluetoothLE` 有输出 | 同上，系统里有 LE 设备节点 |

没有 `BTHLE` 那一条，说明 Windows 只建了经典蓝牙的绑定。此时 `BluetoothLEDevice::FromBluetoothAddressAsync(地址)`
仍然可以尝试直连（不需要先扫描），但成败取决于耳机是否在广播、以及有没有旧的 LE 配对信息。

### 让 Windows 重建一次绑定

1. 设置 → 蓝牙和设备 → 找到耳机 → **删除设备**；
2. 耳机进入配对模式（通常长按电源键，指示灯快闪）；
3. 重新"添加设备 → 蓝牙"；
4. 再跑一次 `Get-PnpDevice -Class BluetoothLE`，看有没有 `BTHLE\DEV_6C1629E7B514`。

> 注意：这一步会短暂断开音频。做完之后先别急着放歌，直接开本应用连一次。

## 三条连接路径（应用内）

| 入口 | 原理 | 何时用 |
| --- | --- | --- |
| 设置 →「我的耳机」→ 保存并连接 | `connect(address)`，`FromBluetoothAddressAsync` | 默认走这条，地址已预填 |
| 扫描页 →「MAC 直连」 | 同上，临时输入 | 想连另一台 |
| 扫描页 →「系统设备」 | `GetSystemDevices()` = WinRT 里 `ConnectionStatus::Connected` 的集合 | 耳机正被 Windows 用着音频 |
| 扫描页 →「蓝牙扫描」 | BLE 广播 | 确认耳机到底有没有在广播；默认不过滤，每行都显示地址 |

## 常见失败

**`Device not found` / 连接超时**
耳机被 Windows 当音频设备占着。先播放器里"断开"，或设置 → 蓝牙里点一下耳机 → 断开，
再回应用里直连。同一时刻只允许一个 GATT 连接。

**连上了但读不到数据**
说明 GATT 通道建立、但耳机没在 Edifier 服务上回包。
看「实验室」里的收发日志：只发不收 = 服务/特征值不对，或耳机固件不认这条命令。

**重启后又连不上**
应用会在启动时静默重连固定地址（`autoReconnect` 打开时），失败就停在"未连接"，
这时点设备页的「连接我的耳机」重试一次即可。

## 已知的平台限制

- universal_ble 3.2.0 的 `getSystemDevices()` 在 Windows 上**只枚举已连接设备**，
  `BleDevice.paired` 字段没有被 native 侧填充 —— 所以"只列已配对（含未连接）"
  在 Dart 层做不到。折中方案是：固定 MAC（本应用的默认行为）+ 系统已连接列表。
- 不做插件 native 改动，保持依赖为上游原版。
