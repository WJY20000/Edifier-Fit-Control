import 'dart:async';
import 'dart:convert';

import 'package:edifier_fit/protocol/engine.dart';
import 'package:edifier_fit/protocol/frame.dart';
import 'package:edifier_fit/protocol/models.dart';
import 'package:edifier_fit/protocol/opcodes.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一台「假耳机」：按 2026-11-08 真机抓包的行为回答命令。
///
/// 只实现 Fit900NB Turbo 这一套命令（BES v2 明文、降噪槽位 0x2F）——
/// 应用也只发这一套。
class FakeHeadset implements EdifierLink {
  FakeHeadset({
    this.silent = false,
    this.replyNoise = true,
    this.name = 'EDIFIER Fit900NB Turbo',
  });

  bool silent;

  /// 降噪查询（0xCC）是否回包。用来模拟「丢帧」。
  final bool replyNoise;

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

  /// 发出去的每一帧（命令行 + payload），用于断言「只发 Fit900 的命令」。
  final List<(int, List<int>)> sent = <(int, List<int>)>[];

  @override
  Stream<List<int>> get incoming => _out.stream;

  @override
  int get chunkSize => 20;

  void _emit(List<int> bytes) {
    if (!_out.isClosed) _out.add(bytes);
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
      body.add(b);
    }
    var sum = 0;
    for (final b in body) {
      sum = (sum + b) & 0xFF;
    }
    body.add(sum);
    return body;
  }

  void _reply(int command, List<int> payload) {
    if (silent) return;
    _emit(_v2(command, payload));
  }

  void _handle(int command, List<int> payload) {
    if (command == Op.batteryGet) {
      _reply(command, [battery]);
      return;
    }
    if (command == Op.nameGet) {
      _reply(command, utf8.encode(name));
      return;
    }
    if (command == Op.firmwareGet) {
      _reply(command, [firmwareMajor, firmwareMinor, firmwarePatch]);
      return;
    }
    if (command == Op.fingerprint) {
      _reply(command, List<int>.generate(25, (i) => i));
      return;
    }
    if (command == Op.noiseGet) {
      if (!replyNoise) return;
      // 真机 CC 只回 [槽位, 模式]，环境声时也不带等级（抓包 14:32:34）
      _reply(command, [AncSlot.fit900, noiseMode]);
      return;
    }
    if (command == Op.noiseSet) {
      if (payload.isEmpty || payload[0] != AncSlot.fit900) return;
      if (payload.length >= 3) {
        noiseMode = payload[1];
        ambientLevel = payload[2];
      } else if (payload.length >= 2) {
        noiseMode = payload[1];
      }
      // 真机：环境声的回包带等级 —— [2F, 04] 回 [2F, 04, 记住的等级]（抓包 14:30:30）
      if (noiseMode == 4) {
        _reply(command, [AncSlot.fit900, 4, ambientLevel]);
      } else {
        _reply(command, [AncSlot.fit900, noiseMode]);
      }
      return;
    }
    if (command == Op.sceneGet) {
      _reply(command, [scene, 0x06]);
      return;
    }
    if (command == Op.sceneSet) {
      if (payload.isEmpty) return;
      scene = payload[0];
      _reply(command, [scene, 0x06]);
      return;
    }
    if (command == Op.soundEffectGet) {
      // 非音乐场景下设备回 0xFF
      _reply(command, [scene == 0 ? eq : 0xFF]);
      return;
    }
    if (command == Op.soundEffectSet) {
      if (scene != 0) {
        _reply(command, [0xFF]);
        return;
      }
      if (payload.isNotEmpty) eq = payload[0];
      _reply(command, [0x01]);
      return;
    }
    if (command == Op.settingGet) {
      _reply(command, [Op.settingLdac, ldac]);
      return;
    }
    if (command == Op.settingSet) {
      if (payload.length < 2 || payload[0] != Op.settingLdac) return;
      ldac = payload[1];
      _reply(command, [0x0C, ldac]);
      return;
    }
  }

  @override
  Future<void> write(List<int> data) async {
    writeCalls++;
    _buffer.addAll(data);
    while (_buffer.length >= 5 && _buffer[0] == EdifierCodec.requestHead) {
      if (_buffer[1] != EdifierCodec.appCode) {
        // 应用只会发明文 v2 帧；收到别的说明实现跑偏了。
        throw StateError('unexpected framing: ${_buffer[0].toRadixString(16)}');
      }
      final length = (_buffer[3] << 8) | _buffer[4];
      final total = length + 6;
      if (_buffer.length < total) return;
      final payload = _buffer.sublist(5, 5 + length);
      final command = _buffer[2];
      _buffer.removeRange(0, total);
      sent.add((command, payload));
      _handle(command, payload);
    }
  }

  Future<void> close() => _out.close();
}

void main() {
  test('一次协商拿到全部控制项，且只发 Fit900 的命令', () async {
    final device = FakeHeadset();
    final engine = EdifierEngine(link: device);
    engine.start();

    final result = await engine.negotiate();

    expect(result.ok, isTrue);
    expect(engine.framing, Framing.v2);
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

    // 写降噪永远带 0x2F；0xC8（读 MAC）在这台耳机上不发。
    for (final (command, payload) in device.sent) {
      if (command == Op.noiseSet) expect(payload.first, AncSlot.fit900);
      expect(command, isNot(Op.macGet));
    }
    await engine.dispose();
    await device.close();
  });

  test('没有回包也不会把降噪控件藏起来', () async {
    final device = FakeHeadset(replyNoise: false);
    final engine = EdifierEngine(link: device);
    engine.start();

    final result = await engine.negotiate();

    expect(result.ok, isTrue);
    expect(engine.caps.noise, isTrue);
    expect(engine.caps.ambientLevel, isTrue);
    // 状态未知，但控件在
    expect(engine.state.noise, isNull);
    await engine.dispose();
    await device.close();
  });

  test('开机就在环境声：借助 C1 [2F 04] 回读等级', () async {
    final device = FakeHeadset();
    device.noiseMode = 4; // 环境声
    device.ambientLevel = 3; // 突出背景声
    final engine = EdifierEngine(link: device);
    engine.start();
    await engine.negotiate();

    expect(engine.state.noise, NoiseMode.ambient);
    expect(engine.state.ambientLevel, AmbientLevel.background);
    await engine.dispose();
    await device.close();
  });

  test('三档降噪 + 环境声等级按真机数值写入', () async {
    final device = FakeHeadset();
    final engine = EdifierEngine(link: device);
    engine.start();
    await engine.negotiate();

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
    final engine = EdifierEngine(link: device);
    engine.start();
    await engine.negotiate();

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
    final engine = EdifierEngine(link: device);
    engine.start();
    await engine.negotiate();

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

  test('重复点「重新读取」：并发也只跑一轮，结果不会被互相打断', () async {
    final device = FakeHeadset();
    final engine = EdifierEngine(link: device);
    engine.start();

    // 用户连点两下。
    final results = await Future.wait([engine.negotiate(), engine.negotiate()]);

    expect(results.every((r) => r.ok), isTrue);
    expect(engine.framing, Framing.v2);
    expect(engine.state.battery, 45);

    // 重新读取之后控制项仍然可用（以前第二次会跑成两轮、把状态改坏）。
    expect(await engine.setNoise(NoiseMode.off), isTrue);
    expect(engine.state.noise, NoiseMode.off);

    await engine.dispose();
    await device.close();
  });

  test('完全不应答的设备：协商失败但可安全释放', () async {
    final device = FakeHeadset(silent: true);
    final engine = EdifierEngine(link: device);
    engine.start();

    final result = await engine.negotiate();

    expect(result.ok, isFalse);
    expect(result.error, isNotNull);
    expect(engine.caps.battery, isFalse);
    await engine.dispose();
    await device.close();
  });

  test('重新读取失败时保留上一次可用的状态', () async {
    final device = FakeHeadset();
    final engine = EdifierEngine(link: device);
    engine.start();
    await engine.negotiate();
    expect(engine.state.battery, 45);
    expect(engine.caps.noise, isTrue);

    // 之后耳机不再回包：这次读取拿不到电量，但已经能用的状态不能被抹掉。
    device.silent = true;
    final second = await engine.negotiate();

    expect(second.ok, isTrue);
    expect(second.error, contains('kept the previous'));
    expect(engine.ready, isTrue);
    expect(engine.state.battery, 45);
    expect(engine.caps.noise, isTrue);
    await engine.dispose();
    await device.close();
  });
}
