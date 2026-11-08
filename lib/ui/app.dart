import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../i18n/l10n.dart';
import '../platform/quit.dart';
import '../state/session.dart';
import 'device_page.dart';
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

  /// 关闭窗口（Windows 右上角 ×、Alt+F4）时先断开耳机再退出，
  /// 而不是把进程留在后台占着蓝牙。
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await _session.shutdown();
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
          locale: Locale(_session.locale),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: _ready
              ? HomeShell(session: _session)
              : const _Boot(),
        );
      },
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
      ScanPage(session: session, onConnected: () => setState(() => _index = 0)),
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
      _Destination(Icons.headphones_rounded, Icons.headphones_outlined, l10n.t('tab.device')),
      _Destination(Icons.bluetooth_searching_rounded, Icons.bluetooth_rounded, l10n.t('tab.scan')),
      _Destination(Icons.terminal_rounded, Icons.terminal_outlined, l10n.t('tab.lab')),
      _Destination(Icons.settings_rounded, Icons.settings_outlined, l10n.t('tab.settings')),
    ];

    final body = IndexedStack(index: _index, children: pages);
    final maxWidth = _index == 0 ? 1180.0 : 900.0;

    return PopScope(
      // Android：在设备页按返回键 = 退出应用（而不是缩到后台）；
      // 在别的分页则先回到设备页。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index != 0) {
          setState(() => _index = 0);
          return;
        }
        quitApp(session);
      },
      child: _buildShell(context, l10n, titles, destinations, body, maxWidth),
    );
  }

  Widget _buildShell(
    BuildContext context,
    L10n l10n,
    List<String> titles,
    List<_Destination> destinations,
    Widget body,
    double maxWidth,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (value) => setState(() => _index = value),
                    labelType: NavigationRailLabelType.all,
                    leading: const Padding(
                      padding: EdgeInsets.only(top: 16, bottom: 22),
                      child: _Brand(width: 46),
                    ),
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  color: FitTheme.hairline(context),
                ),
                Expanded(
                  child: _Backdrop(
                    child: SafeArea(
                      child: Column(
                        children: [
                          _Header(
                            title: titles[_index],
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
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: Row(
              children: [
                const _Brand(width: 30),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    titles[_index],
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
          ),
          body: _Backdrop(child: SafeArea(child: body)),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: [
              for (final d in destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 极淡的纵向渐变，避免整屏死板的纯色。
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = FitTheme.isDark(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [const Color(0xFF12151C), FitColors.bgDark]
              : [const Color(0xFFF8F9FC), FitColors.bgLight],
        ),
      ),
      child: child,
    );
  }
}

class _Destination {
  const _Destination(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 4),
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
    );
  }
}
