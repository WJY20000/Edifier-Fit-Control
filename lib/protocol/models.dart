import 'dart:typed_data';

import 'frame.dart';
import 'opcodes.dart';

/// 降噪模式。头戴只有一档降噪时统一映射为 [deep]。
enum NoiseMode { off, deep, comfort, wind, ambient, adaptive }

/// 某个降噪方言下可选的一项。
class NoiseOption {
  final NoiseMode mode;

  /// 写入设备的数值。
  final int value;

  /// 文案 key（见 lib/i18n/l10n.dart）。
  final String labelKey;

  const NoiseOption(this.mode, this.value, this.labelKey);
}

/// 降噪控制的方言（不同固件 / 型号的 payload 布局不同）。
enum AncDialect {
  /// 无降噪控制。
  none,

  /// 旧协议：[mode]，1 关 / 2 降噪 / 3 环境声。
  v1,

  /// BES v2 槽位 0x1B：1–3 都是降噪档（解码统一归到 [NoiseMode.deep]）、
  /// 4 防风 / 5 环境声 / 6 关。
  ///
  /// 花再 Evo Pro、FitBuds Turbo 的真机记录；Fit900NB Turbo 尚未验证。
  /// 注意：没有独立的「舒适」档 —— 早先的选项表里写了一个 value=2 的舒适，
  /// 但它和「1–3 都是降噪」的记录冲突，已删除。
  slotEvo,

  /// BES v2 槽位 0x10：1 深度 / 2 舒适 / 3 防风 / 4 环境声 / 5 关（W860NB PRO）。
  slotW860,

  /// BES v2 槽位 0x17：1 降噪 / 2 环境声 / 3 关（X5 Pro）。
  slotX5,

  /// Fit900NB Turbo 专用：槽位 0x2F，1 深度 / 2 舒适 / 3 防风噪 /
  /// 4 环境声（+等级）/ 5 关闭。2026-11-08 真机抓包确认。
  slotFit900,
}

extension AncDialectX on AncDialect {
  /// v2 槽位字节；v1 / none 为 null。
  int? get slot {
    switch (this) {
      case AncDialect.slotEvo:
        return AncSlot.evo;
      case AncDialect.slotW860:
        return AncSlot.w860;
      case AncDialect.slotX5:
        return AncSlot.x5;
      case AncDialect.slotFit900:
        return AncSlot.fit900;
      default:
        return null;
    }
  }

  /// UI 上可选的模式（顺序即展示顺序）。
  List<NoiseOption> get options {
    switch (this) {
      case AncDialect.v1:
        return const [
          NoiseOption(NoiseMode.deep, AncV1.anc, 'noise.deeplike'),
          NoiseOption(NoiseMode.ambient, AncV1.ambient, 'noise.ambient'),
          NoiseOption(NoiseMode.off, AncV1.off, 'noise.off'),
        ];
      case AncDialect.slotEvo:
        // 2 / 3 同样是降噪档（固件内部细分），UI 上不单独列；
        // 解码时落到下面的 1–3 → deep 兜底。
        return const [
          NoiseOption(NoiseMode.deep, 1, 'noise.deep'),
          NoiseOption(NoiseMode.wind, 4, 'noise.wind'),
          NoiseOption(NoiseMode.ambient, 5, 'noise.ambient'),
          NoiseOption(NoiseMode.off, 6, 'noise.off'),
        ];
      case AncDialect.slotW860:
        return const [
          NoiseOption(NoiseMode.deep, 1, 'noise.deep'),
          NoiseOption(NoiseMode.comfort, 2, 'noise.comfort'),
          NoiseOption(NoiseMode.wind, 3, 'noise.wind'),
          NoiseOption(NoiseMode.ambient, 4, 'noise.ambient'),
          NoiseOption(NoiseMode.off, 5, 'noise.off'),
        ];
      case AncDialect.slotX5:
        return const [
          NoiseOption(NoiseMode.deep, 1, 'noise.deep'),
          NoiseOption(NoiseMode.ambient, 2, 'noise.ambient'),
          NoiseOption(NoiseMode.off, 3, 'noise.off'),
        ];
      case AncDialect.slotFit900:
        return const [
          NoiseOption(NoiseMode.deep, 1, 'noise.deep'),
          NoiseOption(NoiseMode.comfort, 2, 'noise.comfort'),
          NoiseOption(NoiseMode.wind, 3, 'noise.wind'),
          NoiseOption(NoiseMode.ambient, 4, 'noise.ambient'),
          NoiseOption(NoiseMode.off, 5, 'noise.off'),
        ];
      case AncDialect.none:
        return const [];
    }
  }

  /// 是否支持环境声等级。
  ///
  /// - v1：`[mode][6±3]`，范围 −3..3（mEDIFIER 真机记录）；
  /// - 槽位 0x2F（Fit900NB Turbo）：`[2F 04 等级]`，等级 1..3（2026-11-08 抓包）；
  /// - 其他 v2 槽位的等级编码没见过，宁可不显示，也不发猜测出来的字节。
  bool get supportsAmbientLevel =>
      this == AncDialect.v1 || this == AncDialect.slotFit900;

  /// 生成写命令的 payload。
  List<int> encode(NoiseMode mode) {
    final option = options.where((o) => o.mode == mode).toList();
    if (option.isEmpty) return const [];
    final value = option.first.value;
    final s = slot;
    if (s == null) return [value];
    return [s, value];
  }

  /// 解析 0xCC 回包。返回 null 表示这个方言解释不了该 payload。
  NoiseMode? decode(Uint8List payload) {
    if (payload.isEmpty) return null;
    if (slot == null) {
      // v1: [mode] 或 [mode][ambientVolume]
      final value = payload[0];
      for (final o in options) {
        if (o.value == value) return o.mode;
      }
      return null;
    }
    if (payload.length < 2 || payload[0] != slot) return null;
    for (final o in options) {
      if (o.value == payload[1]) return o.mode;
    }
    // 0x2F：环境声被选中时回包会多一个等级字节 [2F, 04, level]，
    // 模式本身仍是 4，已在上面命中；这里不需要额外兜底。
    // 槽位 0x1B 的 1–3 都是降噪，未细分的档位按 deep 处理。
    if (slot == AncSlot.evo && payload[1] >= 1 && payload[1] <= 3) return NoiseMode.deep;
    return null;
  }
}

/// 内置音效（v1 只有 4 个预设）。
class EqPreset {
  final int value;
  final String labelKey;
  const EqPreset(this.value, this.labelKey);

  static const List<EqPreset> v1 = [
    EqPreset(0, 'eq.classic'),
    EqPreset(1, 'eq.pop'),
    EqPreset(2, 'eq.classical'),
    EqPreset(3, 'eq.rock'),
  ];

  /// Fit900NB Turbo 真机确认的 6 组音效（2026-11-08 抓包）。
  /// 顺序按官方 App 里的排列：人声 → 低音增强 → 动感 → 纯正 → 高音增强 → 发烧友。
  static const List<EqPreset> fit900 = [
    EqPreset(2, 'eq.vocal'),
    EqPreset(3, 'eq.bass'),
    EqPreset(1, 'eq.dynamic'),
    EqPreset(0, 'eq.pure'),
    EqPreset(4, 'eq.treble'),
    EqPreset(5, 'eq.audiophile'),
  ];

  /// 其他 BES v2 型号的 6 组预设（名称未知，显示序号）。
  static const List<EqPreset> v2 = [
    EqPreset(0, 'eq.classic'),
    EqPreset(1, 'eq.pop'),
    EqPreset(2, 'eq.classical'),
    EqPreset(3, 'eq.rock'),
    EqPreset(4, 'eq.preset5'),
    EqPreset(5, 'eq.preset6'),
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

/// 一次协商的结果，用于 UI 展示与排障。
class NegotiationResult {
  final bool ok;

  /// 命中的方言。
  final Framing? framing;

  /// 设备回包首字节（0xBB / 0xCC / 0xAA）。
  final int? responseHead;

  /// 厂商 GATT 服务 UUID。
  final String? serviceUuid;

  /// 写特征 UUID。
  final String? writeUuid;

  /// 通知特征 UUID。
  final String? notifyUuid;

  final AncDialect anc;
  final String? error;

  const NegotiationResult({
    required this.ok,
    this.framing,
    this.responseHead,
    this.serviceUuid,
    this.writeUuid,
    this.notifyUuid,
    this.anc = AncDialect.none,
    this.error,
  });

  NegotiationResult copyWith({
    bool? ok,
    Framing? framing,
    int? responseHead,
    String? serviceUuid,
    String? writeUuid,
    String? notifyUuid,
    AncDialect? anc,
    String? error,
  }) {
    return NegotiationResult(
      ok: ok ?? this.ok,
      framing: framing ?? this.framing,
      responseHead: responseHead ?? this.responseHead,
      serviceUuid: serviceUuid ?? this.serviceUuid,
      writeUuid: writeUuid ?? this.writeUuid,
      notifyUuid: notifyUuid ?? this.notifyUuid,
      anc: anc ?? this.anc,
      error: error ?? this.error,
    );
  }
}
