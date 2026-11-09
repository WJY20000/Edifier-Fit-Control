import 'dart:io' show exit;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 第二个实例的界面：告诉他「已经有一个在跑了」，而不是让他面对
/// 一个连不上、又不停重连的窗口。
///
/// 这不是限制功能 —— 两个进程抢同一只耳机的 BLE 连接，谁都连不好。
class AlreadyRunningApp extends StatelessWidget {
  const AlreadyRunningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: FitTheme.build(Brightness.light),
      darkTheme: FitTheme.build(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Builder(
                builder: (context) {
                  final theme = Theme.of(context);
                  final muted = theme.colorScheme.onSurface.withValues(alpha: 0.62);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.headphones_rounded,
                        size: 44,
                        color: FitColors.accent,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '程序已经在运行',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '同一时间只能开一个实例：两个进程会抢同一只耳机的蓝牙连接，'
                        '表现就是「显示已断开、一直重连、却怎么都连不上」。\n\n'
                        '请切换到已经打开的窗口。\n'
                        '如果找不到窗口（或者它卡住了），打开任务管理器结束 '
                        'EdifierFitControl.exe，再重新启动。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Already running. Only one instance can hold the headphones. '
                        'Switch to the existing window, or end EdifierFitControl.exe '
                        'in Task Manager and start again.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () => exit(0),
                          child: const Text('退出 / Quit'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
