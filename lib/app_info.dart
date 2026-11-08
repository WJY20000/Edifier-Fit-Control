/// 应用版本号。
///
/// 与 `pubspec.yaml` 的 `version` 保持一致。这里不引入 package_info_plus：
/// 桌面端与 Android 都会多一个原生依赖，而目前只有「设置 → 关于」用到它。
/// 发版时两处一起改（pubspec.yaml 与这里）。
const String kAppVersion = '0.8.4';
