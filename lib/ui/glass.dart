import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 液态玻璃的公共数值。
///
/// 参考 FlClash 的「极致液态玻璃」：玻璃不是一块半透明色块，而是
/// **模糊背板 + 带方向的染色 + 一圈镜面高光**。这里没有它的折射着色器
/// （需要额外的 `.frag` 资源和 Android 端真机验证），用同样的三层结构
/// 近似，观感接近，成本低得多。
class GlassBlur {
  /// 卡片：模糊太重会让文字后面的内容糊成一片，14 足够「有厚度」。
  static const double card = 14;

  /// 顶栏 / 底部胶囊：它们面积小、内容少，可以更透。
  static const double bar = 22;

  /// 主卡（设备信息）：背景里的一团蓝光需要被「折」进来。
  static const double hero = 20;
}

class GlassMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration page = Duration(milliseconds: 300);
  static const Duration dock = Duration(milliseconds: 360);
  static const Duration fade = Duration(milliseconds: 220);

  /// `MediaQuery.disableAnimations`（Android 的「移除动画」/ iOS 的减弱动态效果）。
  static bool reduce(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

/// 玻璃面板：背景模糊 + 半透明渐变 + 镜面描边 + 顶部高光。
///
/// 结构（从外到内）：
/// 1. 外阴影（只有浅色主题真正看得见，深色主题等于给玻璃一个落点）；
/// 2. [ClipRRect] + [BackdropFilter]，把背后的东西模糊掉；
/// 3. 染色层：同一颜色的两个透明度做斜向渐变，模拟玻璃厚度不均；
/// 4. [Material]：让 [InkWell] 的水波画在染色层**之上**，不会被玻璃盖住；
/// 5. [CustomPaint]：1.2 px 的镜面圈 + 顶部一道很淡的反光。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = FitRadius.card,
    this.blur = GlassBlur.card,
    this.tint,
    this.tintAlpha,
    this.gradient,
    this.padding,
    this.rim = true,
    this.shadow = true,
    this.ink = true,
  });

  final Widget child;
  final double radius;
  final double blur;

  /// 玻璃底色。默认深色 `#1B232D`、浅色纯白。
  final Color? tint;

  /// 底色透明度。深色 0.56、浅色 0.66。
  final double? tintAlpha;

  /// 自定义染色渐变（优先于 [tint] / [tintAlpha]）。
  final Gradient? gradient;

  final EdgeInsetsGeometry? padding;

  /// 是否画镜面描边。
  final bool rim;

  /// 是否画外阴影。
  final bool shadow;

  /// 是否插入一层透明 [Material]（给水波、[InkWell] 用）。
  final bool ink;

  @override
  Widget build(BuildContext context) {
    final dark = FitTheme.isDark(context);
    final shape = BorderRadius.circular(radius);
    final base = tint ?? (dark ? const Color(0xFF1B232D) : Colors.white);
    final alpha = tintAlpha ?? (dark ? 0.56 : 0.66);
    final fill = gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: math.min(1.0, alpha + 0.10)),
            base.withValues(alpha: math.max(0.0, alpha - 0.08)),
          ],
        );

    // padding 必须在染色层**里面**：否则内边距那一条不会被玻璃盖住，
    // 卡片边缘会出现一圈「没上色」的缝。
    final body = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    final content = DecoratedBox(
      decoration: BoxDecoration(gradient: fill),
      child: ink ? Material(type: MaterialType.transparency, child: body) : body,
    );

    final blurred = blur <= 0
        ? ClipRRect(
            borderRadius: shape,
            clipBehavior: Clip.antiAlias,
            child: content,
          )
        : ClipRRect(
            borderRadius: shape,
            clipBehavior: Clip.antiAlias,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: content,
            ),
          );

    Widget surface = CustomPaint(
      foregroundPainter: rim
          ? _GlassRimPainter(radius: radius, dark: dark)
          : null,
      child: blurred,
    );

    if (shadow) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.26 : 0.09),
              blurRadius: 22,
              spreadRadius: -10,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: surface,
      );
    }
    return surface;
  }
}

/// 顶栏的磨砂底：和 [GlassSurface] 同源，但没有圆角和阴影，
/// 用来铺满 [AppBar.flexibleSpace]。
class GlassBarVeil extends StatelessWidget {
  const GlassBarVeil({super.key, this.blur = GlassBlur.bar});

  final double blur;

  @override
  Widget build(BuildContext context) {
    final dark = FitTheme.isDark(context);
    final tint = dark ? const Color(0xFF0B0F14) : const Color(0xFFF7F8FB);
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tint.withValues(alpha: dark ? 0.78 : 0.86),
                tint.withValues(alpha: dark ? 0.46 : 0.58),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: FitTheme.hairline(context)),
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// 背景：深色渐变 + 三团缓慢漂移的色光。
///
/// 玻璃要「有东西可以折」才像玻璃。静止的纯色背景上，模糊和半透明
/// 看起来和一块灰卡片没有区别。三团光很慢（36 秒一圈）、幅度很小，
/// 不抢内容，但让玻璃边缘一直在轻轻变化。
class GlassBackdrop extends StatefulWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  /// 需要完全静止时置 true（截图、测试、省电模式）。
  static bool freezeMotion = false;

  /// `flutter test` 会在子进程环境里写 `FLUTTER_TEST=true`。
  static final bool _inTest = _detectTest();

  static bool _detectTest() {
    try {
      return Platform.environment['FLUTTER_TEST'] == 'true';
    } catch (_) {
      // 拿不到环境变量（受限的嵌入式运行时）就当不是测试。
      return false;
    }
  }

  /// 背板是 36 秒一圈、永不停止的动画。`pumpAndSettle()` 等的就是
  /// 「没有待处理的帧」，只要它还在跑就一定会超时，所以测试里不启动。
  static bool motionFrozen() => freezeMotion || _inTest;

  @override
  State<GlassBackdrop> createState() => _GlassBackdropState();
}

class _GlassBackdropState extends State<GlassBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 36),
  )..addListener(_onTick);

  /// 上一次真正重画的时间点（毫秒）。
  int _lastPaint = -1000;

  int get _nowMs => (_controller.value * 36000).round();

  void _onTick() {
    // 36 秒才走完一圈，没必要每帧重画：每 120 ms 更新一次，
    // 位移只有零点几像素，看不出台阶，但玻璃背后的模糊少做 5/6。
    final now = _nowMs;
    if ((now - _lastPaint).abs() < 120) return;
    _lastPaint = now;
    if (mounted) setState(() {});
  }

  bool get _frozen =>
      GlassBackdrop.motionFrozen() || GlassMotion.reduce(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系统开了「移除动画」就停在静止状态：省电，也不给前庭敏感的人添麻烦。
    if (_frozen) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = FitTheme.isDark(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xFF0A0E14), Color(0xFF0C1118), Color(0xFF090C11)]
                  : const [Color(0xFFF5F7FB), Color(0xFFEDF1F7), Color(0xFFF7F4EF)],
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final t = _controller.value;
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            double drift(double phase) => math.sin((t + phase) * 2 * math.pi);
            return Stack(
              children: [
                _Glow(
                  left: w * 0.46 + drift(0.0) * w * 0.05,
                  top: -h * 0.18 + drift(0.25) * h * 0.04,
                  size: w * 0.95,
                  color: FitColors.accent,
                  alpha: dark ? 0.26 : 0.16,
                ),
                _Glow(
                  left: -w * 0.40 + drift(0.5) * w * 0.05,
                  top: h * 0.34 + drift(0.75) * h * 0.04,
                  size: w * 0.88,
                  color: FitColors.accentLight,
                  alpha: dark ? 0.14 : 0.10,
                ),
                _Glow(
                  left: w * 0.08 + drift(0.2) * w * 0.04,
                  top: h * 0.70 + drift(0.6) * h * 0.04,
                  size: w * 0.72,
                  color: FitColors.gold,
                  alpha: dark ? 0.07 : 0.09,
                ),
              ],
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
    required this.left,
    required this.top,
    required this.size,
    required this.color,
    required this.alpha,
  });

  final double left;
  final double top;
  final double size;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: alpha * 0.45),
                color.withValues(alpha: 0),
              ],
              stops: const [0, 0.42, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一页一个入口，底部胶囊和侧边栏共用。
class GlassDestination {
  const GlassDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 底部玻璃胶囊。
///
/// 选中块不是一个静态色块：切换时它会沿胶囊滑动，途中横向轻微拉伸
/// （`sin` 一个半周期），到站再弹回原宽 —— 这就是 FlClash 那种「液体」
/// 的手感，全部用一条 360 ms 的曲线完成，没有额外的物理循环。
class GlassDock extends StatelessWidget {
  const GlassDock({
    super.key,
    required this.index,
    required this.onSelected,
    required this.destinations,
  });

  final int index;
  final ValueChanged<int> onSelected;
  final List<GlassDestination> destinations;

  static const double _height = 56;

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.viewPaddingOf(context);
    final dark = FitTheme.isDark(context);
    return Padding(
      // 横屏时左右可能有挖孔 / 刘海，viewPadding 会把这段让出来；
      // 竖屏时它是 0，仍然保持 14 的视觉边距。
      padding: EdgeInsets.fromLTRB(
        14 + view.left,
        6,
        14 + view.right,
        math.max(10.0, view.bottom),
      ),
      child: GlassSurface(
        radius: 28,
        blur: GlassBlur.bar,
        tint: dark ? const Color(0xFF141A22) : Colors.white,
        tintAlpha: dark ? 0.66 : 0.72,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: SizedBox(
          height: _height,
          child: _LiquidIndex(
            index: index,
            duration: GlassMotion.dock,
            builder: (context, value) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final count = destinations.length;
                  final slot = constraints.maxWidth / count;
                  final center = slot * (value + 0.5);
                  // 到整数位置时 0，途中最大 1：拉伸只在滑动时出现。
                  final bob = math.sin(math.pi * (value - value.floorToDouble()));
                  final width = math.min(slot * 0.78, 96.0) * (1 + 0.12 * bob);
                  final height = _height * (1 - 0.06 * bob);
                  return Stack(
                    children: [
                      Positioned(
                        left: center - width / 2,
                        top: (_height - height) / 2,
                        width: width,
                        height: height,
                        child: const _DockIndicator(),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < destinations.length; i++)
                            Expanded(
                              child: _DockTab(
                                destination: destinations[i],
                                selected: i == index,
                                onTap: () => onSelected(i),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 把「当前分页」变成一个连续的动画值。
///
/// 不用 [TweenAnimationBuilder]：它的 begin 语义在连续换页时不可控
/// （快速点 设备 → 设置 → 扫描 会跳位）。这里每次都从**当前显示值**出发，
/// 所以来回猛点也只会顺着走，不会闪回。
class _LiquidIndex extends StatefulWidget {
  const _LiquidIndex({
    required this.index,
    required this.duration,
    required this.builder,
  });

  final int index;
  final Duration duration;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<_LiquidIndex> createState() => _LiquidIndexState();
}

class _LiquidIndexState extends State<_LiquidIndex>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..value = 1;

  late double _from = widget.index.toDouble();
  late double _to = widget.index.toDouble();

  double get _value =>
      _from + (_to - _from) * Curves.easeOutCubic.transform(_controller.value);

  @override
  void didUpdateWidget(covariant _LiquidIndex oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;
    // 先固定当前显示值，再从它滑向新的一页。
    _from = _value;
    _to = widget.index.toDouble();
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(context, _value),
    );
  }
}

class _DockIndicator extends StatelessWidget {
  const _DockIndicator();

  @override
  Widget build(BuildContext context) {
    final dark = FitTheme.isDark(context);
    final accent = FitTheme.accentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FitRadius.pill),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: dark ? 0.30 : 0.18),
            accent.withValues(alpha: dark ? 0.14 : 0.08),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: dark ? 0.34 : 0.22)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: dark ? 0.22 : 0.14),
            blurRadius: 14,
            spreadRadius: -4,
          ),
        ],
      ),
    );
  }
}

class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final GlassDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = FitTheme.accentOf(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final base = theme.textTheme.labelSmall ?? const TextStyle();
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1,
              duration: GlassMotion.dock,
              curve: Curves.easeOutBack,
              child: Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 20,
                color: selected ? accent : muted,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: GlassMotion.fade,
              curve: Curves.easeOut,
              style: base.copyWith(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? accent : muted,
              ),
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 宽屏左侧的玻璃导航栏。
class GlassSidebar extends StatelessWidget {
  const GlassSidebar({
    super.key,
    required this.index,
    required this.onSelected,
    required this.destinations,
    this.leading,
  });

  final int index;
  final ValueChanged<int> onSelected;
  final List<GlassDestination> destinations;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final dark = FitTheme.isDark(context);
    return GlassSurface(
      radius: 28,
      blur: GlassBlur.bar,
      tint: dark ? const Color(0xFF141A22) : Colors.white,
      tintAlpha: dark ? 0.62 : 0.70,
      child: SizedBox(
        width: 94,
        child: Column(
          children: [
            if (leading != null) ...[
              const SizedBox(height: 18),
              leading!,
            ],
            const SizedBox(height: 18),
            for (var i = 0; i < destinations.length; i++)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                child: _SidebarTab(
                  destination: destinations[i],
                  selected: i == index,
                  onTap: () => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarTab extends StatelessWidget {
  const _SidebarTab({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final GlassDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = FitTheme.isDark(context);
    final accent = FitTheme.accentOf(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final base = theme.textTheme.labelSmall ?? const TextStyle();
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: GlassMotion.fast,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? FitColors.accent.withValues(alpha: dark ? 0.20 : 0.12)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? FitColors.accent.withValues(alpha: dark ? 0.34 : 0.22)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 21,
                color: selected ? accent : muted,
              ),
              const SizedBox(height: 4),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: base.copyWith(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? accent : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分页容器：所有页一直活着（滚动位置、输入框内容都不丢），
/// 切换时旧页向离开方向淡出、新页从来向滑入，类似 FlClash 的页面转场。
class LiquidPageView extends StatelessWidget {
  const LiquidPageView({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final reduce = GlassMotion.reduce(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: i != index,
              child: ExcludeSemantics(
                excluding: i != index,
                child: AnimatedOpacity(
                  opacity: i == index ? 1 : 0,
                  duration: reduce ? Duration.zero : GlassMotion.fade,
                  curve: Curves.easeInOut,
                  child: AnimatedSlide(
                    offset: i == index
                        ? Offset.zero
                        : Offset(i < index ? -0.05 : 0.05, 0),
                    duration: reduce ? Duration.zero : GlassMotion.page,
                    curve: Curves.easeOutCubic,
                    // 不在前台的分页停掉所有 ticker（骨架屏呼吸、进度动画），
                    // 免得四个页面一起烧电。
                    child: TickerMode(enabled: i == index, child: children[i]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 滚动到边界时的「拉伸」手感，和 FlClash（Android）一致。
/// 桌面端保持默认的滚轮 / 拖拽行为。
class FitScrollBehavior extends MaterialScrollBehavior {
  const FitScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (Theme.of(context).platform == TargetPlatform.android) {
      return StretchingOverscrollIndicator(
        axisDirection: details.direction,
        child: child,
      );
    }
    return child;
  }
}

/// 1.2 px 的镜面圈：左上最亮、右下最淡，再叠一道顶部反光。
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({required this.radius, required this.dark});

  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final r = math.max(0.0, radius - 0.6);
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.6), Radius.circular(r));

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        dark
            ? [
                Colors.white.withValues(alpha: 0.30),
                Colors.white.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.14),
              ]
            : [
                Colors.black.withValues(alpha: 0.10),
                Colors.black.withValues(alpha: 0.03),
                Colors.black.withValues(alpha: 0.12),
              ],
        const [0, 0.55, 1],
      );
    canvas.drawRRect(rrect, rim);

    // 顶部反光：玻璃被光压到的那一条边。只铺最上面 14 px，
    // 不要盖住卡片标题（内边距 16 px 起），否则深色字会被洗淡。
    canvas.save();
    canvas.clipRRect(rrect);
    final sheenHeight = math.min(14.0, size.height * 0.25);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, sheenHeight),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, sheenHeight),
          [
            Colors.white.withValues(alpha: dark ? 0.08 : 0.22),
            Colors.white.withValues(alpha: 0),
          ],
        ),
    );
    canvas.restore();

    // 底部内阴影：玻璃有厚度，不是一张贴纸。
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        [
          Colors.transparent,
          Colors.black.withValues(alpha: dark ? 0.16 : 0.05),
        ],
        const [0.55, 1],
      );
    canvas.drawRRect(
      rrect.deflate(1.6),
      inner,
    );
  }

  @override
  bool shouldRepaint(_GlassRimPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.dark != dark;
}
