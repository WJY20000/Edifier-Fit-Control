// EDIFIER 耳机私有协议：帧编解码。
//
// 协议来自社区逆向（mEDIFIER / edifier-proto / EncoDeck / HyperEars），
// 详见 docs/PROTOCOL.md。这里只做与设备无关的字节层，便于单元测试。
//
// 两代帧格式：
//
//   v1   AA | len | cmd | data... | crcHi | crcLo
//        len = 1 + data.length，crc = (0x2019 + 前面所有字节之和) & 0xFFFF
//
//   v2   AA | EC | cmd | lenHi | lenLo | payload... | sum8      （BES 新固件）
//        sum8 = 前面所有字节之和 & 0xFF；多数型号 payload 再整体异或 0xA5
//
// 设备回包把首字节换成 BB 或 CC，其余结构一致。

import 'dart:typed_data';

/// 一帧解码结果。
class EdifierFrame {
  /// 首字节：0xBB / 0xCC 表示设备回包（某些固件会原样回 0xAA）。
  final int head;

  /// 命令字。
  final int command;

  /// 数据段（v2 的异或尚未还原，由上层按协商结果处理）。
  final Uint8List payload;

  /// 是否 v2（BES）帧。
  final bool v2;

  const EdifierFrame({
    required this.head,
    required this.command,
    required this.payload,
    required this.v2,
  });

  /// 数据段的十六进制表示，日志用。
  String get payloadHex => payload
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  @override
  String toString() =>
      'EdifierFrame(head=${head.toRadixString(16)}, cmd=${command.toRadixString(16)}, '
      'v2=$v2, payload=[$payloadHex])';
}

/// 请求帧的三种方言。
enum Framing {
  /// 旧协议：AA len cmd data crc16（明文）。
  v1,

  /// BES 新协议：AA EC cmd lenHi lenLo payload sum8（明文）。
  v2,

  /// BES 新协议 + payload 异或 0xA5。
  v2Xor,
}

extension FramingLabel on Framing {
  String get label {
    switch (this) {
      case Framing.v1:
        return 'v1';
      case Framing.v2:
        return 'v2';
      case Framing.v2Xor:
        return 'v2/xor';
    }
  }
}

/// 帧编码 / 解码。
class EdifierCodec {
  static const int requestHead = 0xAA;
  static const int responseHeadBb = 0xBB;
  static const int responseHeadCc = 0xCC;
  static const int appCode = 0xEC;
  static const int checksumSeed = 0x2019;
  static const int payloadXor = 0xA5;

  /// 单个 payload 的上限，防止畸形长度字段撑爆内存。
  static const int maxPayload = 4096;

  /// v1 帧的 16 位校验（大端）。
  static int checksum16(List<int> bytes) {
    var sum = checksumSeed;
    for (final b in bytes) {
      sum = (sum + (b & 0xFF)) & 0xFFFF;
    }
    return sum;
  }

  /// 编码 v1 请求帧。
  static Uint8List encodeV1(int command, List<int> payload) {
    if (payload.length > 254) {
      throw ArgumentError('v1 payload too long: ${payload.length}');
    }
    final length = payload.length + 1;
    final frame = Uint8List(length + 4);
    frame[0] = requestHead;
    frame[1] = length;
    frame[2] = command;
    frame.setRange(3, 3 + payload.length, payload);
    final sum = checksum16(frame.sublist(0, length + 2));
    frame[length + 2] = (sum >> 8) & 0xFF;
    frame[length + 3] = sum & 0xFF;
    return frame;
  }

  /// 编码 v2（BES）请求帧。
  static Uint8List encodeV2(int command, List<int> payload, {bool xor = false}) {
    if (payload.length > maxPayload) {
      throw ArgumentError('v2 payload too long: ${payload.length}');
    }
    final frame = Uint8List(payload.length + 6);
    frame[0] = requestHead;
    frame[1] = appCode;
    frame[2] = command;
    frame[3] = (payload.length >> 8) & 0xFF;
    frame[4] = payload.length & 0xFF;
    var sum = 0;
    for (var i = 0; i < frame.length - 1; i++) {
      var value = 0;
      if (i >= 5) {
        value = payload[i - 5];
        if (xor) value ^= payloadXor;
      } else {
        value = frame[i];
      }
      frame[i] = value;
      sum = (sum + value) & 0xFF;
    }
    frame[frame.length - 1] = sum;
    return frame;
  }

  /// 按方言编码。
  static Uint8List encode(
    Framing framing,
    int command,
    List<int> payload,
  ) {
    switch (framing) {
      case Framing.v1:
        return encodeV1(command, payload);
      case Framing.v2:
        return encodeV2(command, payload);
      case Framing.v2Xor:
        return encodeV2(command, payload, xor: true);
    }
  }

  /// 还原 v2 帧的 payload（异或是对合运算）。
  static Uint8List unxor(Uint8List payload) {
    final out = Uint8List(payload.length);
    for (var i = 0; i < payload.length; i++) {
      out[i] = payload[i] ^ payloadXor;
    }
    return out;
  }
}

/// 增量解码器：把通知流里被拆开的帧重新拼起来。
///
/// 设备可能在任意字节边界分包（BLE 默认 MTU 23 → 每次 20 字节），
/// 因此必须缓存残帧；同时兼容 v1 与 v2 两种布局。
class FrameDecoder {
  final List<int> _buffer = <int>[];

  /// 供 UI / 日志观察的丢弃计数（校验失败、找不到帧头等）。
  int droppedBytes = 0;

  static const int _maxBuffered = 8192;

  /// 喂入一段通知数据，返回解析出的完整帧。
  List<EdifierFrame> feed(List<int> data) {
    _buffer.addAll(data);
    final frames = <EdifierFrame>[];

    while (_buffer.isNotEmpty) {
      // 回包首字节通常是 BB / CC；个别固件直接回显 AA，也一并接受
      // （通知通道里只会出现设备发来的数据，不会读到我们自己写出去的内容）。
      final start = _buffer.indexWhere(
        (b) =>
            b == EdifierCodec.responseHeadBb ||
            b == EdifierCodec.responseHeadCc ||
            b == EdifierCodec.requestHead,
      );
      if (start < 0) {
        droppedBytes += _buffer.length;
        _buffer.clear();
        break;
      }
      if (start > 0) {
        droppedBytes += start;
        _buffer.removeRange(0, start);
      }
      if (_buffer.length < 2) break;

      // v2 用 0xEC 标记；v1 的 len 字段不可能等于 0xEC（236）。
      final isV2 = _buffer[1] == EdifierCodec.appCode;
      if (isV2) {
        if (_buffer.length < 5) break;
        final payloadLength = (_buffer[3] << 8) | _buffer[4];
        if (payloadLength > EdifierCodec.maxPayload) {
          droppedBytes += 1;
          _buffer.removeAt(0);
          continue;
        }
        final total = payloadLength + 6;
        if (_buffer.length < total) break;
        var sum = 0;
        for (var i = 0; i < total - 1; i++) {
          sum = (sum + _buffer[i]) & 0xFF;
        }
        if (_buffer[total - 1] != sum) {
          droppedBytes += 1;
          _buffer.removeAt(0);
          continue;
        }
        final payload = Uint8List.fromList(_buffer.sublist(5, 5 + payloadLength));
        frames.add(EdifierFrame(
          head: _buffer[0],
          command: _buffer[2],
          payload: payload,
          v2: true,
        ));
        _buffer.removeRange(0, total);
        continue;
      }

      final length = _buffer[1];
      if (length < 1) {
        droppedBytes += 1;
        _buffer.removeAt(0);
        continue;
      }
      final total = length + 4;
      if (_buffer.length < total) break;
      final sum = EdifierCodec.checksum16(_buffer.sublist(0, total - 2));
      if (_buffer[total - 2] != ((sum >> 8) & 0xFF) || _buffer[total - 1] != (sum & 0xFF)) {
        droppedBytes += 1;
        _buffer.removeAt(0);
        continue;
      }
      final payload = Uint8List.fromList(_buffer.sublist(3, total - 2));
      frames.add(EdifierFrame(
        head: _buffer[0],
        command: _buffer[2],
        payload: payload,
        v2: false,
      ));
      _buffer.removeRange(0, total);
    }

    if (_buffer.length > _maxBuffered) {
      droppedBytes += _buffer.length;
      _buffer.clear();
    }
    return frames;
  }

  void reset() {
    _buffer.clear();
    droppedBytes = 0;
  }
}
