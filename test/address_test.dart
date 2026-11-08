import 'dart:typed_data';

import 'package:edifier_fit/ble/ble_controller.dart';
import 'package:edifier_fit/config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

/// 地址归一 + 「哪台 BLE 设备是我这只耳机」的判定。
///
/// 背景：这只耳机有两个地址 —— 经典蓝牙 `…:14`、BLE 广告 `…:41`。
/// 拿经典地址去连，WinRT 直接 `Failed to get device`。
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
      expect(BleController.normalizeAddress(kMyHeadsetBleMac), kMyHeadsetBleMac);
      expect(kMyHeadsetBleMac, '6c:16:29:e7:b5:41');
      expect(kMyHeadsetClassicMac, '6c:16:29:e7:b5:14');
      // 两个地址必须不同，否则「经典地址连不上」这条经验就不成立了。
      expect(kMyHeadsetBleMac, isNot(kMyHeadsetClassicMac));
    });

    test('位数不对 / 空 / null 都返回 null', () {
      expect(BleController.normalizeAddress('AA:BB:CC'), isNull);
      expect(BleController.normalizeAddress('AABBCCDDEEFFF'), isNull);
      expect(BleController.normalizeAddress(''), isNull);
      expect(BleController.normalizeAddress('   '), isNull);
      expect(BleController.normalizeAddress(null), isNull);
    });
  });

  group('isMyHeadset', () {
    BleDevice device({
      String id = 'aa:bb:cc:dd:ee:ff',
      String? name,
      List<ManufacturerData> mfg = const [],
    }) =>
        BleDevice(
          deviceId: id,
          name: name,
          rssi: -50,
          manufacturerDataList: mfg,
        );

    test('地址就是已确认的 BLE 地址', () {
      expect(BleController.isMyHeadset(device(id: kMyHeadsetBleMac)), isTrue);
    });

    test('厂商数据里带着这只耳机的经典 MAC', () {
      final mfg = ManufacturerData(
        kEdifierCompanyId,
        // e0 07 已由 ManufacturerData 拆走，payload 只剩 MAC + 02 00。
        Uint8List.fromList(const [0x6c, 0x16, 0x29, 0xe7, 0xb5, 0x14, 0x02, 0x00]),
      );
      expect(BleController.isMyHeadset(device(mfg: [mfg])), isTrue);
    });

    test('别的漫步者耳机不算', () {
      final mfg = ManufacturerData(
        kEdifierCompanyId,
        Uint8List.fromList(const [0xc8, 0x24, 0x78, 0x55, 0x64, 0xca, 0x02, 0x00]),
      );
      expect(
        BleController.isMyHeadset(device(name: 'EDIFIER BLE', mfg: [mfg])),
        isFalse,
      );
    });

    test('名字里有 Fit900 也算（没有广播数据时兜底）', () {
      expect(
        BleController.isMyHeadset(device(name: 'EDIFIER Fit900NB Turbo')),
        isTrue,
      );
      expect(BleController.isMyHeadset(device(name: 'EDIFIER BLE')), isFalse);
    });
  });

  group('sameAddress / sameUuid：回调里的 ID 匹配', () {
    test('Android 回调用大写 MAC，内置常量是小写，必须判为同一台', () {
      expect(
        BleController.sameAddress('6C:16:29:E7:B5:41', kMyHeadsetBleMac),
        isTrue,
      );
    });

    test('短横线 / 纯十六进制 / 带空格的写法都算同一台', () {
      expect(
        BleController.sameAddress('6C-16-29-E7-B5-41', '6c:16:29:e7:b5:41'),
        isTrue,
      );
      expect(
        BleController.sameAddress(' 6c1629e7b541 ', '6C:16:29:E7:B5:41'),
        isTrue,
      );
    });

    test('不同设备 / null 不算', () {
      expect(
        BleController.sameAddress('6C:16:29:E7:B5:14', kMyHeadsetBleMac),
        isFalse,
      );
      expect(BleController.sameAddress(null, kMyHeadsetBleMac), isFalse);
    });

    test('特征值 UUID 忽略大小写与花括号', () {
      const notify = '48090001-1a48-11e9-ab14-d663bd873d93';
      expect(BleController.sameUuid(notify.toUpperCase(), notify), isTrue);
      expect(BleController.sameUuid('{$notify}', notify), isTrue);
      expect(
        BleController.sameUuid('48090002-1a48-11e9-ab14-d663bd873d93', notify),
        isFalse,
      );
    });
  });
}
