import 'dart:async';

import 'package:edifier_fit/protocol/engine.dart';
import 'package:edifier_fit/protocol/frame.dart';
import 'package:edifier_fit/protocol/models.dart';
import 'package:edifier_fit/protocol/opcodes.dart';
import 'package:edifier_fit/protocol/profiles.dart';
import 'package:edifier_fit/state/session.dart';
import 'package:edifier_fit/ui/device_page.dart';
import 'package:edifier_fit/ui/lab_page.dart';
import 'package:edifier_fit/ui/scan_page.dart';
import 'package:edifier_fit/ui/settings_page.dart';
import 'package:edifier_fit/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 不连真机的空链路，只为构造 engine。
class _NullLink implements EdifierLink {
  final StreamController<List<int>> _in = StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get incoming => _in.stream;

  @override
  int get chunkSize => 20;

  @override
  Future<void> write(List<int> data) async {}
}

/// 造一个「已连接且能力齐全」的 session，用来跑界面烟囱测试。
Session _connectedSession() {
  final engine = EdifierEngine(link: _NullLink(), profile: Profiles.fit900nbTurbo);
  engine.framing = Framing.v2;
  engine.anc = AncDialect.slotFit900;
  engine.caps.noise = true;
  engine.caps.ambientLevel = true;
  engine.caps.scene = true;
  engine.caps.ldac = true;
  engine.caps.soundEffect = true;
  engine.caps.rename = true;
  engine.state.battery = 45;
  engine.state.name = 'EDIFIER Fit900NB Turbo';
  engine.state.firmware = '1.0.3';
  engine.state.noise = NoiseMode.ambient;
  engine.state.ambientLevel = AmbientLevel.balanced;
  engine.state.scene = Scene.music;
  engine.state.soundEffect = 2;
  engine.state.ldac = LdacMode.hiRes;

  final session = Session();
  session.engine = engine;
  session.phase = SessionPhase.connected;
  session.deviceId = 'AA:BB:CC:DD:EE:FF';
  return session;
}

Widget _host(Widget child, {Size size = const Size(1280, 900)}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: FitTheme.build(Brightness.dark),
    home: Scaffold(
      body: SizedBox(width: size.width, height: size.height, child: child),
    ),
  );
}

void main() {
  testWidgets('设备页（宽屏）：标题、金标、降噪与环境声都渲染', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = _connectedSession();
    await tester.pumpWidget(
      _host(DevicePage(session: session, onGoScan: () {})),
    );
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('EDIFIER Fit900NB Turbo'), findsOneWidget);
    // 三个金标里的两个 Hi-Res
    expect(find.text('Hi-Res'), findsNWidgets(2));
    expect(find.text('HWA'), findsOneWidget);
    // 当前降噪模式 + 环境声等级
    expect(find.text('环境声'), findsWidgets);
    expect(find.text('平衡'), findsOneWidget);
    // 旧的开发者术语不该出现在首屏
    expect(find.textContaining('slotFit900'), findsNothing);
    expect(find.textContaining('FW 1.0.3'), findsNothing);
  });

  testWidgets('设备页（窄屏）：两栏变单栏，不溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = _connectedSession();
    await tester.pumpWidget(
      _host(
        DevicePage(session: session, onGoScan: () {}),
        size: const Size(390, 844),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('EDIFIER Fit900NB Turbo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('高级区默认折叠，展开后 LDAC 可见（未读到时也不崩）', (tester) async {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = _connectedSession();
    session.engine!.state.ldac = null;
    await tester.pumpWidget(
      _host(DevicePage(session: session, onGoScan: () {}), size: const Size(1280, 1100)),
    );
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('LDAC 编码'), findsNothing);
    await tester.tap(find.text('高级'));
    await tester.pumpAndSettle();
    expect(find.text('LDAC 编码'), findsOneWidget);
    expect(find.text('96k'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未连接：空状态不报错', (tester) async {
    final session = Session();
    await tester.pumpWidget(
      _host(DevicePage(session: session, onGoScan: () {}), size: const Size(390, 844)),
    );
    await tester.pump();
    expect(find.text('还没有连接耳机'), findsOneWidget);
  });

  testWidgets('扫描 / 实验室 / 设置页都能渲染', (tester) async {
    final session = Session();
    for (final page in <Widget>[
      ScanPage(session: session, onConnected: () {}),
      LabPage(session: session),
      SettingsPage(session: session),
    ]) {
      await tester.pumpWidget(_host(page, size: const Size(780, 900)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }

    // 开发者卡片 & 退出卡片：设置页现在用 SingleChildScrollView + Column，
    // 所有卡片都会构建（不再依赖滚动去「碰」ListView 的可见项），
    // 直接断言即可 —— 也就不会再被输入框自带的横向 Scrollable 干扰。
    await tester.pumpWidget(
      _host(SettingsPage(session: session), size: const Size(780, 1200)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('开发者'), findsOneWidget);
    expect(find.text('infinite'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 标题 + 按钮都叫「退出应用」，所以是两个。
    expect(find.text('退出应用'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
