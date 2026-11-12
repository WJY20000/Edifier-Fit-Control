import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../i18n/l10n.dart';
import '../platform/quit.dart';
import '../state/session.dart';
import 'device_page.dart';
import 'glass.dart';
import 'glass_render.dart';
import 'lab_page.dart';
import 'scan_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'widgets.dart';

class FitApp extends StatefulWidget {
  const FitApp({super.key});

  @override
  State<FitApp> createState() => _FitAppState();
}

class _FitAppState extends State<FitApp> {
  final Session _session = Session();
  bool _ready = false;

  /// 正在走退出流程：盖一层遮罩，别让用户以为窗口卡死了。
  bool _quitting = false;

  /// 关闭窗口（Windows 右上角 ×、Alt+F4）时先断开耳机再退出，
  /// 而不是把进程留在后台占着蓝牙。
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // 面板着色器异步加载：启动就预热，免得第一帧还是纯色、
    // 半秒后突然「变成玻璃」。
    GlassPaneProgram.warmUp();
    _lifecycle = AppLifecycleListener(
      // 和「设置 → 退出应用」完全是同一条路径：断开耳机 → 结束进程。
      // quitApp 内部有兜底定时器，清理卡住也会 exit(0)，不会留下后台进程。
      onExitRequested: () async {
        if (mounted) setState(() => _quitting = true);
        try {
          await quitApp(_session);
        } catch (_) {
          // 兜底：不管清理过程中发生什么，都必须明确回答 exit。
          // 引擎只认 `exit` 这一个答案，不回答（或抛异常）它就永远不关窗，
          // 那正是「点了 × 进程还在」的根因。
        }
        return AppExitResponse.exit;
      },
    );
    _session.init().whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final themeMode = switch (_session.themeMode) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        };
        return MaterialApp(
          title: 'EDIFIER Fit Control',
          debugShowCheckedModeBanner: false,
          theme: FitTheme.build(Brightness.light),
          darkTheme: FitTheme.build(Brightness.dark),
          themeMode: themeMode,
          // 滚到边界用「拉伸」而不是发光（Android），和 FlClash 一致。
          scrollBehavior: const FitScrollBehavior(),
          locale: Locale(_session.locale),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // 退出遮罩放在 builder 里：它会盖住整个 Navigator，
          // 不受当前在哪个分页影响。不在退出流程时原样返回，树结构不变。
          builder: (context, child) {
            final base = child ?? const SizedBox.shrink();
            if (!_quitting) return base;
            // 显式给 textDirection：Stack 的默认对齐是 AlignmentDirectional。
            return Stack(
              textDirection: TextDirection.ltr,
              children: [
                base,
                const Positioned.fill(child: _QuitOverlay()),
              ],
            );
          },
          home: _ready
              ? HomeShell(session: _session)
              : const _Boot(),
        );
      },
    );
  }
}

/// 退出时的遮罩：断开耳机要一两秒，给个明确的反馈。
class _QuitOverlay extends StatelessWidget {
  const _QuitOverlay();

  @override
  Widget build(BuildContext context) {
    // builder 可能不在 Directionality / DefaultTextStyle 之下，
    // 这里显式给一份，避免 Text 找不到祖先时断言失败。
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Color(0xCC0C0F13),
        child: DefaultTextStyle(
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                ),
                SizedBox(height: 14),
                Text(
                  '正在断开耳机并退出…',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text(
                  'Disconnecting and quitting…',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 启动页：品牌 + 一个进度环，避免白屏闪一下。
class _Boot extends StatelessWidget {
  const _Boot();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Brand(width: 64),
            const SizedBox(height: 22),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session});

  final Session session;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  String? _lastError;

  Session get session => widget.session;

  @override
  void initState() {
    super.initState();
    session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    final error = session.lastError;
    if (error == null) {
      _lastError = null;
      return;
    }
    if (error == _lastError) return;
    _lastError = error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          action: SnackBarAction(
            label: session.l10n.t('common.close'),
            onPressed: session.clearNotice,
          ),
        ),
      );
    });
  }

  void _goScan() => setState(() => _index = 1);

  @override
  Widget build(BuildContext context) {
    final l10n = session.l10n;
    final pages = [
      DevicePage(session: session, onGoScan: _goScan),
      ScanPage(session: session, onConnected: () => _select(0)),
      LabPage(session: session),
      SettingsPage(session: session),
    ];
    final titles = [
      l10n.t('tab.device'),
      l10n.t('tab.scan'),
      l10n.t('tab.lab'),
      l10n.t('tab.settings'),
    ];
    final destinations = [
      GlassDestination(
        icon: Icons.headphones_outlined,
        selectedIcon: Icons.headphones_rounded,
        label: l10n.t('tab.device'),
      ),
      GlassDestination(
        icon: Icons.bluetooth_rounded,
        selectedIcon: Icons.bluetooth_searching_rounded,
        label: l10n.t('tab.scan'),
      ),
      GlassDestination(
        icon: Icons.terminal_outlined,
        selectedIcon: Icons.terminal_rounded,
        label: l10n.t('tab.lab'),
      ),
      GlassDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: l10n.t('tab.settings'),
      ),
    ];

    // 四个页面一直挂在树上（滚动位置、输入内容不丢），
    // 切换时按方向滑入 / 滑出。
    final body = LiquidPageView(index: _index, children: pages);
    final maxWidth = _index == 0 ? 1180.0 : 900.0;

    return PopScope(
      // Android：在设备页按返回键 = 退出应用（而不是缩到后台）；
      // 在别的分页则先回到设备页。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index != 0) {
          _select(0);
          return;
        }
        quitApp(session);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          return GlassBackdrop(
            child: Scaffold(
              // 背景由 GlassBackdrop 负责画。Scaffold 必须透明，
              // 否则玻璃背后是一块纯色，色光看不见。
              backgroundColor: Colors.transparent,
              // 内容延伸到胶囊下面：底部胶囊才能把滚过去的列表
              // **真的折进玻璃里**（FlClash 也是这么做的）。
              extendBody: true,
              appBar: wide ? null : _buildPhoneBar(l10n, titles[_index]),
              body: wide
                  ? _buildWideBody(titles[_index], body, maxWidth, destinations)
                  : SafeArea(
                      top: false,
                      bottom: false,
                      // 整页内容截成一张纹理：底部胶囊从这里采样。
                      // 只包 body（不含胶囊本身）—— 没有自我采样。
                      // 每 3 帧最多截一次：60 fps 下 20 Hz，肉眼追不上，
                      // 但同步光栅化的开销少了三分之一。
                      child: GlassCapture(
                        kind: GlassSourceKind.content,
                        interval: 3,
                        child: body,
                      ),
                    ),
              bottomNavigationBar: wide
                  ? null
                  : GlassDock(
                      index: _index,
                      onSelected: _select,
                      destinations: destinations,
                    ),
            ),
          );
        },
      ),
    );
  }

  void _select(int value) {
    if (value == _index) return;
    setState(() => _index = value);
  }

  PreferredSizeWidget _buildPhoneBar(L10n l10n, String title) {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 16,
      // 磨砂底：和卡片同一套玻璃语言，状态栏那一条也一起磨。
      flexibleSpace: const GlassBarVeil(),
      title: Row(
        children: [
          const _Brand(width: 30),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        if (_index != 0) _StatusAction(session: session),
        if (_index == 0)
          IconButton(
            tooltip: l10n.t('device.refreshHint'),
            onPressed: session.refreshBattery,
            icon: const Icon(Icons.refresh_rounded),
          ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _buildWideBody(
    String title,
    Widget body,
    double maxWidth,
    List<GlassDestination> destinations,
  ) {
    return SafeArea(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
            child: GlassSidebar(
              index: _index,
              onSelected: _select,
              destinations: destinations,
              leading: const _Brand(width: 44),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _Header(
                  title: title,
                  session: session,
                  showRefresh: _index == 0,
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FitColors.accentLight, FitColors.accent, FitColors.accentDeep],
        ),
        borderRadius: BorderRadius.circular(width * 0.3),
        boxShadow: [
          BoxShadow(
            color: FitColors.accent.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        size: width * 0.54,
        color: Colors.white,
      ),
    );
  }
}

class _StatusAction extends StatelessWidget {
  const _StatusAction({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    if (session.phase == SessionPhase.connecting) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (!session.connected) {
      return const SizedBox.shrink();
    }
    final battery = session.device?.battery;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: StatusChip(
        label: battery == null ? '--' : '$battery%',
        color: battery != null && battery <= 20 ? FitColors.warning : FitColors.success,
        icon: Icons.battery_std_rounded,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.session,
    required this.showRefresh,
  });

  final String title;
  final Session session;
  final bool showRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = FitTheme.isDark(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 18, 4),
      child: GlassSurface(
        radius: 20,
        blur: GlassBlur.bar,
        tint: dark ? const Color(0xFF141A22) : Colors.white,
        tintAlpha: dark ? 0.62 : 0.70,
        padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
        child: Row(
          children: [
            Text(title, style: theme.textTheme.headlineSmall),
            const Spacer(),
            _StatusAction(session: session),
            if (showRefresh)
              IconButton(
                tooltip: session.l10n.t('device.refreshHint'),
                onPressed: session.connected ? session.refreshBattery : null,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}
