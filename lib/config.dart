/// 这台耳机的固定身份。
///
/// 用户只有一只耳机（EDIFIER Fit900NB Turbo），所以从 0.6.1 起不再等扫描：
/// 首次启动就把地址写进偏好，直接连它。换耳机时在
/// 「设置 → 我的耳机」里改地址即可，或者点「取消固定」回到扫描模式。
///
/// 地址来源：Windows 设备实例 ID 里的 `DEV_6C1629E7B514`
/// （`Get-PnpDevice -FriendlyName '*Fit900*'` 的 `InstanceId` 字段）。
const String kMyHeadsetName = 'EDIFIER Fit900NB Turbo';

/// 小写冒号形式，Windows / Android 的 BLE 栈都认这个格式。
const String kMyHeadsetMac = '6c:16:29:e7:b5:14';
