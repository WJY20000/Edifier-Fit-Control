import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

import '../ble/ble_controller.dart';
import '../config.dart';
import '../i18n/l10n.dart';
import '../protocol/engine.dart';
import '../protocol/frame.dart';
import '../protocol/models.dart';
import '../protocol/profiles.dart';

enum SessionPhase { idle, connecting, connected }

/// 应用状态：BLE 连接、协议引擎、偏好设置。
class Session extends ChangeNotifier {
  static const String _kLocale = 'locale';
  static const String _kTheme = 'themeMode';
  static const String _kDeepProbe = 'deepProbe';
  static const String _kAutoReconnect = 'autoReconnect';
  static const String _kLastId = 'lastDeviceId';
  static const String _kLastName = 'lastDeviceName';
  static const String _kTargetMac = 'targetMac';
  static const String _kMacCleared = 'targetMacCleared';
  static const Set<String> _themeModes = {'system', 'dark', 'light'};

  SharedPreferences? _prefs;

  final BleController ble = BleController();
  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();

  StreamSubscription<List<DiscoveredDevice>>? _scanSub;
  StreamSubscription<BleConnectionChange>? _disconnectSub;
  StreamSubscription<EdifierFrame>? _frameSub;
  Timer? _batteryTimer;
  Timer? _scanTimer;

  SessionPhase phase = SessionPhase.idle;
  EdifierEngine? engine;
  UniversalBleLink? link;
  ModelProfile profile = Profiles.fit900nbTurbo;

  String? deviceId;

  /// 用户固定下来的那台耳机（**BLE 地址**）。扫描不到时可以直接连它。
  String? targetMac;

  /// 用户点过「取消固定」：别再用内置地址自动填回去。
  bool _macCleared = false;
  String? deviceName;
  String? peripheralName;

  String? lastError;
  String? notice;
  bool _intentionalDisconnect = false;

  List<DiscoveredDevice> devices = const [];

  String locale = 'zh';
  String themeMode = 'system';
  bool deepProbe = false;
  bool autoReconnect = true;

  L10n get l10n => L10n(locale);

  bool get connected => phase == SessionPhase.connected && engine != null;

  DeviceState? get device => engine?.state;
  Capabilities? get caps => engine?.caps;
  NegotiationResult? get negotiation => _negotiation;
  NegotiationResult? _negotiation;

  List<LogEntry> get logs => engine?.log ?? const [];

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null; // 读取失败就退回默认值，不影响主流程
    }
    // 偏好里可能存着旧版本写下的值（或被手改坏）。这里逐个校验：
    // SegmentedButton 的 selected 必须落在 segments 里，否则 debug 下直接断言失败。
    final storedLocale = _prefs?.getString(_kLocale);
    locale = L10n.supported.contains(storedLocale) ? storedLocale! : 'zh';
    final storedTheme = _prefs?.getString(_kTheme);
    themeMode = _themeModes.contains(storedTheme) ? storedTheme! : 'system';
    deepProbe = _prefs?.getBool(_kDeepProbe) ?? false;
    autoReconnect = _prefs?.getBool(_kAutoReconnect) ?? true;
    // 首次启动直接固定这台耳机：用户只有它，光等广播没有意义。
    // 用户点过「取消固定」就尊重这个选择（_kMacCleared），不再自动填回去。
    var storedMac = BleController.normalizeAddress(_prefs?.getString(_kTargetMac));
    _macCleared = _prefs?.getBool(_kMacCleared) ?? false;
    // 旧版本把「经典蓝牙地址」当成了连接地址（连不上，报 Failed to get device）。
    // 这里静默迁移成真正的 BLE 地址。
    if (storedMac == kMyHeadsetClassicMac) {
      storedMac = kMyHeadsetBleMac;
      _prefs?.setString(_kTargetMac, kMyHeadsetBleMac);
    }
    targetMac = storedMac ?? (_macCleared ? null : kMyHeadsetBleMac);

    ble.installListeners();
    _scanSub = ble.scanResults.listen((list) {
      devices = list;
      _learnAddress(list);
      notifyListeners();
    });
    _disconnectSub = ble.disconnects.listen((change) {
      // 不能用 ==：Android 回调给的是大写 MAC，内置地址是小写。
      if (!BleController.sameAddress(change.deviceId, deviceId)) return;
      if (_intentionalDisconnect) return;
      // 主动断开时事件可能晚于 _intentionalDisconnect 复位到达，
      // 此时本地已经清干净，再报「已断开」会弹出误导性的提示。
      if (phase == SessionPhase.idle && engine == null) return;
      lastError = change.error ?? l10n.t('status.disconnected');
      // 链路已经没了，本地状态要跟着清掉；engine 的 dispose 是异步的，
      // 这里不等它，先把界面恢复到「未连接」。
      phase = SessionPhase.idle;
      unawaited(_teardown(keepDevice: true));
      notifyListeners();
    });

    UniversalBle.onValueChange = (value) {
      final current = link;
      if (current == null) return;
      // 这两处以前都是裸 `==` 比较。Android 的 deviceId 是
      // `BluetoothDevice.address`（大写），特征值也可能带花括号，
      // 于是每一帧回包都在这里被丢掉 —— 表现就是「什么都没读出来」。
      if (!BleController.sameAddress(value.deviceId, current.deviceId)) return;
      if (!BleController.sameUuid(value.characteristicId, current.gatt.notify)) return;
      if (!_notifications.isClosed) _notifications.add(value.value);
    };

    notifyListeners();

    if (autoReconnect) {
      // 有固定地址就用它：它不依赖上一次扫描是否成功。
      final last = targetMac ?? _prefs?.getString(_kLastId);
      if (last != null && last.isNotEmpty) {
        // 固定地址优先用内置的名字：Windows 的 BLE 侧常常只有地址没有名字。
        final normalized = BleController.normalizeAddress(last);
        final name = _prefs?.getString(_kLastName) ??
            (normalized == kMyHeadsetBleMac || normalized == kMyHeadsetClassicMac
                ? kMyHeadsetName
                : null);
        // 静默重连：不阻塞启动，失败就停在「未连接」。
        // 失败后再补一次「短扫 + 重试」：开机时 Windows 可能还没见过这台设备。
        unawaited(() async {
          await connectTo(last, name, auto: true).catchError((Object _) {});
          if (connected) return;
          await ble.warmUp(duration: const Duration(seconds: 3));
          final retry = targetMac ?? last;
          await connectTo(retry, name, auto: true).catchError((Object _) {});
        }());
      }
    }
  }

  /// 扫描到「我那只耳机」时，把它真正的 BLE 地址记下来。
  ///
  /// 经典蓝牙地址是 `…:14`、BLE 广告地址是 `…:41`，两者不同。
  /// 用户从设备属性里复制到的往往是前者，直接连一定失败。
  /// 只要它广播一次（厂商数据里带着经典 MAC），这里就能自动纠正。
  void _learnAddress(List<DiscoveredDevice> list) {
    if (_macCleared) return;
    final mine = list.where((d) => d.mine).toList();
    if (mine.isEmpty) return;
    final id = mine.first.id;
    // Android 扫描结果是大小写混杂的 MAC，用归一化比较，避免每次扫描都重写一遍。
    if (BleController.sameAddress(targetMac, id)) return;
    // 只覆盖「内置值 / 经典地址 / 空」，别把用户手动固定成别的设备改掉。
    final auto = targetMac == null ||
        BleController.sameAddress(targetMac, kMyHeadsetBleMac) ||
        BleController.sameAddress(targetMac, kMyHeadsetClassicMac);
    if (!auto) return;
    // 存归一化之后的小写形式：Android 拿回来的可能是大写。
    final canonical = BleController.normalizeAddress(id) ?? id;
    targetMac = canonical;
    _prefs?.setString(_kTargetMac, canonical);
  }

  void setLocale(String value) {
    if (!L10n.supported.contains(value) || value == locale) return;
    locale = value;
    _prefs?.setString(_kLocale, value);
    notifyListeners();
  }

  void setThemeMode(String value) {
    if (!_themeModes.contains(value) || value == themeMode) return;
    themeMode = value;
    _prefs?.setString(_kTheme, value);
    notifyListeners();
  }

  void setDeepProbe(bool value) {
    deepProbe = value;
    _prefs?.setBool(_kDeepProbe, value);
    notifyListeners();
  }

  void setAutoReconnect(bool value) {
    autoReconnect = value;
    _prefs?.setBool(_kAutoReconnect, value);
    notifyListeners();
  }

  Future<void> startScan({bool all = false}) async {
    lastError = null;
    final problem = await ble.prepare();
    if (problem != null) {
      lastError = problem;
      notifyListeners();
      return;
    }
    devices = const [];
    notifyListeners();
    try {
      await ble.startScan(all: all);
      // 扫描不会自己结束：不设上限会一直开着射频，既费电又让界面停在「扫描中」。
      _scanTimer?.cancel();
      _scanTimer = Timer(const Duration(seconds: 20), () {
        unawaited(stopScan());
      });
    } catch (error) {
      lastError = '$error';
    }
    notifyListeners();
  }

  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await ble.stopScan();
    notifyListeners();
  }

  Future<void> connect(DiscoveredDevice device) =>
      connectTo(device.id, device.name, auto: false);

  Future<void> connectTo(String id, String? name, {required bool auto}) async {
    if (phase == SessionPhase.connecting) return;
    if (BleController.sameAddress(deviceId, id) && connected) return;
    final previousId = deviceId;
    await _teardown(keepDevice: false);
    if (previousId != null && !BleController.sameAddress(previousId, id)) {
      // 换一台设备时把旧链路断干净：Windows 不会替我们回收，
      // 留着它会让新连接一直卡到超时。
      try {
        await ble.disconnect(previousId).timeout(const Duration(seconds: 3));
      } catch (_) {
        // 旧链路本来就已经断了。
      }
    }
    phase = SessionPhase.connecting;
    deviceId = id;
    deviceName = name;
    lastError = null;
    notifyListeners();

    try {
      final candidates = await ble.connectCandidates(id);
      final detected = Profiles.resolve(name);
      NegotiationResult? negotiation;

      // 不同的「写 + 通知」配对都试一遍：选错了不会报错，只是永远没有回包。
      for (var index = 0; index < candidates.length; index++) {
        final gatt = candidates[index];
        final bleLink = UniversalBleLink(
          deviceId: id,
          gatt: gatt,
          notifications: _notifications.stream,
        );
        link = bleLink;

        final edifier = EdifierEngine(link: bleLink, profile: detected);
        edifier.serviceUuid = gatt.service;
        edifier.writeUuid = gatt.write;
        edifier.notifyServiceUuid = gatt.notifyService;
        edifier.notifyUuid = gatt.notify;
        for (final line in ble.lastGattDump) {
          edifier.logInfo(line);
        }
        engine = edifier;
        profile = detected;
        await _frameSub?.cancel();
        _frameSub = edifier.frames.listen((_) => notifyListeners());
        edifier.start();

        // BLE 链路已经建立：即使协议没协商成功，也让用户能进实验室手动试。
        phase = SessionPhase.connected;
        notifyListeners();

        var attempt = NegotiationResult(
          ok: false,
          framing: edifier.framing,
          responseHead: edifier.responseHead,
          serviceUuid: gatt.service,
          writeUuid: gatt.write,
          notifyUuid: gatt.notify,
          error: 'no answer',
        );
        try {
          await bleLink.requestMtu(247);
          await bleLink.subscribe();
          attempt = await edifier.negotiate(deepProbe: deepProbe);
        } catch (error) {
          attempt = NegotiationResult(
            ok: false,
            framing: edifier.framing,
            responseHead: edifier.responseHead,
            serviceUuid: gatt.service,
            writeUuid: gatt.write,
            notifyUuid: gatt.notify,
            error: '$error',
          );
        }
        negotiation = attempt;
        if (attempt.ok) break;
        // 最后一个候选留着（不 dispose / 不退订），实验室还能手动发帧排障。
        if (index == candidates.length - 1) break;
        await bleLink.unsubscribe();
        await edifier.dispose();
      }

      _negotiation = negotiation;
      if (negotiation == null || !negotiation.ok) {
        lastError = negotiation?.error ?? 'no answer';
        notifyListeners();
        return;
      }

      peripheralName = engine?.state.name ?? name;
      _prefs?.setString(_kLastId, id);
      _prefs?.setString(_kLastName, name ?? '');
      // 连通过一次就记住地址：以后哪怕扫不到，也能一键直连。
      targetMac = BleController.normalizeAddress(id) ?? targetMac;
      if (targetMac != null) _prefs?.setString(_kTargetMac, targetMac!);
      _startBatteryTimer();
      notifyListeners();
    } catch (error) {
      lastError = '$error';
      phase = SessionPhase.idle;
      notifyListeners();
    }
  }

  /// 固定 / 取消固定这台耳机。
  Future<void> setTargetMac(String? raw) async {
    final mac = BleController.normalizeAddress(raw);
    targetMac = mac;
    // 偏好写入本身不用等（失败也不影响本次连接）。
    _macCleared = mac == null;
    if (mac == null) {
      _prefs?.remove(_kTargetMac);
      // 记住「是用户主动取消的」，否则下次启动又会被内置地址填回去。
      _prefs?.setBool(_kMacCleared, true);
    } else {
      _prefs?.setString(_kTargetMac, mac);
      _prefs?.remove(_kMacCleared);
    }
    notifyListeners();
  }

  /// 不扫描，直接连固定地址（也接受用户当场输入的地址）。
  Future<bool> connectByAddress(String raw) async {
    final mac = BleController.normalizeAddress(raw);
    if (mac == null) {
      lastError = l10n.t('scan.macInvalid');
      notifyListeners();
      return false;
    }
    // 直连同样要先拿到蓝牙权限并确认适配器开着（Android 12+ 必须）。
    final problem = await ble.prepare();
    if (problem != null) {
      lastError = problem;
      notifyListeners();
      return false;
    }
    // 用户很可能填的是经典蓝牙地址（Windows 属性里显示的那个）。
    // BLE 栈不认识它，直接换成已知的 BLE 地址。
    final target = mac == kMyHeadsetClassicMac ? kMyHeadsetBleMac : mac;
    await setTargetMac(target);
    await connectTo(target, null, auto: false);
    if (connected) return true;

    // 还不行：短扫一次，让 Windows 的 BLE 栈先「看见」这台设备。
    // 扫描期间如果认出了这只耳机，_learnAddress 会把地址纠正成实际广播的那个。
    await ble.warmUp();
    final retry = targetMac ?? target;
    await connectTo(retry, null, auto: false);
    if (connected) {
      await setTargetMac(retry);
      return true;
    }
    return false;
  }

  /// 手动让系统给固定地址做一次配对（LE bonding）。
  ///
  /// 耳机的控制服务在部分固件上要求加密链路，配对后才能读到特征值。
  Future<bool> pairTarget() async {
    final mac = targetMac;
    if (mac == null) return false;
    final ok = await ble.pair(mac);
    notifyListeners();
    return ok;
  }

  /// 系统当前已连接的设备（不依赖广播）。
  Future<List<DiscoveredDevice>> systemDevices() async {
    final problem = await ble.prepare();
    if (problem != null) {
      lastError = problem;
      notifyListeners();
      return const [];
    }
    try {
      return await ble.systemDevices();
    } catch (error) {
      lastError = '$error';
      notifyListeners();
      return const [];
    }
  }

  Future<void> renegotiate() async {
    final edifier = engine;
    if (edifier == null) return;
    _negotiation = await edifier.negotiate(deepProbe: deepProbe);
    notifyListeners();
  }

  /// 无视设置，强制做一次包含控制项的深度探测。
  Future<void> probeNow() async {
    final edifier = engine;
    if (edifier == null) return;
    // 和控制命令共用一条队列：探测期间点选项会排队，不会两边抢通道。
    await _serialized(() async {
      try {
        _negotiation = await edifier.negotiate(deepProbe: true);
      } catch (error) {
        lastError = '$error';
      }
      notifyListeners();
      return true;
    });
  }

  Future<void> refreshBattery() async {
    await engine?.refreshBattery();
    notifyListeners();
  }

  /// 控制命令的串行队列。
  ///
  /// 用户连点两个选项时，两条写入/读回会交错：读回可能拿到上一条命令的回包，
  /// 于是界面显示「失败」，设备其实已经改了。这里让控制命令一条一条来。
  Future<void> _controlQueue = Future<void>.value();

  Future<bool> _serialized(Future<bool> Function() task) {
    final previous = _controlQueue;
    final done = Completer<void>();
    _controlQueue = done.future;
    return previous.then((_) => task()).whenComplete(() => done.complete());
  }

  /// 上一次「失败后自动重新协商」的时间，避免每次点击都触发一轮探测。
  DateTime? _lastHeal;

  /// 先按当前协商结果执行；失败就自动重谈一次再试一遍。
  ///
  /// 真机上出现过「刚连上时点选项没反应，点一次深度探测之后就好了」：
  /// 说明那次协商结果不可用（回包丢了 / 通知还没订阅上）。
  /// 与其让用户自己去找「深度探测」，不如失败时自动补一次。
  Future<bool> _runOrHeal(Future<bool> Function(EdifierEngine engine) action) async {
    final edifier = engine;
    if (edifier == null) return false;
    // 链路抖一下时写 GATT 可能直接抛异常，别让它变成未捕获错误。
    try {
      if (await action(edifier)) return true;
    } catch (_) {
      // 当作失败，下面走自动重谈。
    }
    // 链路已经断了就别再折腾探测了，直接报错让用户重连。
    if (!connected) return false;

    final now = DateTime.now();
    final cooling = _lastHeal != null &&
        now.difference(_lastHeal!) < const Duration(seconds: 12);
    if (cooling) return false;
    _lastHeal = now;
    try {
      // 已验证的型号才敢自动发「未验证的控制命令」；未验证的型号只做一次轻量重谈，
      // 免得为了修一个控件而对未知固件乱发命令（部分型号会直接掉线）。
      _negotiation = await edifier.negotiate(deepProbe: profile.verified);
    } catch (_) {
      return false;
    }
    notifyListeners();
    try {
      return await action(edifier);
    } catch (_) {
      return false;
    }
  }

  Future<bool> setNoise(NoiseMode mode) async {
    final ok = await _serialized(() => _runOrHeal((engine) => engine.setNoise(mode)));
    // 成功就清掉上一次的「操作失败」：以前这条提示会一直挂在页面上，
    // 用户明明点成功了，下面还写着失败，看起来像没生效。
    lastError = ok ? null : l10n.t('common.failed');
    notifyListeners();
    return ok;
  }

  Future<bool> setAmbientLevel(int level) async {
    final ok = await _serialized(() => _runOrHeal((engine) => engine.setAmbientLevel(level)));
    // 以前这里失败是静默的：界面停在旧档位，用户不知道是没发出去还是被拒绝。
    // 成功则清掉上一次的「操作失败」，别让旧提示一直挂着。
    lastError = ok ? null : l10n.t('common.failed');
    notifyListeners();
    return ok;
  }

  Future<bool> setScene(int value) async {
    final ok = await _serialized(() => _runOrHeal((engine) => engine.setScene(value)));
    // 成功就清掉上一次的「操作失败」：以前这条提示会一直挂在页面上，
    // 用户明明点成功了，下面还写着失败，看起来像没生效。
    lastError = ok ? null : l10n.t('common.failed');
    notifyListeners();
    return ok;
  }

  Future<bool> setLdac(int value) async {
    final ok = await _serialized(() => _runOrHeal((engine) => engine.setLdac(value)));
    // 成功就清掉上一次的「操作失败」：以前这条提示会一直挂在页面上，
    // 用户明明点成功了，下面还写着失败，看起来像没生效。
    lastError = ok ? null : l10n.t('common.failed');
    notifyListeners();
    return ok;
  }

  Future<bool> setSoundEffect(int value) async {
    final ok = await _serialized(() => _runOrHeal((engine) => engine.setSoundEffect(value)));
    // 成功就清掉上一次的「操作失败」：以前这条提示会一直挂在页面上，
    // 用户明明点成功了，下面还写着失败，看起来像没生效。
    lastError = ok ? null : l10n.t('common.failed');
    notifyListeners();
    return ok;
  }

  Future<bool> rename(String name) async {
    final ok = await engine?.rename(name) ?? false;
    notifyListeners();
    return ok;
  }

  Future<void> powerOff() async {
    await engine?.powerOff();
    await disconnect();
  }

  Future<void> sendRaw(int command, List<int> payload) async {
    await engine?.sendRaw(command, payload);
    notifyListeners();
  }

  Future<void> disconnect() async {
    final id = deviceId;
    _intentionalDisconnect = true;
    try {
      await _teardown(keepDevice: true);
      if (id != null) await ble.disconnect(id);
    } finally {
      _intentionalDisconnect = false;
    }
    notifyListeners();
  }

  /// 退出前收尾：停扫描、断连接、停定时器。
  ///
  /// 只做清理，不关 notifyListeners 之外的任何东西；
  /// 调用方（退出流程）负责真的结束进程。
  Future<void> shutdown() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    _batteryTimer?.cancel();
    _batteryTimer = null;
    try {
      await ble.stopScan();
    } catch (_) {
      // 扫描没开或已经停了，不影响退出。
    }
    final id = deviceId;
    // 先把「系统层面的断开」发出去：进程退出后 Windows 不会替我们收尾，
    // 残留的半开连接会让下次启动直接卡到超时（TimeoutException: 20s）。
    // 以前这里先做 Dart 侧清理、再断链，总共只给 2 秒，经常断到一半就 exit 了。
    if (id != null) {
      try {
        await ble.disconnect(id).timeout(const Duration(seconds: 5));
      } catch (_) {
        // 本来就没连上 / 超时，忽略。
      }
    }
    _intentionalDisconnect = true;
    try {
      await _teardown(keepDevice: true).timeout(const Duration(seconds: 2));
    } catch (_) {
      // 清理慢一点也没关系，进程马上就结束了。
    } finally {
      _intentionalDisconnect = false;
    }
  }

  /// 每两分钟轻量刷新一次电量（0xD0 是最安全的查询，不会改任何设置）。
  void _startBatteryTimer() {
    _batteryTimer?.cancel();
    _batteryTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (connected) unawaited(refreshBattery());
    });
  }

  Future<void> _teardown({required bool keepDevice}) async {
    _batteryTimer?.cancel();
    _batteryTimer = null;
    await _frameSub?.cancel();
    _frameSub = null;
    await link?.unsubscribe();
    await engine?.dispose();
    engine = null;
    link = null;
    _negotiation = null;
    phase = SessionPhase.idle;
    if (!keepDevice) {
      deviceId = null;
      deviceName = null;
      peripheralName = null;
    }
  }

  void clearNotice() {
    notice = null;
    lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _batteryTimer?.cancel();
    _scanTimer?.cancel();
    _scanSub?.cancel();
    _disconnectSub?.cancel();
    _frameSub?.cancel();
    _notifications.close();
    engine?.dispose();
    super.dispose();
  }
}
