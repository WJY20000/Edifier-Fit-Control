import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'frame.dart';
import 'models.dart';
import 'opcodes.dart';
import 'profiles.dart';

/// 传输层抽象：BLE（Android / Windows）或测试里的假链路。
abstract class EdifierLink {
  /// 通知数据流（长度不定，可能被拆包）。
  Stream<List<int>> get incoming;

  /// 写入一段数据。
  Future<void> write(List<int> data);

  /// 单次写入的最大字节数（MTU - 3）。默认 20（BLE 最小包）。
  int get chunkSize;
}

enum LogDirection { tx, rx, info, error }

/// 一条协议日志，实验室页面直接展示 / 导出。
class LogEntry {
  final DateTime time;
  final LogDirection direction;
  final String text;

  LogEntry(this.direction, this.text) : time = DateTime.now();

  String get stamp {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

String hex(List<int> bytes) =>
    bytes.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

class _Waiter {
  final int command;
  final Completer<EdifierFrame?> completer;
  _Waiter(this.command, this.completer);
}

/// 协议引擎：负责协商方言、收发帧、维护设备状态。
class EdifierEngine {
  EdifierEngine({required this.link, required this.profile});

  final EdifierLink link;
  ModelProfile profile;

  final FrameDecoder _decoder = FrameDecoder();
  final Map<int, List<_Waiter>> _waiters = <int, List<_Waiter>>{};
  final StreamController<EdifierFrame> _frames = StreamController<EdifierFrame>.broadcast();
  final List<LogEntry> _log = <LogEntry>[];
  StreamSubscription<List<int>>? _subscription;
  Future<void> _writeChain = Future<void>.value();

  Framing framing = Framing.v1;
  AncDialect anc = AncDialect.none;
  int? responseHead;
  String? serviceUuid;
  String? writeUuid;
  String? notifyServiceUuid;
  String? notifyUuid;

  final DeviceState state = DeviceState();
  final Capabilities caps = Capabilities();

  /// 最近一次协商是否成功。
  bool ready = false;

  /// 收到的通知帧总数。用来区分「耳机不回」和「回包没进来」：
  /// 协商失败时如果是 0，说明通知链路本身有问题（订阅/通道/过滤），
  /// 而不是耳机装死。
  int receivedFrames = 0;

  List<LogEntry> get log => List<LogEntry>.unmodifiable(_log);

  /// 当前型号的音效预设表（Fit900NB Turbo 已按真机确认的顺序与名称）。
  List<EqPreset> get eqPresets =>
      profile.id == 'fit900nb-turbo' ? EqPreset.fit900 : EqPreset.v2;
  Stream<EdifierFrame> get frames => _frames.stream;

  void _record(LogDirection direction, String text) {
    _log.add(LogEntry(direction, text));
    if (_log.length > 800) {
      _log.removeRange(0, _log.length - 800);
    }
  }

  void _info(String text) => _record(LogDirection.info, text);

  /// 从外部往实验室日志里写一行（例如 GATT 服务清单）。
  void logInfo(String text) => _info(text);

  /// 开始监听通知。
  void start() {
    _subscription?.cancel();
    _subscription = link.incoming.listen(
      _onData,
      onError: (Object error) => _record(LogDirection.error, 'notify error: $error'),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    for (final list in _waiters.values) {
      for (final waiter in list) {
        if (!waiter.completer.isCompleted) waiter.completer.complete(null);
      }
    }
    _waiters.clear();
    await _frames.close();
  }

  void _onData(List<int> data) {
    _record(LogDirection.rx, hex(data));
    for (final frame in _decoder.feed(data)) {
      final payload = (frame.v2 && framing == Framing.v2Xor)
          ? EdifierCodec.unxor(frame.payload)
          : frame.payload;
      final decoded = EdifierFrame(
        head: frame.head,
        command: frame.command,
        payload: payload,
        v2: frame.v2,
      );
      responseHead ??= decoded.head;
      _record(
        LogDirection.info,
        'RX ${decoded.command.toRadixString(16).padLeft(2, '0').toUpperCase()} → [${decoded.payloadHex}]',
      );
      final list = _waiters[decoded.command];
      if (list != null && list.isNotEmpty) {
        final waiter = list.removeAt(0);
        if (!waiter.completer.isCompleted) waiter.completer.complete(decoded);
      }
      receivedFrames++;
      if (!_frames.isClosed) _frames.add(decoded);
    }
  }

  /// 发送一帧（按 chunkSize 分片，片间留一点间隔给固件缓冲）。
  Future<void> _write(int command, List<int> payload) async {
    final bytes = EdifierCodec.encode(framing, command, payload);
    _record(
      LogDirection.tx,
      'TX ${command.toRadixString(16).padLeft(2, '0').toUpperCase()} ← [${hex(payload)}] '
      '(${framing.label}, ${bytes.length}B)',
    );
    // 上一次写失败不能把整条链卡死，否则后续所有命令都会立刻抛错。
    _writeChain = _writeChain.catchError((Object _) {}).then((_) async {
      final size = link.chunkSize <= 0 ? 20 : link.chunkSize;
      for (var offset = 0; offset < bytes.length; offset += size) {
        final end = (offset + size > bytes.length) ? bytes.length : offset + size;
        await link.write(bytes.sublist(offset, end));
        if (end < bytes.length) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
    });
    return _writeChain;
  }

  /// 发命令并等回包；超时返回 null。
  Future<EdifierFrame?> request(
    int command, {
    List<int> payload = const [],
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final waiter = _Waiter(command, Completer<EdifierFrame?>());
    _waiters.putIfAbsent(command, () => <_Waiter>[]).add(waiter);
    try {
      await _write(command, payload);
      return await waiter.completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
    } catch (error) {
      _record(LogDirection.error, 'write failed: $error');
      return null;
    } finally {
      final list = _waiters[command];
      list?.remove(waiter);
      if (list != null && list.isEmpty) _waiters.remove(command);
    }
  }

  /// 裸发一帧（实验室用），不等待。
  Future<void> sendRaw(int command, List<int> payload) => _write(command, payload);

  /// 正在进行的协商。重复点「深度探测」不会并发跑两轮：
  /// 两次协商交错发命令会让 `framing` / `anc` 互相覆盖，
  /// 收尾时还可能把已经能用的状态改坏（真机上表现为「探测之后反而全都失败」）。
  Future<NegotiationResult>? _negotiating;
  bool _negotiatingDeep = false;

  /// 协商：先用哪些帧格式、再定降噪方言。
  ///
  /// [deepProbe] 为 true 时才会去试探降噪 / EQ / LDAC 等命令；
  /// 默认关闭，避免向未知固件发送不认识的控制字（部分型号会直接掉线）。
  Future<NegotiationResult> negotiate({bool deepProbe = false}) {
    final running = _negotiating;
    if (running != null) {
      if (!deepProbe || _negotiatingDeep) {
        _info('已有协商在进行，直接复用这次结果');
        return running;
      }
      // 正在跑的是「轻量协商」，而用户按的是「深度探测」：
      // 不能把轻量结果当成深度结果返回（界面上就是按了没反应），
      // 等它结束再补一次完整的。
      _info('轻量协商进行中，结束后继续做深度探测');
      return running.then((_) => negotiate(deepProbe: true));
    }
    late Future<NegotiationResult> future;
    _negotiatingDeep = deepProbe;
    future = _negotiate(deepProbe: deepProbe).whenComplete(() {
      if (identical(_negotiating, future)) {
        _negotiating = null;
        _negotiatingDeep = false;
      }
    });
    _negotiating = future;
    return future;
  }

  Future<NegotiationResult> _negotiate({bool deepProbe = false}) async {
    // 记下上一次「谈成功」的状态：重新探测失败时原样保留，
    // 不能因为一次超时就把已经能用的控件弄坏。
    final wasReady = ready;
    final prevFraming = framing;
    final prevAnc = anc;
    final prevCaps = caps.copy();
    final prevBattery = state.battery;
    ready = false;
    // 把通道写进日志：万一还是「无应答」，一眼就能看出是不是选错了服务。
    _info(
      '通道 write=${serviceUuid ?? '?'}/${writeUuid ?? '?'} '
      'notify=${notifyServiceUuid ?? serviceUuid ?? '?'}/${notifyUuid ?? '?'}',
    );
    if (notifyUuid != null && !notifyUuid!.toLowerCase().startsWith('48090001')) {
      _info('注意：通知特征不是 48090001，很可能收不到厂商回包');
    }
    await _probeFraming();
    if (!caps.battery) {
      _info(
        '电池查询无应答，协商失败（本次共收到 $receivedFrames 帧通知'
        '${receivedFrames == 0 ? '：一帧都没有，先查通道和订阅' : ''}）',
      );
      if (wasReady) {
        // 之前是好的：回滚，保持可用。
        framing = prevFraming;
        anc = prevAnc;
        caps.restore(prevCaps);
        state.battery = prevBattery;
        ready = true;
        _info('保留上一次可用的协商结果（${prevFraming.label}），控件不会消失');
        return NegotiationResult(
          ok: true,
          framing: framing,
          responseHead: responseHead,
          serviceUuid: serviceUuid,
          writeUuid: writeUuid,
          notifyUuid: notifyUuid,
          anc: anc,
          error: 're-probe failed, kept the previous working setup',
        );
      }
      return NegotiationResult(
        ok: false,
        framing: framing,
        responseHead: responseHead,
        serviceUuid: serviceUuid,
        writeUuid: writeUuid,
        notifyUuid: notifyUuid,
        error: 'device did not answer the battery query',
      );
    }

    await _readIdentity();
    // 亲手抓过包的型号（目前只有 Fit900NB Turbo）连接后直接读控制项，
    // 省掉一次手动探测；其他型号仍遵守 deepProbe 开关。
    if (deepProbe || profile.autoProbe) {
      await _probeAnc();
      await _probeOptional();
    }

    ready = true;
    return NegotiationResult(
      ok: true,
      framing: framing,
      responseHead: responseHead,
      serviceUuid: serviceUuid,
      writeUuid: writeUuid,
      notifyUuid: notifyUuid,
      anc: anc,
    );
  }

  /// 用 0xD0 电量查询确定「写出去」的帧格式。
  ///
  /// 解码是自动的（解码器靠长度字段区分 v1 / v2），这里要定的是编码：
  /// 同一代固件可能要求 payload 异或 0xA5，而异或版本在空 payload 时
  /// 与明文完全相同，所以电量查询只足以确定「v1 还是 v2 家族」。
  Future<void> _probeFraming() async {
    final tried = <Framing>[];
    for (final candidate in profile.framingOrder) {
      // v2 与 v2Xor 的空 payload 帧一字节都不差，试第二次没有意义。
      final family = candidate == Framing.v2Xor ? Framing.v2 : candidate;
      if (tried.contains(family)) continue;
      tried.add(family);
      framing = candidate;
      _info('尝试帧格式 ${candidate.label}');
      var frame = await request(
        Op.batteryGet,
        timeout: const Duration(milliseconds: 1200),
      );
      if (frame == null || frame.payload.isEmpty) {
        // 真机上连接后的第一条命令偶尔会被丢掉（CCCD 刚写完、耳机还没开始推）。
        // 再问一次；两次都没回包才算这个帧格式不对。
        frame = await request(
          Op.batteryGet,
          timeout: const Duration(milliseconds: 900),
        );
      }
      if (frame == null || frame.payload.isEmpty) continue;

      var value = frame.payload[0];
      var decided = candidate;
      // 异或固件：这里还是按明文解，45% 会变成 45^0xA5=0x88（136），
      // 超出 0..100 的合法电量范围。用同一个回包反推一次就知道了，
      // 不必再发一遍命令（省一次往返，也避免某些固件对重复查询无应答）。
      if (candidate != Framing.v1 && value > 100) {
        final plain = value ^ EdifierCodec.payloadXor;
        if (plain <= 100) {
          value = plain;
          decided = Framing.v2Xor;
        }
      }
      if (value > 100) continue;

      framing = decided;
      state.battery = value;
      caps.battery = true;
      _info('帧格式确定为 ${decided.label}，电量 ${state.battery}%');
      await _refineFlavor();
      return;
    }
    caps.battery = false;
  }

  /// 区分 v2 明文与 v2 + 0xA5 异或。
  ///
  /// 关键点：一定要先用**明文**去读，才能看到设备回包的原始字节。
  /// 否则如果型号档案本来猜的是异或，回包会被提前异或掉，判断就反了。
  /// 「读名称」的请求 payload 为空，两种编码字节相同，因此对设备无副作用。
  Future<void> _refineFlavor() async {
    if (framing == Framing.v1) return;
    final probedWithXor = framing == Framing.v2Xor;
    final assumed = probedWithXor ? Framing.v2Xor : Framing.v2;
    // 先按明文收发，才能看到设备回包的原始字节。
    framing = Framing.v2;
    final reply = await request(
      Op.nameGet,
      timeout: const Duration(milliseconds: 900),
    );
    var decided = assumed;
    if (reply != null && reply.payload.isNotEmpty) {
      final plainLooksText = _looksLikeText(reply.payload);
      final unxored = EdifierCodec.unxor(reply.payload);
      if (!plainLooksText && _looksLikeText(unxored)) {
        decided = Framing.v2Xor;
      } else if (plainLooksText) {
        decided = Framing.v2;
      }
    }
    // 从「明文」切成「异或」是个危险操作：一旦切错，之后所有命令都会失败
    // （真机上就表现为「点一次深度探测之后，选项全部失灵」）。
    // 单个回包有可能被误判，所以切过去之后再读一次设备名做验证：
    // 真异或的设备会回可读文本，明文设备被我们异或之后就是乱码。
    if (decided == Framing.v2Xor && assumed != Framing.v2Xor) {
      framing = Framing.v2Xor;
      final check = await request(
        Op.nameGet,
        timeout: const Duration(milliseconds: 800),
      );
      final confirmed = check != null && _looksLikeText(check.payload);
      if (!confirmed) {
        decided = Framing.v2;
        _info('异或回读不像设备名，判为误判，退回明文');
      }
    }
    framing = decided;
    _info('回包为${decided == Framing.v2Xor ? '异或' : '明文'}编码，采用 ${decided.label}');

    // 之前的电量是按另一个方言读的，数值不可信，重读一次。
    if (decided != assumed) {
      final again = await request(
        Op.batteryGet,
        timeout: const Duration(milliseconds: 900),
      );
      if (again != null && again.payload.isNotEmpty && again.payload[0] <= 100) {
        state.battery = again.payload[0];
      }
    }
  }

  /// 粗略判断一段字节像不像设备名：可打印 ASCII 占多数。
  static bool _looksLikeText(List<int> bytes) {
    if (bytes.isEmpty) return false;
    var printable = 0;
    var ascii = 0;
    for (final b in bytes) {
      if (b >= 0x20 && b <= 0x7E) printable++;
      if (b < 0x80) ascii++;
    }
    // 允许 1 字节长度前缀：它是控制字符，不算可打印。
    final meaningful = bytes.length - 1;
    if (meaningful <= 0) return false;
    return printable / meaningful >= 0.75 && ascii == bytes.length;
  }

  Future<void> _readIdentity() async {
    final firmware = await request(Op.firmwareGet, timeout: const Duration(milliseconds: 800));
    if (firmware != null && firmware.payload.length >= 3) {
      state.firmware =
          '${firmware.payload[0]}.${firmware.payload[1]}.${firmware.payload[2]}';
    }
    final name = await request(Op.nameGet, timeout: const Duration(milliseconds: 800));
    if (name != null && name.payload.isNotEmpty) {
      state.name = utf8.decode(name.payload, allowMalformed: true).trim();
      caps.rename = true;
    }
    // 0xC8 在 Fit900 的抓包里没出现过（官方 App 用系统 BLE 地址），
    // 对抓过包的型号跳过，UI 会回退到连接时的设备地址。
    if (profile.id != 'fit900nb-turbo') {
      final mac = await request(Op.macGet, timeout: const Duration(milliseconds: 800));
      if (mac != null && mac.payload.length >= 6) {
        state.mac = mac.payload
            .take(6)
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(':');
      }
    }
    final fingerprint = await request(Op.fingerprint, timeout: const Duration(milliseconds: 800));
    if (fingerprint != null && fingerprint.payload.isNotEmpty) {
      state.fingerprint = hex(fingerprint.payload);
    }
  }

  /// 逐个方言试探降噪查询。
  Future<void> _probeAnc() async {
    for (final dialect in profile.ancCandidates) {
      if (dialect == AncDialect.none) continue;
      final slot = dialect.slot;
      // 真机确认：Fit900NB Turbo 的降噪读命令不带任何参数（CC 空 payload）。
      final payload = (slot == null || dialect == AncDialect.slotFit900)
          ? <int>[]
          : <int>[slot];
      final frame = await request(
        Op.noiseGet,
        payload: payload,
        timeout: const Duration(milliseconds: 700),
      );
      if (frame == null) continue;
      final mode = dialect.decode(frame.payload);
      if (mode == null) continue;
      anc = dialect;
      caps.noise = true;
      caps.ambientLevel = dialect.supportsAmbientLevel;
      state.noise = mode;
      if (frame.payload.length >= 2 && dialect.slot == null) {
        state.ambientLevel = frame.payload[1] - 6;
      }
      // CC 只回 [2F, 模式]，不带环境声等级；真机上重发一次 [2F, 04]
      // 会回 [2F, 04, 等级]，这是唯一能读到等级的办法（模式不变，无副作用）。
      if (dialect == AncDialect.slotFit900 && mode == NoiseMode.ambient) {
        state.ambientLevel = await _readAmbientLevelFit900() ?? state.ambientLevel;
      }
      _info('降噪方言确定为 ${dialect.name}（模式 ${mode.name}）');
      return;
    }
    // 型号档案是真机验证过的、而且只有一个候选方言：即使这台固件不回 0xC1
    // （老固件常见），也按档案采用它。否则整块降噪控件会凭空消失，
    // 用户还以为软件坏了。
    final known = profile.ancCandidates
        .where((dialect) => dialect != AncDialect.none)
        .toList();
    if (profile.verified && known.length == 1) {
      anc = known.first;
      caps.noise = true;
      caps.ambientLevel = known.first.supportsAmbientLevel;
      _info('降噪查询无应答，按已验证档案采用 ${known.first.name}');
      return;
    }
    _info('降噪查询无应答，隐藏降噪控件');
  }

  /// 读回 Fit900 的环境声等级。
  ///
  /// 抓包里官方 App 发 `C1 [2F 04]`（不带等级）时，耳机回 `[2F 04 02]`，
  /// 也就是把当前记住的等级带回来。仅在已经处于环境声模式时调用，
  /// 因此不会改变设备状态。
  Future<int?> _readAmbientLevelFit900() async {
    final echo = await request(
      Op.noiseSet,
      payload: <int>[AncSlot.fit900, 4],
      timeout: const Duration(milliseconds: 700),
    );
    if (echo != null &&
        echo.payload.length >= 3 &&
        echo.payload[0] == AncSlot.fit900 &&
        echo.payload[1] == 4 &&
        echo.payload[2] >= 1 &&
        echo.payload[2] <= 3) {
      return echo.payload[2];
    }
    return null;
  }

  Future<void> _probeOptional() async {
    // 场景：0 音乐 / 1 游戏 / 2 空间音效（0x08 回 [场景, 0x06]）
    final scene = await request(Op.sceneGet, timeout: const Duration(milliseconds: 600));
    if (scene != null && scene.payload.isNotEmpty && scene.payload[0] <= 2) {
      caps.scene = true;
      state.scene = scene.payload[0];
    }

    // LDAC：0x91 回 [0x11, 档位]
    final ldac = await request(Op.settingGet, timeout: const Duration(milliseconds: 600));
    if (ldac != null &&
        ldac.payload.length >= 2 &&
        ldac.payload[0] == Op.settingLdac &&
        ldac.payload[1] <= 2) {
      caps.ldac = true;
      state.ldac = ldac.payload[1];
    }

    // 音效：0xD5 回 [预设号]；场景不是「音乐」时设备回 0xFF，控件置灰
    final eq = await request(Op.soundEffectGet, timeout: const Duration(milliseconds: 600));
    if (eq != null && eq.payload.isNotEmpty && eq.payload[0] != 0xFF) {
      caps.soundEffect = true;
      if (eq.payload[0] <= 5) state.soundEffect = eq.payload[0];
    } else if (eq != null && eq.payload.isNotEmpty && eq.payload[0] == 0xFF) {
      caps.soundEffect = true;
      state.soundEffect = null;
    }
  }

  /// 重新读取一次电量（廉价、安全的「心跳」）。
  Future<void> refreshBattery() async {
    final frame = await request(Op.batteryGet, timeout: const Duration(milliseconds: 900));
    if (frame != null && frame.payload.isNotEmpty && frame.payload[0] <= 100) {
      state.battery = frame.payload[0];
    }
  }

  Future<bool> setNoise(NoiseMode mode) async {
    if (anc == AncDialect.none) return false;
    var payload = anc.encode(mode);
    if (payload.isEmpty) return false;
    // 0x2F 的环境声要带等级：切过去时默认「平衡」(2)
    if (anc == AncDialect.slotFit900 && mode == NoiseMode.ambient) {
      payload = <int>[AncSlot.fit900, 4, state.ambientLevel ?? AmbientLevel.balanced];
    }
    final echo = await request(
      Op.noiseSet,
      payload: payload,
      timeout: const Duration(milliseconds: 900),
    );
    if (echo != null &&
        echo.payload.length >= 3 &&
        echo.payload[0] == AncSlot.fit900 &&
        echo.payload[1] == 4 &&
        echo.payload[2] >= 1 &&
        echo.payload[2] <= 3) {
      state.ambientLevel = echo.payload[2];
    }
    var check = await request(
      Op.noiseGet,
      payload: (anc.slot == null || anc == AncDialect.slotFit900)
          ? const <int>[]
          : <int>[anc.slot!],
      timeout: const Duration(milliseconds: 800),
    );
    if (check == null) {
      // Windows 上偶发丢一帧，重读一次再判断。
      await Future<void>.delayed(const Duration(milliseconds: 180));
      check = await request(
        Op.noiseGet,
        payload: (anc.slot == null || anc == AncDialect.slotFit900)
            ? const <int>[]
            : <int>[anc.slot!],
        timeout: const Duration(milliseconds: 900),
      );
    }
    if (check == null) {
      // 写命令本身有回包 = 设备已经收下并执行了；读回只是确认。
      // 真机上读回偶尔丢一帧，以前会直接报「操作失败」并且界面不动，
      // 看起来像点了没反应。这里相信写入的回包。
      if (echo != null) {
        state.noise = mode;
        _info('读回无应答，但写入已有回包，按已生效处理');
        return true;
      }
      _info('设置降噪失败：写入和读回都没有回包');
      return false;
    }
    final decoded = anc.decode(check.payload);
    if (decoded == null) return false;
    state.noise = decoded;
    return decoded == mode ||
        // 槽位 0x1B 的 1–3 都会解成 deep，按 1/2 切换时只比较「同类」。
        (mode == NoiseMode.comfort && decoded == NoiseMode.deep);
  }

  Future<bool> setAmbientLevel(int level) async {
    if (!caps.ambientLevel) return false;
    if (anc == AncDialect.slotFit900) {
      final clamped = level.clamp(1, 3).toInt();
      final echo = await request(
        Op.noiseSet,
        payload: <int>[AncSlot.fit900, 4, clamped],
        timeout: const Duration(milliseconds: 900),
      );
      // 写命令的回包就是 [2F, 04, 等级]；耳机不回或回短包时再读一次。
      var confirmed = echo != null &&
              echo.payload.length >= 3 &&
              echo.payload[0] == AncSlot.fit900 &&
              echo.payload[1] == 4 &&
              echo.payload[2] == clamped
          ? clamped
          : null;
      confirmed ??= await _readAmbientLevelFit900();
      state.noise = NoiseMode.ambient;
      if (confirmed != null) {
        state.ambientLevel = confirmed;
        return confirmed == clamped;
      }
      state.ambientLevel = clamped;
      return true;
    }
    final clamped = level.clamp(-3, 3).toInt();
    final payload = anc.slot == null
        ? <int>[AncV1.ambient, 6 + clamped]
        : <int>[anc.slot!, 5, 6 + clamped];
    await request(Op.noiseSet, payload: payload, timeout: const Duration(milliseconds: 900));
    state.ambientLevel = clamped;
    state.noise = NoiseMode.ambient;
    return true;
  }

  /// 场景：0 音乐 / 1 游戏 / 2 空间音效。
  Future<bool> setScene(int value) async {
    if (!caps.scene) return false;
    await request(
      Op.sceneSet,
      payload: <int>[value],
      timeout: const Duration(milliseconds: 800),
    );
    final check = await request(Op.sceneGet, timeout: const Duration(milliseconds: 700));
    if (check == null || check.payload.isEmpty) return false;
    state.scene = check.payload[0];
    // 场景变化后音效可用性也会变（非音乐时设备回 0xFF）
    await _refreshSoundEffect();
    return state.scene == value;
  }

  Future<void> _refreshSoundEffect() async {
    final eq = await request(Op.soundEffectGet, timeout: const Duration(milliseconds: 600));
    if (eq == null || eq.payload.isEmpty) return;
    if (eq.payload[0] == 0xFF) {
      state.soundEffect = null;
    } else if (eq.payload[0] <= 5) {
      state.soundEffect = eq.payload[0];
    }
  }

  /// LDAC：0 关 / 1 44.1&48k / 2 96k。
  Future<bool> setLdac(int value) async {
    if (!caps.ldac) return false;
    await request(
      Op.settingSet,
      payload: <int>[Op.settingLdac, value],
      timeout: const Duration(milliseconds: 900),
    );
    final check = await request(Op.settingGet, timeout: const Duration(milliseconds: 900));
    if (check != null &&
        check.payload.length >= 2 &&
        check.payload[0] == Op.settingLdac &&
        check.payload[1] <= 2) {
      state.ldac = check.payload[1];
    }
    return true;
  }

  Future<bool> setSoundEffect(int value) async {
    if (!caps.soundEffect) return false;
    await request(
      Op.soundEffectSet,
      payload: <int>[value],
      timeout: const Duration(milliseconds: 900),
    );
    final check = await request(Op.soundEffectGet, timeout: const Duration(milliseconds: 700));
    if (check == null || check.payload.isEmpty) return false;
    if (check.payload[0] == 0xFF) {
      // 场景不是「音乐」时设备拒绝切换音效
      state.soundEffect = null;
      return false;
    }
    state.soundEffect = check.payload[0];
    return state.soundEffect == value;
  }

  Future<bool> rename(String name) async {
    if (!caps.rename) return false;
    final bytes = _utf8Capped(name, 30);
    await request(Op.nameSet, payload: bytes, timeout: const Duration(milliseconds: 900));
    // 记录真正发出去的名字（可能被 30 字节截断），避免界面显示一个设备上不存在的名字。
    state.name = utf8.decode(bytes, allowMalformed: true).trim();
    return true;
  }

  /// 按 UTF-8 边界把字符串截到不超过 [maxBytes] 字节。
  ///
  /// 直接 `utf8.encode(name).take(30)` 会把一个三字节的汉字切成两半，
  /// 发过去的名字就不是合法 UTF-8，部分固件会整条丢弃。
  static Uint8List _utf8Capped(String text, int maxBytes) {
    final all = utf8.encode(text);
    if (all.length <= maxBytes) return Uint8List.fromList(all);
    var cut = maxBytes;
    while (cut > 0 && (all[cut] & 0xC0) == 0x80) {
      cut--;
    }
    return Uint8List.fromList(all.sublist(0, cut));
  }

  Future<void> powerOff() async {
    await request(Op.powerOff, timeout: const Duration(milliseconds: 400));
  }

  Future<void> disconnectDevice() async {
    await request(Op.disconnect, timeout: const Duration(milliseconds: 400));
  }
}
