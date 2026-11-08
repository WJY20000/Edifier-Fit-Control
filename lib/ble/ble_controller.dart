import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../protocol/engine.dart';

/// 扫描到的一台设备。
class DiscoveredDevice {
  final String id;
  final String? name;
  final int rssi;
  final List<String> services;

  /// 是否像漫步者（名字或厂商服务）。
  final bool looksLikeEdifier;

  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.services,
    required this.looksLikeEdifier,
  });
}

/// 一次连接里用到的 GATT 通道。
class EdifierGatt {
  final String service;
  final String write;
  final String notify;

  /// 写特征是否支持「带响应」写。只支持 writeWithoutResponse 的固件
  /// 用带响应的方式写会直接失败，所以要记下来。
  final bool writeWithResponse;

  const EdifierGatt({
    required this.service,
    required this.write,
    required this.notify,
    this.writeWithResponse = true,
  });

  @override
  String toString() =>
      'service=$service write=$write notify=$notify writeWithResponse=$writeWithResponse';
}

/// universal_ble 的薄封装：扫描、连接、找通道。
class BleController {
  final Map<String, DiscoveredDevice> _devices = <String, DiscoveredDevice>{};
  final StreamController<List<DiscoveredDevice>> _scanOut =
      StreamController<List<DiscoveredDevice>>.broadcast();
  final StreamController<BleConnectionChange> _disconnects =
      StreamController<BleConnectionChange>.broadcast();

  bool _scanning = false;
  bool showAll = false;

  Stream<List<DiscoveredDevice>> get scanResults => _scanOut.stream;

  /// 主动断开 / 链路丢失事件。
  Stream<BleConnectionChange> get disconnects => _disconnects.stream;

  List<DiscoveredDevice> get devices {
    final list = _devices.values.toList();
    list.sort((a, b) {
      if (a.looksLikeEdifier != b.looksLikeEdifier) return a.looksLikeEdifier ? -1 : 1;
      return b.rssi.compareTo(a.rssi);
    });
    return list;
  }

  /// 服务 UUID 形如 4809xxxx-1a48-11e9-ab14-d663bd873d93。
  static bool isEdifierService(String uuid) {
    final lower = uuid.toLowerCase();
    return lower.startsWith('4809') && lower.endsWith('-1a48-11e9-ab14-d663bd873d93');
  }

  static bool looksLikeEdifierName(String? name) {
    if (name == null || name.isEmpty) return false;
    final lower = name.toLowerCase();
    return lower.contains('edifier') ||
        lower.contains('漫步者') ||
        lower.contains('fit900') ||
        lower.contains('fitbuds') ||
        lower.contains('w820nb') ||
        lower.contains('w830nb');
  }

  void _installListeners() {
    UniversalBle.onScanResult = (device) {
      final services = device.services;
      final like = looksLikeEdifierName(device.name) ||
          services.any(isEdifierService) ||
          services.any((s) => s.toLowerCase() == '00003800-0000-1000-8000-00805f9b34fb');
      if (!like && !showAll) return;
      _devices[device.deviceId] = DiscoveredDevice(
        id: device.deviceId,
        name: device.name,
        rssi: device.rssi ?? -127,
        services: services,
        looksLikeEdifier: like,
      );
      if (!_scanOut.isClosed) _scanOut.add(devices);
    };
    UniversalBle.onConnectionChange = (change) {
      if (!change.isConnected && !_disconnects.isClosed) {
        _disconnects.add(change);
      }
    };
  }

  /// 提前安装全局回调（自动重连时也要能收到断线事件）。
  void installListeners() => _installListeners();

  /// 蓝牙是否可用。
  Future<AvailabilityState> availability() async {
    try {
      return await UniversalBle.getBluetoothAvailabilityState();
    } catch (_) {
      return AvailabilityState.unknown;
    }
  }

  /// 申请权限（Android 12+ 必需），并检查蓝牙状态。
  Future<String?> prepare() async {
    _installListeners();
    try {
      if (!await UniversalBle.hasPermissions()) {
        await UniversalBle.requestPermissions();
      }
    } catch (error) {
      return 'permission denied: $error';
    }
    final state = await availability();
    if (state == AvailabilityState.poweredOff) return 'bluetooth is off';
    if (state == AvailabilityState.unauthorized) return 'bluetooth unauthorized';
    if (state == AvailabilityState.unsupported) return 'bluetooth unsupported';
    return null;
  }

  Future<void> startScan({bool all = false}) async {
    if (_scanning) {
      await stopScan();
    }
    showAll = all;
    _devices.clear();
    _installListeners();
    _scanning = true;
    // 不做服务过滤：部分固件把 Edifier 服务放在 service data 里，
    // 硬过滤会直接把设备筛掉。改为在 Dart 侧匹配。
    try {
      await UniversalBle.startScan(skipDuplicates: false);
    } catch (_) {
      // 起不来就复位，否则界面会永远停在「扫描中」且只能手动点停止。
      _scanning = false;
      rethrow;
    }
    if (!_scanOut.isClosed) _scanOut.add(devices);
  }

  Future<void> stopScan() async {
    if (!_scanning) return;
    _scanning = false;
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
  }

  bool get isScanning => _scanning;

  /// 连接并发现 Edifier 通道。
  Future<EdifierGatt> connect(String deviceId, {Duration timeout = const Duration(seconds: 20)}) async {
    await stopScan();
    await UniversalBle.connect(deviceId, timeout: timeout);
    if (kDebugMode) debugPrint('[ble] connected $deviceId');
    final services = await UniversalBle.discoverServices(deviceId);
    final gatt = pickGatt(services);
    if (gatt == null) {
      await UniversalBle.disconnect(deviceId);
      throw StateError('no writable + notifiable characteristic on this device');
    }
    return gatt;
  }

  /// 从服务表里挑出写 / 通知通道。
  ///
  /// 优先 Edifier 私有服务（4809…），其次任意同时具备 write 与 notify 的服务；
  /// 这样即使型号换了 UUID 也能工作。
  static EdifierGatt? pickGatt(List<BleService> services) {
    EdifierGatt? preferred;
    EdifierGatt? fallback;
    for (final service in services) {
      String? write;
      String? notify;
      var writeWithResponse = true;
      for (final ch in service.characteristics) {
        final props = ch.properties;
        final canWrite = props.contains(CharacteristicProperty.write) ||
            props.contains(CharacteristicProperty.writeWithoutResponse);
        final canNotify = props.contains(CharacteristicProperty.notify) ||
            props.contains(CharacteristicProperty.indicate);
        // 写与通知分开判断：个别固件把两者放在同一个特征上。
        if (write == null && canWrite) {
          write = ch.uuid;
          writeWithResponse = props.contains(CharacteristicProperty.write);
        }
        if (notify == null && canNotify) notify = ch.uuid;
      }
      if (write == null || notify == null) continue;
      final candidate = EdifierGatt(
        service: service.uuid,
        write: write,
        notify: notify,
        writeWithResponse: writeWithResponse,
      );
      if (isEdifierService(service.uuid)) {
        preferred ??= candidate;
      } else {
        fallback ??= candidate;
      }
    }
    return preferred ?? fallback;
  }

  /// 断开。
  Future<void> disconnect(String deviceId) async {
    try {
      await UniversalBle.disconnect(deviceId);
    } catch (_) {}
  }
}

/// 把 universal_ble 的通知流包成协议引擎要的 [EdifierLink]。
class UniversalBleLink implements EdifierLink {
  UniversalBleLink({
    required this.deviceId,
    required this.gatt,
    required this.notifications,
    this.mtu = 23,
  });

  final String deviceId;
  final EdifierGatt gatt;
  final Stream<List<int>> notifications;

  /// 协商后的 MTU（含 3 字节头）。
  int mtu;

  @override
  Stream<List<int>> get incoming => notifications;

  @override
  int get chunkSize => mtu > 23 ? mtu - 3 : 20;

  @override
  Future<void> write(List<int> data) async {
    await UniversalBle.write(
      deviceId,
      gatt.service,
      gatt.write,
      Uint8List.fromList(data),
      withoutResponse: !gatt.writeWithResponse,
    );
  }

  /// 请求更大的 MTU；Android 有效，Windows 会忽略或抛 notSupported。
  Future<void> requestMtu(int value) async {
    try {
      final granted = await UniversalBle.requestMtu(deviceId, value);
      if (granted > 0) mtu = granted;
    } catch (_) {
      // 保持默认 23
    }
  }

  Future<void> subscribe() async {
    await UniversalBle.subscribeNotifications(deviceId, gatt.service, gatt.notify);
  }

  Future<void> unsubscribe() async {
    try {
      await UniversalBle.unsubscribe(deviceId, gatt.service, gatt.notify);
    } catch (_) {}
  }
}
