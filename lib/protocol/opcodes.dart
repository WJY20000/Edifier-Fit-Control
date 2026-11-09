// EDIFIER 命令字（v1 协议；v2 复用同一套命令字，长度字段不同）。
//
// 来源：mEDIFIER doc/KnownCommands/W820NB_Double_Gold.txt、
//       edifier-proto models/w820nb.md、EncoDeck EdifierConstants.cs。
// 带「?」的是尚未在公开记录里确认、靠本项目探测得到的。

class Op {
  /// 当前曲目标题（只读，UTF-8）
  static const int trackTitle = 0x01;

  /// 当前曲目艺术家（只读，UTF-8）
  static const int trackArtist = 0x02;

  /// 提示音音量（0–15）
  static const int promptVolumeGet = 0x05;
  static const int promptVolumeSet = 0x06;

  /// 恢复出厂
  static const int factoryReset = 0x07;

  /// 场景：0 音乐 / 1 游戏 / 2 空间音效（Fit900NB Turbo 真机确认）
  static const int sceneGet = 0x08;
  static const int sceneSet = 0x09;

  /// 通用设置通道（Fit900NB Turbo 真机确认）：
  /// 读 0x91 / 写 0x92，payload 首字节是设置项 id。
  static const int settingGet = 0x91;
  static const int settingSet = 0x92;

  /// 设置通道里 LDAC 的项 id：`[0x11, 0 关 / 1 44.1&48k / 2 96k]`
  static const int settingLdac = 0x11;

  /// 主动降噪 / 环境声
  static const int noiseSet = 0xC1;
  static const int noiseGet = 0xCC;

  /// 音效（EQ 预设）
  static const int soundEffectSet = 0xC4;
  static const int soundEffectGet = 0xD5;

  /// 固件版本（3 字节：主.次.修订）
  static const int firmwareGet = 0xC6;

  /// MAC 地址（社区记录为 0xC8，但 2026-11-08 的 Fit900 抓包里官方 App
  /// 从没发过这条——它直接用系统 BLE 地址。本应用不发，避免未知命令。）
  static const int macGet = 0xC8;

  /// 蓝牙名称
  static const int nameGet = 0xC9;
  static const int nameSet = 0xCA;

  /// 断开 / 关机 / 重新配对
  static const int disconnect = 0xCD;
  static const int powerOff = 0xCE;
  static const int rePair = 0xCF;

  /// 电量（百分比）
  static const int batteryGet = 0xD0;

  /// 自动关机计时（分钟）
  static const int powerOffTimerSet = 0xD1;
  static const int powerOffTimerDisable = 0xD2;
  static const int powerOffTimerGet = 0xD3;

  /// 按键循环的降噪模式掩码
  static const int keyControlGet = 0xF0;
  static const int keyControlSet = 0xF1;

  /// 型号指纹（16 字节）
  static const int fingerprint = 0xD8;

  /// 双耳 / 充电盒状态（TWS 用；头戴一般不回）
  static const int twsState = 0xF2;

  /// 未知但被官方 App 使用：提示音音量影子寄存器
  static const int promptVolumeShadow = 0xF9;
}

/// 降噪槽位（v2 帧 payload 的第一个字节）。
class AncSlot {
  /// Fit900NB Turbo（固件 1.0.3）：1 深度 / 2 舒适 / 3 防风 / 4 环境声 / 5 关。
  ///
  /// 读降噪（0xCC）不带参数；写降噪（0xC1）是 `[2F, 档位]`，
  /// 切环境声时再带一个等级字节。
  static const int fit900 = 0x2F;
}

/// 场景（0x09 写入，0x08 回读）。Fit900NB Turbo 真机确认。
class Scene {
  static const int music = 0;
  static const int game = 1;
  static const int spatial = 2;

  static const List<int> all = [music, game, spatial];

  static String labelKey(int value) {
    switch (value) {
      case music:
        return 'scene.music';
      case game:
        return 'scene.game';
      case spatial:
        return 'scene.spatial';
      default:
        return 'scene.music';
    }
  }
}

/// LDAC 档位（0x92 写入 `[0x11, 值]`，0x91 回读）。真机确认。
class LdacMode {
  static const int off = 0;
  static const int auto = 1; // 44.1 / 48 kHz
  static const int hiRes = 2; // 96 kHz

  static const List<int> all = [off, auto, hiRes];

  static String labelKey(int value) {
    switch (value) {
      case off:
        return 'ldac.off';
      case auto:
        return 'ldac.auto';
      case hiRes:
        return 'ldac.hires';
      default:
        return 'ldac.off';
    }
  }
}

/// 环境声等级（0xC1 `[0x2F, 0x04, 等级]`）。真机确认只有 1–3。
class AmbientLevel {
  static const int vocal = 1; // 突出人声
  static const int balanced = 2; // 平衡
  static const int background = 3; // 突出背景声

  static const List<int> all = [vocal, balanced, background];

  static String labelKey(int value) {
    switch (value) {
      case vocal:
        return 'ambient.vocal';
      case balanced:
        return 'ambient.balanced';
      case background:
        return 'ambient.background';
      default:
        return 'ambient.balanced';
    }
  }
}
