import 'package:edifier_fit/ble/ble_controller.dart';
import 'package:edifier_fit/config.dart';
import 'package:flutter_test/flutter_test.dart';

/// MAC / UUID 归一：用户手输的地址格式五花八门，必须统一成平台要的形式。
void main() {
  group('normalizeAddress', () {
    test('冒号分隔（大写）→ 小写冒号', () {
      expect(
        BleController.normalizeAddress('AA:BB:CC:DD:EE:FF'),
        'aa:bb:cc:dd:ee:ff',
      );
    });

    test('短横分隔', () {
      expect(
        BleController.normalizeAddress('aa-bb-cc-dd-ee-ff'),
        'aa:bb:cc:dd:ee:ff',
      );
    });

    test('纯 12 位十六进制', () {
      expect(BleController.normalizeAddress('AABBCCDDEEFF'), 'aa:bb:cc:dd:ee:ff');
    });

    test('带空格和换行（从属性框复制粘贴）', () {
      expect(
        BleController.normalizeAddress('  AA BB CC DD EE FF \n'),
        'aa:bb:cc:dd:ee:ff',
      );
    });

    test('平台 UUID 原样保留（iOS / macOS 用）', () {
      const uuid = '1A2B3C4D-5E6F-7A8B-9C0D-1E2F3A4B5C6D';
      expect(BleController.normalizeAddress(uuid), uuid.toLowerCase());
    });

    test('内置地址本身就是规范形式', () {
      expect(BleController.normalizeAddress(kMyHeadsetMac), kMyHeadsetMac);
      expect(kMyHeadsetMac, '6c:16:29:e7:b5:14');
    });

    test('位数不对 / 空 / null 都返回 null', () {
      expect(BleController.normalizeAddress('AA:BB:CC'), isNull);
      expect(BleController.normalizeAddress('AABBCCDDEEFFF'), isNull);
      expect(BleController.normalizeAddress(''), isNull);
      expect(BleController.normalizeAddress('   '), isNull);
      expect(BleController.normalizeAddress(null), isNull);
    });
  });
}
