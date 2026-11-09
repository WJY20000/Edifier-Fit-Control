import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'frame.dart';
import 'models.dart';
import 'opcodes.dart';

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

/// 协议引擎：只服务 Fit900NB Turbo —— 固定明文 v2 帧，收发并维护设备状态。
class EdifierEngine {
  EdifierEngine({required this.link}) {
    // 这台耳机一定有降噪与环境声等级：两个控件不依赖「读取成功」才出现，
    // 否则一次丢包就会让用户以为软件坏了。
    caps.noise = true;
    caps.ambientLevel = true;
  }

  final EdifierLink link;

  final FrameDecoder _decoder = FrameDecoder();
  final Map<int, List<_Waiter>> _waiters = <int, List<_Waiter>>{};
  final StreamController<EdifierFrame> _frames = StreamController<EdifierFrame>.broadcast();
  final List<LogEntry> _log = <LogEntry>[];
  StreamSubscription<List<int>>? _subscription;
  Future<void> _writeChain = Future<void>.value();

  /// 这台耳机只认 BES v2 明文帧（2026-11-08 真机抓包，固件 1.0.3）。
  /// 字段保留只为日志显示；不再协商、不会切换。
  final Framing framing = Framing.v2;
  int? responseHead;
  String? serviceUuid;
  String? writeUuid;
  String? notifyServiceUuid;
  String? notifyUuid;

  final DeviceState state = DeviceState();
  final Capabilities caps = Capabilities();

  /// 最近一次读取是否拿到有效回包。
  bool ready = false;

  /// 收到的通知帧总数。用来区分「耳机不回」和「回包没进来」：
  /// 读不到电量时如果是 0，说明通知链路本身有问题（订阅/通道/过滤），
  /// 而不是耳机装死。
  int receivedFrames = 0;

  List<LogEntry> get log => List<LogEntry>.unmodifiable(_log);

  /// 音效预设表（真机确认的顺序与名称）。
  List<EqPreset> get eqPresets => EqPreset.fit900;
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
      final payload = frame.payload;
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

  /// 正在进行的读取。重复触发不会并发跑两轮：
  /// 两次读取交错发命令会让状态互相覆盖，收尾时还可能把已经能用的状态改坏
  /// （真机上表现为「重新探测之后反而全都失败」）。
  Future<NegotiationResult>? _negotiating;

  /// 读取设备状态：电量 → 身份 → 降噪 / 场景 / 音效 / LDAC。
  ///
  /// 只针对 Fit900NB Turbo，命令字全部来自真机抓包，
  /// 所以不需要「试探别的型号」，也不再区分轻量 / 深度。
  Future<NegotiationResult> negotiate() {
    final running = _negotiating;
    if (running != null) {
      _info('已有读取在进行，直接复用这次结果');
      return running;
    }
    late Future<NegotiationResult> future;
    future = _negotiate().whenComplete(() {
      if (identical(_negotiating, future)) _negotiating = null;
    });
    _negotiating = future;
    return future;
  }

  Future<NegotiationResult> _negotiate() async {
    // 记下上一次「谈成功」的状态：重新读取失败时原样保留，
    // 不能因为一次超时就把已经能用的控件弄坏。
    final wasReady = ready;
    // 这一轮收到了多少帧：日志里说「本轮共收到 N 帧」必须是本轮的增量，
    // 否则第二次重新读取失败时会报出上一轮累积的数字，把排障带偏。
    final framesAtStart = receivedFrames;
    final prevCaps = caps.copy();
    final prevBattery = state.battery;
    ready = false;
    // 把通道写进日志：万一「无应答」，一眼就能看出是不是选错了服务。
    _info(
      '通道 write=${serviceUuid ?? '?'}/${writeUuid ?? '?'} '
      'notify=${notifyServiceUuid ?? serviceUuid ?? '?'}/${notifyUuid ?? '?'}',
    );
    if (notifyUuid != null && !notifyUuid!.toLowerCase().startsWith('48090001')) {
      _info('注意：通知特征不是 48090001，很可能收不到厂商回包');
    }
    await _readBattery();
    if (!caps.battery) {
      _info(
        '电池查询无应答（本轮共收到 ${receivedFrames - framesAtStart} 帧通知'
        '${receivedFrames == 0 ? '：一帧都没有，先查通道和订阅' : ''}）',
      );
      if (wasReady) {
        // 之前是好的：回滚，保持可用。
        caps.restore(prevCaps);
        state.battery = prevBattery;
        ready = true;
        _info('保留上一次的状态，控件不会消失');
        return NegotiationResult(
          ok: true,
          framing: framing,
          responseHead: responseHead,
          serviceUuid: serviceUuid,
          writeUuid: writeUuid,
          notifyUuid: notifyUuid,
          error: 're-read failed, kept the previous working setup',
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
    await _readNoise();
    await _readOptional();

    ready = true;
    return NegotiationResult(
      ok: true,
      framing: framing,
      responseHead: responseHead,
      serviceUuid: serviceUuid,
      writeUuid: writeUuid,
      notifyUuid: notifyUuid,
    );
  }

  /// 读一次电量。
  ///
  /// 0xD0 不带 payload，是最安全的一条查询；回包首字节就是百分比。
  /// 连接后的第一条命令偶尔会被丢掉（CCCD 刚写完、耳机还没开始推），
  /// 所以没回包时再问一次。
  Future<void> _readBattery() async {
    var frame = await request(Op.batteryGet, timeout: const Duration(milliseconds: 1200));
    if (frame == null || frame.payload.isEmpty) {
      frame = await request(Op.batteryGet, timeout: const Duration(milliseconds: 900));
    }
    if (frame == null || frame.payload.isEmpty) {
      caps.battery = false;
      return;
    }
    final value = frame.payload[0];
    if (value > 100) {
      _info('电量回包超出 0–100（0x${value.toRadixString(16).toUpperCase()}），按无应答处理');
      caps.battery = false;
      return;
    }
    caps.battery = true;
    state.battery = value;
    _info('电量 ${state.battery}%');
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
    // 0xC8 在这台耳机的抓包里没出现过（官方 App 用的是系统 BLE 地址），
    // 不发这条查询；界面直接显示连接时用的地址。
    final fingerprint = await request(Op.fingerprint, timeout: const Duration(milliseconds: 800));
    if (fingerprint != null && fingerprint.payload.isNotEmpty) {
      state.fingerprint = hex(fingerprint.payload);
    }
  }

  /// 读当前降噪档位。
  ///
  /// 读命令不带 payload；只回 `[2F, 档位]`。
  /// 这台耳机只支持一个型号，所以无论有没有回包，降噪控件都照常显示
  /// （以前「没回包就整块隐藏」会让用户以为软件坏了）。
  Future<void> _readNoise() async {
    final frame = await request(
      Op.noiseGet,
      timeout: const Duration(milliseconds: 700),
    );
    if (frame == null) {
      _info('降噪查询无应答，控件保留，可点「重新读取」再试');
      return;
    }
    final mode = decodeNoise(frame.payload);
    if (mode == null) {
      _info('降噪回包无法解析：${hex(frame.payload)}');
      return;
    }
    state.noise = mode;
    // CC 只回 [2F, 模式]，不带环境声等级；重发一次 [2F, 04]
    // 会回 [2F, 04, 等级]，这是唯一能读到等级的办法（模式不变，无副作用）。
    if (mode == NoiseMode.ambient) {
      state.ambientLevel = await _readAmbientLevel() ?? state.ambientLevel;
    }
    _info('降噪档位 ${mode.name}');
  }

  /// 读回 Fit900 的环境声等级。
  ///
  /// 抓包里官方 App 发 `C1 [2F 04]`（不带等级）时，耳机回 `[2F 04 02]`，
  /// 也就是把当前记住的等级带回来。仅在已经处于环境声模式时调用，
  /// 因此不会改变设备状态。
  Future<int?> _readAmbientLevel() async {
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

  Future<void> _readOptional() async {
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
    if (!caps.noise) return false;
    final payload = noisePayload(
      mode,
      ambientLevel: state.ambientLevel ?? AmbientLevel.balanced,
    );
    if (payload.isEmpty) return false;
    final echo = await request(
      Op.noiseSet,
      payload: payload,
      timeout: const Duration(milliseconds: 900),
    );
    // 切到环境声时，回包会带上耳机记住的等级 [2F, 04, 等级]。
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
      timeout: const Duration(milliseconds: 800),
    );
    if (check == null) {
      // Windows 上偶发丢一帧，重读一次再判断。
      await Future<void>.delayed(const Duration(milliseconds: 180));
      check = await request(
        Op.noiseGet,
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
    final decoded = decodeNoise(check.payload);
    if (decoded == null) return false;
    state.noise = decoded;
    return decoded == mode;
  }

  Future<bool> setAmbientLevel(int level) async {
    if (!caps.ambientLevel) return false;
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
    confirmed ??= await _readAmbientLevel();
    state.noise = NoiseMode.ambient;
    if (confirmed != null) {
      state.ambientLevel = confirmed;
      return confirmed == clamped;
    }
    state.ambientLevel = clamped;
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
