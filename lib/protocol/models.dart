import 'dart:typed_data';

import 'frame.dart';
import 'opcodes.dart';

/// 降噪模式。头戴只有一档降噪时统一映射为 [deep]。
enum NoiseMode { off, deep, comfort, wind, ambient, adaptive }

/// 一个可选的降噪档位。
class NoiseOption {
  final NoiseMode mode;

  /// 写入设备的数值。
  final int value;

  /// 文案 key（见 lib/i18n/l10n.dart）。
  final String labelKey;

  const NoiseOption(this.mode, this.value, this.labelKey);
}

/// Fit900NB Turbo 的降噪档位。
///
/// 2026-11-08 真机抓包（固件 1.0.3）确认：写 `C1 [2F 档位]`，
/// 1 深度 / 2 舒适 / 3 防风噪 / 4 环境声 / 5 关闭。
/// 只支持这一只耳机，所以没有「方言」的概念 —— 数值就是唯一的一套。
const List<NoiseOption> kNoiseOptions = [
  NoiseOption(NoiseMode.deep, 1, 'noise.deep'),
  NoiseOption(NoiseMode.comfort, 2, 'noise.comfort'),
  NoiseOption(NoiseMode.wind, 3, 'noise.wind'),
  NoiseOption(NoiseMode.ambient, 4, 'noise.ambient'),
  NoiseOption(NoiseMode.off, 5, 'noise.off'),
];

/// 写降噪的 payload。
///
/// 环境声要带等级：`[2F, 04, 等级]`（等级 1 人声 / 2 平衡 / 3 背景声）；
/// 其它档位就是 `[2F, 档位]`。
List<int> noisePayload(NoiseMode mode, {int ambientLevel = AmbientLevel.balanced}) {
  if (mode == NoiseMode.ambient) return [AncSlot.fit900, 4, ambientLevel];
  for (final option in kNoiseOptions) {
    if (option.mode == mode) return [AncSlot.fit900, option.value];
  }
  return const [];
}

/// 解析 0xCC 的回包。
///
/// 真机只回 `[2F, 档位]`；处于环境声时可能多带一个等级字节，不影响档位判断。
NoiseMode? decodeNoise(Uint8List payload) {
  if (payload.length < 2 || payload[0] != AncSlot.fit900) return null;
  for (final option in kNoiseOptions) {
    if (option.value == payload[1]) return option.mode;
  }
  return null;
}

/// 内置音效预设。
///
/// Fit900NB Turbo 真机确认的 6 组（2026-11-08 抓包），
/// 顺序按官方 App 的排列：人声 → 低音增强 → 动感 → 纯正 → 高音增强 → 发烧友。
class EqPreset {
  final int value;
  final String labelKey;
  const EqPreset(this.value, this.labelKey);

  static const List<EqPreset> fit900 = [
    EqPreset(2, 'eq.vocal'),
    EqPreset(3, 'eq.bass'),
    EqPreset(1, 'eq.dynamic'),
    EqPreset(0, 'eq.pure'),
    EqPreset(4, 'eq.treble'),
    EqPreset(5, 'eq.audiophile'),
  ];
}

/// 设备能力：只有探测到应答才置 true，UI 据此隐藏控件。
class Capabilities {
  bool battery = false;
  bool noise = false;
  bool ambientLevel = false;
  bool scene = false;
  bool ldac = false;
  bool soundEffect = false;
  bool rename = false;
  bool powerOffTimer = false;

  bool get anyControl =>
      noise || scene || ldac || soundEffect || rename || powerOffTimer;

  /// 快照。重新读取失败时用它回滚，避免把已经能用的控件弄没。
  Capabilities copy() => Capabilities()
    ..battery = battery
    ..noise = noise
    ..ambientLevel = ambientLevel
    ..scene = scene
    ..ldac = ldac
    ..soundEffect = soundEffect
    ..rename = rename
    ..powerOffTimer = powerOffTimer;

  void restore(Capabilities other) {
    battery = other.battery;
    noise = other.noise;
    ambientLevel = other.ambientLevel;
    scene = other.scene;
    ldac = other.ldac;
    soundEffect = other.soundEffect;
    rename = other.rename;
    powerOffTimer = other.powerOffTimer;
  }
}

/// 设备当前状态（全部来自设备应答，不做乐观假设）。
class DeviceState {
  int? battery;
  NoiseMode? noise;
  int? ambientLevel;
  int? soundEffect;
  int? scene;
  int? ldac;
  String? firmware;
  String? name;
  String? mac;
  String? fingerprint;

  void reset() {
    battery = null;
    noise = null;
    ambientLevel = null;
    soundEffect = null;
    scene = null;
    ldac = null;
    firmware = null;
    name = null;
    mac = null;
    fingerprint = null;
  }

  /// LDAC 文案（0 关 / 1 44.1&48k / 2 96k）
  String? get ldacLabel {
    switch (ldac) {
      case 0:
        return 'Off';
      case 1:
        return '44.1 / 48 kHz';
      case 2:
        return '96 kHz';
      default:
        return null;
    }
  }
}

/// 一次读取的结果，用于 UI 展示与排障。
class NegotiationResult {
  final bool ok;

  /// 帧格式（固定 v2，保留字段只为日志显示）。
  final Framing? framing;

  /// 设备回包首字节（0xBB / 0xCC / 0xAA）。
  final int? responseHead;

  /// 厂商 GATT 服务 UUID。
  final String? serviceUuid;

  /// 写特征 UUID。
  final String? writeUuid;

  /// 通知特征 UUID。
  final String? notifyUuid;

  final String? error;

  const NegotiationResult({
    required this.ok,
    this.framing,
    this.responseHead,
    this.serviceUuid,
    this.writeUuid,
    this.notifyUuid,
    this.error,
  });

  NegotiationResult copyWith({
    bool? ok,
    Framing? framing,
    int? responseHead,
    String? serviceUuid,
    String? writeUuid,
    String? notifyUuid,
    String? error,
  }) {
    return NegotiationResult(
      ok: ok ?? this.ok,
      framing: framing ?? this.framing,
      responseHead: responseHead ?? this.responseHead,
      serviceUuid: serviceUuid ?? this.serviceUuid,
      writeUuid: writeUuid ?? this.writeUuid,
      notifyUuid: notifyUuid ?? this.notifyUuid,
      error: error ?? this.error,
    );
  }
}
