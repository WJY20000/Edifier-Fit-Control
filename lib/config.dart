/// 这台耳机的固定身份。
///
/// 用户只有一只耳机（EDIFIER Fit900NB Turbo），所以从 0.6.1 起不再等扫描：
/// 启动就直接连它。换耳机时在「设置 → 我的耳机」里改地址，或点「取消固定」。
///
/// ## 经典蓝牙地址 ≠ BLE 地址
///
/// 很多人会从「设备和打印机 → 属性 → 唯一标识符」拿到 **经典蓝牙** 的地址，
/// 那个地址 Windows 的 BLE 栈根本不认识，直接连会得到
/// `UniversalBleErrorCode.connectionFailed / Failed to get device`。
/// 这只耳机两者确实不同：
///
/// | 用途 | 地址 |
/// | --- | --- |
/// | 经典蓝牙（音频 A2DP/HFP） | `6c:16:29:e7:b5:14` |
/// | BLE 广告 / GATT（本应用连这个） | `6c:16:29:e7:b5:41` |
///
/// 两个地址都写在下面；连接只用 [kMyHeadsetBleMac]，
/// 经典地址只用来「认出这是同一台」。
const String kMyHeadsetName = 'EDIFIER Fit900NB Turbo';

/// BLE 广告地址 —— 真正要连的那个（小写冒号形式）。
///
/// 来源：真机抓包里该设备广播的地址；同一包的厂商数据
/// `e0 07 6c 16 29 e7 b5 14 02 00` 里写着经典地址，可以确认是同一台。
const String kMyHeadsetBleMac = '6c:16:29:e7:b5:41';

/// 经典蓝牙地址（Windows 属性里显示的那个）。**不要**拿它去连 BLE。
const String kMyHeadsetClassicMac = '6c:16:29:e7:b5:14';

/// 漫步者（BES 方案）广播里厂商数据的公司 ID。
///
/// 数据格式：`E0 07` + 6 字节经典 MAC + 2 字节状态。
/// 扫描时用这个把「哪台 BLE 设备是这只耳机」认出来，从而自动学会它的 BLE 地址。
const int kEdifierCompanyId = 0x07E0;
