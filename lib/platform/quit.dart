import 'dart:io' show exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show SystemNavigator;

import '../state/session.dart';

/// 真正退出应用：先断开耳机、停掉扫描，再把进程结束掉。
///
/// 不这么做的话有两种「假退出」：
/// * Windows：窗口关了，进程还挂在任务管理器里，蓝牙连接也还占着；
/// * Android：按返回只是把 Activity 挪到后台，点开又回到原样。
///
/// 这里统一处理：先 `session.shutdown()` 释放连接，
/// Android 用 `SystemNavigator.pop()` 结束 Activity，
/// 桌面端直接 `exit(0)`。
Future<void> quitApp(Session session) async {
  await session.shutdown();
  if (defaultTargetPlatform == TargetPlatform.android) {
    await SystemNavigator.pop();
    return;
  }
  exit(0);
}
