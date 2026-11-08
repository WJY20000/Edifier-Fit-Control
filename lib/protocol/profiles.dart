import 'frame.dart';
import 'models.dart';

/// 型号档案：决定「先试哪种帧格式」和「按键位解释降噪」。
///
/// 刻意做成数据表：新增型号只要加一条记录，不用改引擎。
class ModelProfile {
  final String id;
  final String displayName;

  /// 归一化后的名字关键字（小写、只保留字母数字）。
  /// 例如 "Fit900NB Turbo" 归一化为 "fit900nbturbo"。
  final List<String> matchKeys;

  /// 协商时依次尝试的帧格式。
  ///
  /// 顺序很重要：对只认 BES v2 的固件发 v1 帧有概率直接掉线
  /// （社区记录：W830NB 收到 v1 无应答并断开），所以已知是新协议的
  /// 型号绝不把 v1 放在前面。
  final List<Framing> framingOrder;

  /// 降噪方言候选，按可能性排序；仅深度探测时逐个验证。
  final List<AncDialect> ancCandidates;

  /// 是否有真机证据。false 时 UI 会提示「未验证」。
  final bool verified;

  /// 连接后是否自动读一遍控制项（降噪 / 场景 / 音效 / LDAC）。
  ///
  /// 只对本项目亲手抓过包的型号打开：这些命令字都已确认无副作用。
  /// 其他型号仍要用户手动点「立即探测控制项」，免得把陌生固件发重启。
  final bool autoProbe;

  /// 证据来源说明，显示在「关于」里。
  final String evidence;

  const ModelProfile({
    required this.id,
    required this.displayName,
    required this.matchKeys,
    required this.framingOrder,
    required this.ancCandidates,
    required this.verified,
    required this.evidence,
    this.autoProbe = false,
  });

  /// 名称匹配得分：0 不匹配，越高越具体。
  int match(String normalizedName) {
    var score = 0;
    for (final key in matchKeys) {
      if (key.isEmpty) continue;
      if (normalizedName == key) {
        score = score > 100 ? score : 100;
      } else if (normalizedName.contains(key)) {
        score = score > 60 ? score : 60;
      }
    }
    return score;
  }
}

/// 归一化 BLE 名称：小写，去掉品牌词与非字母数字。
String normalizeDeviceName(String? name) {
  if (name == null || name.isEmpty) return '';
  var value = name.toLowerCase();
  for (final brand in ['edifier', '漫步者']) {
    value = value.replaceAll(brand, '');
  }
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final ch = String.fromCharCode(rune);
    final code = ch.codeUnitAt(0);
    final isDigit = code >= 0x30 && code <= 0x39;
    final isLower = code >= 0x61 && code <= 0x7A;
    if (isDigit || isLower) buffer.write(ch);
  }
  return buffer.toString();
}

/// 已知型号表。
class Profiles {
  /// 目标型号：漫步者 Fit900NB Turbo（2026，头戴，五档降噪 + 6 组 EQ + LDAC）。
  ///
  /// 官方 App 的协议没有公开记录；同代 FitBuds Turbo 是 BES v2 明文、
  /// 降噪槽位 0x1B，因此先按这一族去试，失败再退到异或版本。
  static const ModelProfile fit900nbTurbo = ModelProfile(
    id: 'fit900nb-turbo',
    displayName: 'EDIFIER Fit900NB Turbo',
    matchKeys: ['fit900nbturbo', 'fit900nb'],
    framingOrder: [Framing.v2],
    ancCandidates: [AncDialect.slotFit900],
    verified: true,
    autoProbe: true,
    evidence:
        '2026-11-08 真机 HCI 抓包（固件 1.0.3）：BES v2 明文帧，降噪槽位 0x2F，'
        '环境声 1–3，场景 0/1/2，音效 0–5，LDAC 走 0x91/0x92 的 0x11 子项。',
  );

  /// 同代真无线（社区真机记录），用于对照。
  static const ModelProfile fitbudsTurbo = ModelProfile(
    id: 'fitbuds-turbo',
    displayName: 'EDIFIER FitBuds Turbo',
    matchKeys: ['fitbudsturbo'],
    framingOrder: [Framing.v2, Framing.v2Xor],
    ancCandidates: [AncDialect.slotEvo],
    verified: true,
    evidence: 'HyperEars PR #62 真机记录：BES v2 明文、槽位 0x1B、支持游戏模式。',
  );

  static const ModelProfile w830nb = ModelProfile(
    id: 'w830nb',
    displayName: 'EDIFIER W830NB',
    matchKeys: ['w830nb'],
    framingOrder: [Framing.v2Xor, Framing.v2],
    ancCandidates: [AncDialect.slotW860, AncDialect.slotEvo],
    verified: true,
    evidence: 'devicePEQ 抓包：BES v2 + 异或；v1 帧会掉线，降噪槽位未见记录。',
  );

  static const ModelProfile w860nbPro = ModelProfile(
    id: 'w860nb-pro',
    displayName: 'EDIFIER W860NB PRO',
    matchKeys: ['w860nbpro'],
    framingOrder: [Framing.v2Xor, Framing.v2],
    ancCandidates: [AncDialect.slotW860],
    verified: true,
    evidence: 'HyperEars 真机验证：BES v2 + 异或，降噪槽位 0x10。',
  );

  static const ModelProfile w820nb = ModelProfile(
    id: 'w820nb',
    displayName: 'EDIFIER W820NB',
    matchKeys: ['w820nb', 'w820nbplus', 'w820nbdoublegold'],
    framingOrder: [Framing.v1, Framing.v2],
    ancCandidates: [AncDialect.v1],
    verified: true,
    evidence: 'mEDIFIER 真机测试与完整命令抓包（v1 协议）。',
  );

  /// 兜底：能连上就至少能看电量。
  static const ModelProfile generic = ModelProfile(
    id: 'generic-edifier',
    displayName: 'EDIFIER（未识别型号）',
    matchKeys: [],
    framingOrder: [Framing.v1, Framing.v2, Framing.v2Xor],
    ancCandidates: [
      AncDialect.slotFit900,
      AncDialect.v1,
      AncDialect.slotEvo,
      AncDialect.slotW860,
    ],
    verified: false,
    evidence: '未识别型号：按最常见的 v1 协议尝试，控制项需在实验室里手动验证。',
  );

  static const List<ModelProfile> all = [
    fit900nbTurbo,
    fitbudsTurbo,
    w830nb,
    w860nbPro,
    w820nb,
    generic,
  ];

  /// 按名称挑最具体的档案。
  static ModelProfile resolve(String? name) {
    final normalized = normalizeDeviceName(name);
    ModelProfile best = generic;
    var bestScore = 0;
    for (final profile in all) {
      final score = profile.match(normalized);
      if (score > bestScore) {
        best = profile;
        bestScore = score;
      }
    }
    return best;
  }
}
