import 'package:flutter/material.dart';

import 'platform/single_instance.dart';
import 'ui/already_running.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 只允许一个实例：第二个实例会和第一个抢同一只耳机的 BLE 连接。
  if (!SingleInstance.acquire()) {
    runApp(const AlreadyRunningApp());
    return;
  }
  runApp(const FitApp());
}
