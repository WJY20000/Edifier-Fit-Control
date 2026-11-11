import 'dart:io';
import 'dart:typed_data';

import 'package:edifier_fit/protocol/frame.dart';
import 'package:edifier_fit/protocol/models.dart';
import 'package:edifier_fit/protocol/opcodes.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造设备回包（首字节 0xBB，校验按「整帧」计算）。
List<int> responseV1(int command, List<int> payload) {
  final body = <int>[0xBB, payload.length + 1, command, ...payload];
  final sum = EdifierCodec.checksum16(body);
  return [...body, (sum >> 8) & 0xFF, sum & 0xFF];
}

List<int> responseV2(int command, List<int> payload, {bool xor = false}) {
  final body = <int>[0xBB, EdifierCodec.appCode, command, (payload.length >> 8) & 0xFF, payload.length & 0xFF];
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

void main() {
  group('v1 编解码', () {
    test('电量查询的字节精确匹配', () {
      final frame = EdifierCodec.encodeV1(Op.batteryGet, const []);
      // sum = 0x2019 + 0xAA + 0x01 + 0xD0 = 0x2194
      expect(frame, [0xAA, 0x01, 0xD0, 0x21, 0x94]);
    });

    test('带 payload 的帧能被解码回来', () {
      final frame = EdifierCodec.encodeV1(Op.noiseGet, const [0x1B]);
      final decoder = FrameDecoder();
      // 把请求头换成回包头，并重算校验
      expect(frame.length, 6); // AA len cmd data crcHi crcLo
      final response = responseV1(Op.noiseGet, const [0x1B, 0x06]);
      final frames = decoder.feed(response);
      expect(frames.length, 1);
      expect(frames.first.head, 0xBB);
      expect(frames.first.command, Op.noiseGet);
      expect(frames.first.payload, [0x1B, 0x06]);
      expect(frames.first.v2, isFalse);
    });

    test('逐字节喂入也能拼出完整帧', () {
      final bytes = responseV1(Op.batteryGet, const [87]);
      final decoder = FrameDecoder();
      final frames = <EdifierFrame>[];
      for (final b in bytes) {
        frames.addAll(decoder.feed([b]));
      }
      expect(frames.length, 1);
      expect(frames.first.payload, [87]);
    });

    test('前缀噪声被计入 droppedBytes', () {
      final decoder = FrameDecoder();
      final frames = decoder.feed([0x00, 0x11, 0x22, ...responseV1(Op.batteryGet, const [50])]);
      expect(frames.length, 1);
      expect(decoder.droppedBytes, 3);
    });

    test('坏校验会跳过一个字节继续找帧头', () {
      final broken = responseV1(Op.batteryGet, const [50]);
      broken[broken.length - 1] ^= 0xFF;
      final decoder = FrameDecoder();
      final frames = decoder.feed([...broken, ...responseV1(Op.batteryGet, const [42])]);
      expect(frames.length, 1);
      expect(frames.first.payload, [42]);
    });
  });

  group('v2 编解码', () {
    test('结构：AA EC cmd lenHi lenLo payload sum8', () {
      final frame = EdifierCodec.encodeV2(Op.noiseGet, const [0x1B]);
      expect(frame.sublist(0, 5), [0xAA, 0xEC, 0xCC, 0x00, 0x01]);
      expect(frame[5], 0x1B);
      expect(frame.length, 7);
      var sum = 0;
      for (var i = 0; i < frame.length - 1; i++) {
        sum = (sum + frame[i]) & 0xFF;
      }
      expect(frame.last, sum);
    });

    test('异或版本与明文只差 payload 一个字节', () {
      final plain = EdifierCodec.encodeV2(Op.noiseSet, const [0x1B, 0x06]);
      final xored = EdifierCodec.encodeV2(Op.noiseSet, const [0x1B, 0x06], xor: true);
      expect(xored.length, plain.length);
      expect(xored[5], plain[5] ^ 0xA5);
      expect(xored[6], plain[6] ^ 0xA5);
      expect(EdifierCodec.unxor(xored.sublist(5, 7)), plain.sublist(5, 7));
    });

    test('解码 v2 回包', () {
      final decoder = FrameDecoder();
      final frames = decoder.feed(responseV2(Op.batteryGet, const [87]));
      expect(frames.length, 1);
      expect(frames.first.v2, isTrue);
      expect(frames.first.payload, [87]);
    });

    test('长度字段跨包时等待剩余字节', () {
      final decoder = FrameDecoder();
      final bytes = responseV2(Op.nameGet, List<int>.filled(18, 0x41));
      expect(decoder.feed(bytes.sublist(0, 7)), isEmpty);
      final frames = decoder.feed(bytes.sublist(7));
      expect(frames.length, 1);
      expect(frames.first.payload.length, 18);
    });

    test('静默超过 5 秒：上一次的半帧作废，不拖累新帧', () {
      var now = DateTime(2026, 1, 1, 12);
      final decoder = FrameDecoder(clock: () => now);
      final bytes = responseV2(Op.nameGet, List<int>.filled(18, 0x41));
      // 先只喂前 7 个字节，留下一个「长度够了但内容还没到」的半帧。
      expect(decoder.feed(bytes.sublist(0, 7)), isEmpty);
      expect(decoder.droppedBytes, 0);

      now = now.add(const Duration(seconds: 6));
      final frames = decoder.feed(responseV2(Op.batteryGet, const [55]));
      expect(frames.length, 1);
      expect(frames.first.payload, [55]);
      // 半帧的 7 个字节被记账丢弃，而不是留在缓冲区里搅乱下一帧。
      expect(decoder.droppedBytes, 7);
    });

    test('静默不超过 5 秒：残帧继续拼，不误丢', () {
      var now = DateTime(2026, 1, 1, 12);
      final decoder = FrameDecoder(clock: () => now);
      final bytes = responseV2(Op.nameGet, List<int>.filled(18, 0x41));
      expect(decoder.feed(bytes.sublist(0, 7)), isEmpty);
      now = now.add(const Duration(seconds: 4));
      final frames = decoder.feed(bytes.sublist(7));
      expect(frames.length, 1);
      expect(frames.first.payload.length, 18);
      expect(decoder.droppedBytes, 0);
    });

    test('也接受回显 AA 头的固件', () {
      final bytes = responseV2(Op.batteryGet, const [33]);
      bytes[0] = 0xAA;
      var sum = 0;
      for (var i = 0; i < bytes.length - 1; i++) {
        sum = (sum + bytes[i]) & 0xFF;
      }
      bytes[bytes.length - 1] = sum;
      final frames = FrameDecoder().feed(bytes);
      expect(frames.length, 1);
      expect(frames.first.payload, [33]);
    });
  });

  group('Fit900NB Turbo 的固定协议', () {
    test('只支持这一只耳机：没有型号识别表', () {
      // 0.8.7 起删掉了多型号档案，所有连接都按 Fit900NB Turbo 处理。
      // 这里守住「文件名不再存在」这件事（改回多型号会立刻红）。
      expect(File('lib/protocol/profiles.dart').existsSync(), isFalse);
    });

    test('真机抓包：0x2F 槽位的编解码', () {
      expect(AncSlot.fit900, 0x2F);
      expect(noisePayload(NoiseMode.deep), [0x2F, 1]);
      expect(noisePayload(NoiseMode.comfort), [0x2F, 2]);
      expect(noisePayload(NoiseMode.wind), [0x2F, 3]);
      expect(noisePayload(NoiseMode.off), [0x2F, 5]);
      // 环境声要带等级：[2F, 04, level]
      expect(noisePayload(NoiseMode.ambient), [0x2F, 4, 2]);
      expect(
        noisePayload(NoiseMode.ambient, ambientLevel: AmbientLevel.vocal),
        [0x2F, 4, 1],
      );
      expect(decodeNoise(Uint8List.fromList([0x2F, 5])), NoiseMode.off);
      expect(decodeNoise(Uint8List.fromList([0x2F, 1])), NoiseMode.deep);
      expect(decodeNoise(Uint8List.fromList([0x2F, 3])), NoiseMode.wind);
      expect(decodeNoise(Uint8List.fromList([0x2F, 4, 1])), NoiseMode.ambient);
      // 别的槽位 / 半截包一律不认
      expect(decodeNoise(Uint8List.fromList([0x1B, 1])), isNull);
      expect(decodeNoise(Uint8List.fromList([0x2F])), isNull);
      expect(decodeNoise(Uint8List.fromList([])), isNull);
    });

    test('真机抓包：用真实字节验证一帧', () {
      // 抓包 14:30:13 切舒适：AA EC C1 00 02 2F 02 8A
      expect(EdifierCodec.encodeV2(Op.noiseSet, const [0x2F, 0x02]),
          [0xAA, 0xEC, 0xC1, 0x00, 0x02, 0x2F, 0x02, 0x8A]);
      // 抓包 14:30:16 切防风噪：AA EC C1 00 02 2F 03 8B
      expect(EdifierCodec.encodeV2(Op.noiseSet, const [0x2F, 0x03]),
          [0xAA, 0xEC, 0xC1, 0x00, 0x02, 0x2F, 0x03, 0x8B]);
      // 抓包 14:32:53 恢复 96k LDAC：AA EC 92 00 02 11 02 3D
      expect(EdifierCodec.encodeV2(Op.settingSet, const [0x11, 0x02]),
          [0xAA, 0xEC, 0x92, 0x00, 0x02, 0x11, 0x02, 0x3D]);
      // 抓包 14:31:46 低音增强：AA EC C4 00 01 03 5E
      expect(EdifierCodec.encodeV2(Op.soundEffectSet, const [0x03]),
          [0xAA, 0xEC, 0xC4, 0x00, 0x01, 0x03, 0x5E]);
      // 抓包 14:31:20 切游戏场景：AA EC 09 00 01 01 A1
      expect(EdifierCodec.encodeV2(Op.sceneSet, const [0x01]),
          [0xAA, 0xEC, 0x09, 0x00, 0x01, 0x01, 0xA1]);
    });

    test('音效预设就是真机确认的 6 组', () {
      expect(EqPreset.fit900.map((p) => p.value).toList(), [2, 3, 1, 0, 4, 5]);
      expect(EqPreset.fit900.first.labelKey, 'eq.vocal');
      expect(EqPreset.fit900.last.labelKey, 'eq.audiophile');
    });
  });
}