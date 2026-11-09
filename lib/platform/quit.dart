import 'dart:async';
import 'dart:io' show exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show SystemNavigator;

import '../state/session.dart';

/// 清理流程的总预算：超过这个时间就不再等，直接结束进程。
///
/// 断 GATT、停扫描、取消订阅都是系统调用，任何一个卡住（真机上出现过）
/// 都会让「关窗口」变成「窗口没了、进程还在、蓝牙还被占着」。
const Duration _kShutdownBudget = Duration(seconds: 8);

/// 真正退出应用：先断开耳机、停掉扫描，再把进程结束掉。
///
/// 0.8.9 起这里保证「无论如何都会死」：
/// * 每台平台的清理都有超时，总耗时不会超过 [_kShutdownBudget]；
/// * 即使清理卡住，兜底定时器到点也会 `exit(0)`。
///
/// Windows 上点窗口右上角 × / Alt+F4 与设置里的「退出应用」按钮走的是
/// 同一个函数，不再有两套行为。
Future<void> quitApp(Session session) async {
  var cleanedUp = false;
  final watchdog = Timer(_kShutdownBudget, () {
    if (cleanedUp) return;
    // 清理没能在预算内结束：硬退出。宁可少一次优雅断开，也不能把
    // 进程和蓝牙连接一起留在后台。
    exit(0);
  });

  try {
    await session.shutdown().timeout(_kShutdownBudget - const Duration(seconds: 1));
  } catch (_) {
    // 超时或报错都继续往下走：退出这件事不能被清理流程拦住。
  }
  cleanedUp = true;
  watchdog.cancel();

  if (defaultTargetPlatform == TargetPlatform.android) {
    await SystemNavigator.pop();
    return;
  }
  // Windows 上断开 GATT 是异步的系统调用，插件把结果回传之前就 exit(0)，
  // 系统那边可能还留着一个半开连接，下次启动会卡到 20 秒超时。
  // 多等 350 ms 让它落地（总耗时仍然远小于「关不掉」的体验）。
  await Future<void>.delayed(const Duration(milliseconds: 350));
  exit(0);
}
