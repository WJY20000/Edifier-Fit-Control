import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../config.dart';
import '../protocol/engine.dart';

/// 扫描到（或从系统里取到）的一台设备。
class DiscoveredDevice {
  final String id;
  final String? name;

  /// 信号强度；0 表示这台设备不是扫描来的，没有 RSSI。
  final int rssi;
  final List<String> services;

  /// 是否像漫步者（名字或厂商服务）。
  final bool looksLikeEdifier;

  /// 来自「系统已连接设备」而不是扫描广播。
  final bool fromSystem;

  /// 确认为「我这只耳机」：广播里的厂商数据带着它的经典 MAC
  /// （`E0 07` + `6c1629e7b514`），或地址就是已确认的 BLE 地址。
  final bool mine;

  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.services,
    required this.looksLikeEdifier,
    this.fromSystem = false,
    this.mine = false,
  });

  bool get hasRssi => rssi != 0;
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

  /// 这台 BLE 设备是不是「我那只耳机」。
  ///
  /// 判定顺序（从硬到软）：
  /// 1. 地址就是抓包里确认的 BLE 地址；
  /// 2. 厂商数据（company 0x07E0）里带着这只耳机的经典 MAC —— 这是硬件写的，
  ///    换一台手机/换一台电脑都一样，最可靠；
  /// 3. 名字里有 fit900。
  static bool isMyHeadset(BleDevice device) {
    final id = normalizeAddress(device.deviceId);
    if (id == kMyHeadsetBleMac) return true;
    for (final data in device.manufacturerDataList) {
      if (_hasMacBytes(data.payload, kMyHeadsetClassicMac)) return true;
    }
    final name = (device.name ?? device.rawName ?? '').toLowerCase();
    return name.contains('fit900') || name.contains('fit 900');
  }

  /// 在厂商数据里找 6 字节 MAC（不要求从第 0 字节开始）。
  static bool _hasMacBytes(List<int> payload, String mac) {
    final want = <int>[
      for (final part in mac.split(':')) int.parse(part, radix: 16),
    ];
    if (payload.length < want.length) return false;
    for (var i = 0; i + want.length <= payload.length; i++) {
      var ok = true;
      for (var j = 0; j < want.length; j++) {
        if (payload[i + j] != want[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }

  /// 扫描里出现「我那只耳机」时，返回它的 BLE 地址（用来自动固定）。
  static String? myHeadsetId(List<BleDevice> devices) {
    for (final device in devices) {
      if (isMyHeadset(device)) return device.deviceId;
    }
    return null;
  }

  void _installListeners() {
    UniversalBle.onScanResult = (device) {
      final services = device.services;
      final like = looksLikeEdifierName(device.name) ||
          services.any(isEdifierService) ||
          services.any((s) => s.toLowerCase() == '00003800-0000-1000-8000-00805f9b34fb');
      // 一律收下：Windows 的广播里经常没有名字（名字在另一条 GAP 记录里），
      // 以前在这里就按「像不像漫步者」筛掉，结果耳机明明在广播、列表却是空的。
      // 过滤改由界面上的「只看漫步者」开关做，原始列表保留下来还能排障。
      _devices[device.deviceId] = DiscoveredDevice(
        id: device.deviceId,
        name: device.name,
        rssi: device.rssi ?? -127,
        services: services,
        looksLikeEdifier: like,
        mine: isMyHeadset(device),
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

  Future<void> startScan({bool all = true}) async {
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

  /// 短扫一次再停：Windows 的 `FromBluetoothAddressAsync` 只认它「见过」的地址，
  /// 扫一下等于告诉系统「这台正在广播」，之后再按地址连成功率会高很多。
  Future<void> warmUp({Duration duration = const Duration(seconds: 4)}) async {
    try {
      await startScan();
      await Future<void>.delayed(duration);
    } catch (_) {
      // 扫不起来不影响后面的直连尝试。
    } finally {
      await stopScan();
    }
  }

  /// 系统当前已连接的蓝牙设备（Windows: WinRT 的 Connected 设备集合）。
  ///
  /// 扫描靠的是广播，耳机被系统占用后往往不再广播，这时只能走这条路：
  /// 它直接列出「系统已经握着」的设备，不依赖天线听不听得见。
  Future<List<DiscoveredDevice>> systemDevices() async {
    final list = await UniversalBle.getSystemDevices();
    return [
      for (final device in list)
        DiscoveredDevice(
          id: device.deviceId,
          name: device.name,
          rssi: 0,
          services: device.services,
          looksLikeEdifier: looksLikeEdifierName(device.name) ||
              device.services.any(isEdifierService),
          fromSystem: true,
          mine: normalizeAddress(device.deviceId) == kMyHeadsetBleMac,
        ),
    ];
  }

  /// 把用户输入的地址归一成平台使用的形式（小写、冒号分隔）。
  ///
  /// 支持 `AA:BB:CC:DD:EE:FF`、`AA-BB-...`、`aabbccddeeff`、
  /// 以及 iOS/macOS 那种 UUID（原样返回）。解析不出来返回 null。
  static String? normalizeAddress(String? input) {
    if (input == null) return null;
    final raw = input.trim();
    if (raw.isEmpty) return null;
    // 平台 UUID：8-4-4-4-12，原样（小写）返回。
    if (RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(raw)) {
      return raw.toLowerCase();
    }
    final hex = raw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
    if (hex.length != 12) return null;
    final parts = <String>[
      for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2),
    ];
    return parts.join(':');
  }

  /// 连接并发现 Edifier 通道。
  ///
  /// Windows 上这只耳机还暴露了一个**受保护的服务**
  /// （`48097303-1a48-11e9-ab14-d663bd873d93`）。插件的连接流程会逐个服务取特征，
  /// 只要有一个服务回 `AccessDenied`，它就会**整个连接失败**。
  /// 这种 AccessDenied 通常是「链路没加密」造成的，所以先配对（bonding）
  /// 再重连一次；配不上也只是原样报错。
  Future<EdifierGatt> connect(
    String deviceId, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await stopScan();
    try {
      return await _connectOnce(deviceId, timeout);
    } catch (error) {
      if (!needsPairing(error)) rethrow;
      if (kDebugMode) debugPrint('[ble] AccessDenied, pairing then retrying: $error');
      // 上一次失败可能留下半开连接，先收干净再重来。
      try {
        await UniversalBle.disconnect(deviceId);
      } catch (_) {}
      await pair(deviceId);
      // 系统配对完成后链路要几百毫秒才稳定，太急会又拿到 AccessDenied。
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return _connectOnce(deviceId, timeout);
    }
  }

  /// 单次连接 + 服务发现。
  Future<EdifierGatt> _connectOnce(String deviceId, Duration timeout) async {
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

  /// 这个错误是不是「服务需要加密链路」。
  static bool needsPairing(Object error) {
    final text = '$error'.toLowerCase();
    return text.contains('accessdenied') ||
        text.contains('access denied') ||
        text.contains('failed to get characteristics');
  }

  /// 让系统给这台设备做一次配对（BLE bonding）。
  ///
  /// Windows 11 走 `DeviceInformation.Pairing.PairAsync`（通常不弹窗）；
  /// 其它平台不一定支持，失败就当没配对，不影响后续重连的报错。
  Future<bool> pair(String deviceId) async {
    try {
      await UniversalBle.pair(deviceId);
      if (kDebugMode) debugPrint('[ble] paired $deviceId');
      return true;
    } catch (error) {
      if (kDebugMode) debugPrint('[ble] pair failed: $error');
      return false;
    }
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
