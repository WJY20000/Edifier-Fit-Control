import 'dart:async';
import 'dart:convert';

import 'package:edifier_fit/protocol/engine.dart';
import 'package:edifier_fit/protocol/frame.dart';
import 'package:edifier_fit/protocol/models.dart';
import 'package:edifier_fit/protocol/opcodes.dart';
import 'package:edifier_fit/protocol/profiles.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一台「假耳机」：按 2026-11-08 真机抓包的行为回答命令。
class FakeHeadset implements EdifierLink {
  FakeHeadset({
    this.acceptsV2 = true,
    this.acceptsV1 = false,
    this.xor = false,
    this.ancSlot = AncSlot.fit900,
    this.silent = false,
    this.name = 'EDIFIER Fit900NB Turbo',
  });

  final bool acceptsV2;
  final bool acceptsV1;
  bool xor;
  final int? ancSlot;
  final bool silent;
  final String name;

  // 真机初始状态（抓包起点 14:29:36）：深度降噪、环境声等级记 2、
  // 音效 2（人声）、场景音乐、LDAC 96k、电量 45%。
  int noiseMode = 1; // 1 = 深度
  int ambientLevel = 2;
  int scene = 0;
  int eq = 2;
  int ldac = 2;
  int battery = 45;
  int firmwareMajor = 1;
  int firmwareMinor = 0;
  int firmwarePatch = 3;

  final StreamController<List<int>> _out = StreamController<List<int>>.broadcast(sync: true);
  final List<int> _buffer = <int>[];
  int writeCalls = 0;

  @override
  Stream<List<int>> get incoming => _out.stream;

  @override
  int get chunkSize => 20;

  void _emit(List<int> bytes) {
    if (!_out.isClosed) _out.add(bytes);
  }

  List<int> _v1(int command, List<int> payload) {
    final body = <int>[0xBB, payload.length + 1, command, ...payload];
    final sum = EdifierCodec.checksum16(body);
    return [...body, (sum >> 8) & 0xFF, sum & 0xFF];
  }

  List<int> _v2(int command, List<int> payload) {
    final body = <int>[
      0xBB,
      EdifierCodec.appCode,
      command,
      (payload.length >> 8) & 0xFF,
      payload.length & 0xFF,
    ];
    for (final b in payload) {
      body.add(xor ? b ^ EdifierCodec.payloadXor : b);
    }
    var sum = 0;
    for (final b in body) {
      sum = (sum + b) & 0xFF;
    }
    body.add(sum);
    return body;
  }

  void _reply(int command, List<int> payload, {required bool v2}) {
    if (silent) return;
    _emit(v2 ? _v2(command, payload) : _v1(command, payload));
  }

  void _handle(int command, List<int> payload, {required bool v2}) {
    if (command == Op.batteryGet) {
      _reply(command, [battery], v2: v2);
      return;
    }
    if (command == Op.nameGet) {
      _reply(command, utf8.encode(name), v2: v2);
      return;
    }
    if (command == Op.firmwareGet) {
      _reply(command, [firmwareMajor, firmwareMinor, firmwarePatch], v2: v2);
      return;
    }
    if (command == Op.macGet) {
      _reply(command, [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF], v2: v2);
      return;
    }
    if (command == Op.fingerprint) {
      _reply(command, List<int>.generate(25, (i) => i), v2: v2);
      return;
    }
    if (command == Op.noiseGet) {
      if (ancSlot == null) return;
      // 真机 CC 只回 [槽位, 模式]，环境声时也不带等级（抓包 14:32:34）
      _reply(command, [ancSlot!, noiseMode], v2: v2);
      return;
    }
    if (command == Op.noiseSet) {
      if (ancSlot == null || payload.isEmpty) return;
      if (payload[0] != ancSlot) return;
      if (payload.length >= 3) {
        noiseMode = payload[1];
        ambientLevel = payload[2];
      } else if (payload.length >= 2) {
        noiseMode = payload[1];
      }
      // 真机：环境声的回包带等级 —— [2F, 04] 回 [2F, 04, 记住的等级]（抓包 14:30:30）
      if (ancSlot == AncSlot.fit900 && noiseMode == 4) {
        _reply(command, [AncSlot.fit900, 4, ambientLevel], v2: v2);
      } else {
        _reply(command, [ancSlot!, noiseMode], v2: v2);
      }
      return;
    }
    if (command == Op.sceneGet) {
      _reply(command, [scene, 0x06], v2: v2);
      return;
    }
    if (command == Op.sceneSet) {
      if (payload.isEmpty) return;
      scene = payload[0];
      _reply(command, [scene, 0x06], v2: v2);
      return;
    }
    if (command == Op.soundEffectGet) {
      // 非音乐场景下设备回 0xFF
      _reply(command, [scene == 0 ? eq : 0xFF], v2: v2);
      return;
    }
    if (command == Op.soundEffectSet) {
      if (scene != 0) {
        _reply(command, [0xFF], v2: v2);
        return;
      }
      if (payload.isNotEmpty) eq = payload[0];
      _reply(command, [0x01], v2: v2);
      return;
    }
    if (command == Op.settingGet) {
      _reply(command, [Op.settingLdac, ldac], v2: v2);
      return;
    }
    if (command == Op.settingSet) {
      if (payload.length < 2 || payload[0] != Op.settingLdac) return;
      ldac = payload[1];
      _reply(command, [0x0C, ldac], v2: v2);
      return;
    }
  }

  @override
  Future<void> write(List<int> data) async {
    writeCalls++;
    _buffer.addAll(data);
    while (_buffer.length >= 2 && _buffer[0] == EdifierCodec.requestHead) {
      if (_buffer[1] == EdifierCodec.appCode) {
        if (_buffer.length < 5) return;
        final length = (_buffer[3] << 8) | _buffer[4];
        final total = length + 6;
        if (_buffer.length < total) return;
        final raw = _buffer.sublist(5, 5 + length);
        final command = _buffer[2];
        _buffer.removeRange(0, total);
        if (!acceptsV2) continue;
        final payload = xor ? raw.map((b) => b ^ EdifierCodec.payloadXor).toList() : raw.toList();
        _handle(command, payload, v2: true);
        continue;
      }
      final length = _buffer[1];
      if (length < 1) {
        _buffer.removeAt(0);
        continue;
      }
      final total = length + 4;
      if (_buffer.length < total) return;
      final command = _buffer[2];
      final payload = _buffer.sublist(3, total - 2);
      _buffer.removeRange(0, total);
      if (!acceptsV1) continue;
      _handle(command, payload, v2: false);
    }
  }

  Future<void> close() => _out.close();
}

void main() {
  test('Fit900NB Turbo：v2 明文 + 0x2F 槽位，一次协商拿到全部控制项', () async {
    final device = FakeHeadset();
    final engine = EdifierEngine(link: device, profile: Profiles.fit900nbTurbo);
    engine.start();

    final result = await engine.negotiate(deepProbe: true);

    expect(result.ok, isTrue);
    expect(engine.framing, Framing.v2);
    expect(engine.anc, AncDialect.slotFit900);
    expect(engine.state.battery, 45);
    expect(engine.state.firmware, '1.0.3');
    expect(engine.state.name, 'EDIFIER Fit900NB Turbo');
    expect(engine.state.noise, NoiseMode.deep);
    expect(engine.caps.noise, isTrue);
    expect(engine.caps.ambientLevel, isTrue);
    expect(engine.caps.scene, isTrue);
    expect(engine.caps.soundEffect, isTrue);
    expect(engine.caps.ldac, isTrue);
    expect(engine.state.scene, 0);
    expect(engine.state.soundEffect, 2);
    expect(engine.state.ldac, 2);
    await engine.dispose();
    await device.close();
  });

  test('已验证型号连接后自动读控制项', () async {
    final device = FakeHeadset();
    final engine = EdifierEngine(link: device, profile: Profiles.fit900nbTurbo);
    engine.start();

    final result = await engine.negotiate(); // 不传 deepProbe

    expect(result.ok, isTrue);
    expect(engine.caps.noise, isTrue);
    expect(engine.caps.scene, isTrue);
    expect(engine.caps.ldac, isTrue);
    expect(engine.caps.soundEffect, isTrue);
    await engine.dispose();
    await device.close();
  });

  test('未识别型号仍不自动发控制字', () async {
    final device = FakeHeadset();
    final engine = EdifierEngine(link: device, profile: Profiles.generic);
    engine.start();

    final result = await engine.negotiate();

    expect(result.ok, isTrue);
    expect(engine.caps.noise, isFalse);
    // 只发了探活与身份查询，没有发控制字
    expect(engine.caps.scene, isFalse);
    await engine.dispose();
    await device.close();
  });

  test('开机就在环境声：借助 C1 [2F 04] 回读等级', () async {
    final device = FakeHeadset();
    device.noiseMode = 4; // 环境声
    device.ambientLevel = 3; // 突出背景声
    final engine = EdifierEngine(link: device, profile: Profiles.fit900nbTurbo);
    engine.start();
    await engine.negotiate(deepProbe: true);

    expect(engine.state.noise, NoiseMode.ambient);
    expect(engine.state.ambientLevel, AmbientLevel.background);
    await engine.dispose();
    await device.close();
  });

  test('三档降噪 + 环境声等级按真机数值写入', () async {
    final device = FakeHeadset();
    final engine = EdifierEngine(link: device, profile: Profiles.fit900nbTurbo);
    engine.start();
    await engine.negotiate(deepProbe: true);

    expect(await engine.setNoise(NoiseMode.deep), isTrue);
    expect(device.noiseMode, 1);
    expect(await engine.setNoise(NoiseMode.comfort), isTrue);
    expect(device.noiseMode, 2);
    expect(await engine.setNoise(NoiseMode.wind), isTrue);
    expect(device.noiseMode, 3);

    expect(await engine.setNoise(NoiseMode.ambient), isTrue);
    expect(device.noiseMode, 4);
    expect(engine.state.noise, NoiseMode.ambient);

    expect(await engine.setAmbientLevel(AmbientLevel.vocal), isTrue);
    expect(device.ambientLevel, 1);
    expect(await engine.setAmbientLevel(AmbientLevel.background), isTrue);
    expect(device.ambientLevel, 3);
    expect(engine.state.ambientLevel, 3);

    expect(await engine.setNoise(NoiseMode.off), isTrue);
    expect(device.noiseMode, 5);
    await engine.dispose();
    await device.close();
  });

  test('场景切换会连带刷新音效可用性', () async {
    final device = FakeHeadset();
    final engine = EdifierEngine(link: device, profile: Profiles.fit900nbTurbo);
    engine.start();
    await engine.negotiate(deepProbe: true);

    expect(await engine.setScene(Scene.game), isTrue);
    expect(device.scene, 1);
    // 非音乐场景：设备回 0xFF，音效置为不可用
    expect(engine.state.soundEffect, isNull);
    expect(await engine.setSoundEffect(3), isFalse);

    expect(await engine.setScene(Scene.spatial), isTrue);
    expect(device.scene, 2);

    expect(await engine.setScene(Scene.music), isTrue);
    expect(engine.state.soundEffect, 2);
    expect(await engine.setSoundEffect(5), isTrue);
    expect(device.eq, 5);
    await engine.dispose();
    await device.close();
  });

  test('音效预设表按真机名称与顺序', () {
    expect(EqPreset.fit900.map((p) => p.value).toList(), [2, 3, 1, 0, 4, 5]);
    expect(EqPreset.fit900.first.labelKey, 'eq.vocal');
    expect(EqPreset.fit900.last.labelKey, 'eq.audiophile');
  });

  test('LDAC 走 0x92/0x91 的 0x11 子项', () async {
    final device = FakeHeadset();
    final engine = EdifierEngine(link: device, profile: Profiles.fit900nbTurbo);
    engine.start();
    await engine.negotiate(deepProbe: true);

    expect(engine.state.ldac, 2);
    expect(await engine.setLdac(LdacMode.auto), isTrue);
    expect(device.ldac, 1);
    expect(engine.state.ldac, 1);
    expect(await engine.setLdac(LdacMode.off), isTrue);
    expect(device.ldac, 0);
    expect(await engine.setLdac(LdacMode.hiRes), isTrue);
    expect(engine.state.ldac, 2);
    await engine.dispose();
    await device.close();
  });

  test('异或固件：靠回包是否可读自动切到 v2Xor', () async {
    final device = FakeHeadset(xor: true);
    final engine = EdifierEngine(link: device, profile: Profiles.fit900nbTurbo);
    engine.start();

    final result = await engine.negotiate();

    expect(result.ok, isTrue);
    expect(engine.framing, Framing.v2Xor);
    expect(engine.state.battery, 45);
    expect(engine.state.name, 'EDIFIER Fit900NB Turbo');
    await engine.dispose();
    await device.close();
  });

  test('只认 v1 的老固件：回退到 v1 方言', () async {
    final device = FakeHeadset(acceptsV2: false, acceptsV1: true, ancSlot: null);
    final engine = EdifierEngine(link: device, profile: Profiles.w820nb);
    engine.start();

    final result = await engine.negotiate(deepProbe: true);

    expect(result.ok, isTrue);
    expect(engine.framing, Framing.v1);
    expect(engine.anc, AncDialect.v1);
    expect(engine.caps.noise, isTrue);
    await engine.dispose();
    await device.close();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('完全不应答的设备：协商失败但可安全释放', () async {
    final device = FakeHeadset(silent: true);
    final engine = EdifierEngine(link: device, profile: Profiles.fit900nbTurbo);
    engine.start();

    final result = await engine.negotiate();

    expect(result.ok, isFalse);
    expect(result.error, isNotNull);
    expect(engine.caps.noise, isFalse);
    await engine.dispose();
    await device.close();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('长 payload 会按 MTU 分片写出', () async {
    final device = FakeHeadset();
    final engine = EdifierEngine(link: device, profile: Profiles.fit900nbTurbo);
    engine.start();
    await engine.negotiate();
    device.writeCalls = 0;

    await engine.sendRaw(Op.nameSet, List<int>.filled(45, 0x41));

    expect(device.writeCalls, greaterThan(1));
    await engine.dispose();
    await device.close();
  });
}
