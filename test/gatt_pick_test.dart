import 'package:edifier_fit/ble/ble_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

/// 真机（2026-10-19，Windows 实验室日志）暴露出来的通道选择问题。
///
/// 这台耳机的控制口全部在服务 `48097303-…` 里：
///   - `48090002`：写
///   - `48090001`：通知（厂商回包走这里）
///   - `0000ff18-…`：同样可通知，但**不是**厂商通道
///
/// Windows 插件把特征存在 `unordered_map` 里，遍历顺序是哈希序；旧代码
/// 「每个服务取第一个可通知的」，于是订阅了 `0000ff18`，耳机一帧都不回。
String _svc(String short) => '$short-1a48-11e9-ab14-d663bd873d93';

BleCharacteristic _ch(String uuid, List<CharacteristicProperty> props) =>
    BleCharacteristic(uuid, props, const <BleDescriptor>[]);

final _controlService = BleService(_svc('48097303'), [
  _ch(_svc('48090001'), const [CharacteristicProperty.notify]),
  _ch(_svc('48090002'), const [CharacteristicProperty.write]),
  _ch('0000ff18-0000-1000-8000-00805f9b34fb', const [CharacteristicProperty.notify]),
]);

final _batteryService = BleService('0000180f-0000-1000-8000-00805f9b34fb', [
  _ch('00002a19-0000-1000-8000-00805f9b34fb',
      const [CharacteristicProperty.read, CharacteristicProperty.notify]),
]);

void main() {
  test('真机服务表：第一候选必须是 48090002 写 + 48090001 通知', () {
    final candidates = BleController.gattCandidates([_batteryService, _controlService]);
    expect(candidates, isNotEmpty);

    final first = candidates.first;
    expect(first.write, _svc('48090002'));
    expect(first.notify, _svc('48090001'));
    expect(first.service, _svc('48097303'));
    expect(first.notifyService, _svc('48097303'));
  });

  test('0000ff18 那种标准通知口不能被当成厂商通道', () {
    final candidates = BleController.gattCandidates([_controlService]);
    expect(candidates.first.notify, isNot(contains('ff18')));

    // 它仍然可以作为后备候选出现，但顺序必须靠后。
    final index = candidates.indexWhere((c) => c.notify.contains('ff18'));
    expect(index, greaterThan(0));
  });

  test('写口与通知口分属不同服务时也能配对', () {
    final writeOnly = BleService(_svc('48097303'), [
      _ch(_svc('48090002'), const [CharacteristicProperty.write]),
    ]);
    final notifyOnly = BleService(_svc('48097304'), [
      _ch(_svc('48090001'), const [CharacteristicProperty.notify]),
    ]);
    final candidates = BleController.gattCandidates([writeOnly, notifyOnly]);
    expect(candidates, isNotEmpty);
    expect(candidates.first.service, _svc('48097303'));
    expect(candidates.first.notifyService, _svc('48097304'));
  });

  test('只有标准 GATT 服务时也不会崩，按原顺序给候选', () {
    final candidates = BleController.gattCandidates([_batteryService]);
    expect(candidates, hasLength(1));
    expect(candidates.first.notify, '00002a19-0000-1000-8000-00805f9b34fb');
  });

  test('没有可写特征时返回空列表', () {
    final services = [
      BleService('0000180f-0000-1000-8000-00805f9b34fb', [
        _ch('00002a19-0000-1000-8000-00805f9b34fb',
            const [CharacteristicProperty.read, CharacteristicProperty.notify]),
      ]),
    ];
    expect(BleController.gattCandidates(services), isEmpty);
  });
}
