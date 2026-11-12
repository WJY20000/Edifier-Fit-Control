import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'glass_optics.dart';
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
class GlassSurface extends StatefulWidget {
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
    this.refraction,
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

  /// 折射深度（dp）。为空时按模糊半径推一个合适的值；
  /// 传 0 表示这块玻璃只要磨砂、不要弯折。
  final double? refraction;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  GlassLens? _lens;

  /// 实际布局尺寸。ListView 里约束高度是无限的，拿不到尺寸，
  /// 所以由 [_GlassMetrics] 在布局后回填一次。
  Size? _size;

  /// 上一次算好的滤镜。卡片在 session 每次通知（电量、降噪切换……）时都会
  /// 重建，如果每次都 `setFloat` × 18 再 new 一个 `ImageFilter`，一屏十块玻璃
  /// 就是每秒几百次分配。参数没变就直接复用。
  ui.ImageFilter? _cachedFilter;
  Object? _cachedKey;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  /// 只有「会模糊或会折射」的玻璃才需要着色器。扫描页那种纯染色的列表项
  /// 一屏十几块，每块都建一个 `FragmentShader` 是白给的开销。
  bool get _needsOptics =>
      widget.blur > 0 || (widget.refraction ?? 1) != 0;

  /// 已经挂上「着色器加载完叫我」的回调，避免重复注册。
  bool _waitingForOptics = false;

  void _attach() {
    if (!_needsOptics || !GlassOptics.supported || _lens != null) return;
    if (!_waitingForOptics) {
      _waitingForOptics = true;
      GlassOptics.whenReady(() {
        _waitingForOptics = false;
        if (!mounted) return;
        setState(_attach);
      });
    }
    _lens = GlassOptics.createLens();
    // 着色器其实已经就绪（whenReady 没注册回调），就不用再等了。
    if (_lens != null) _waitingForOptics = false;
  }

  @override
  void didUpdateWidget(GlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 参数从「纯染色」变成「要模糊 / 折射」时补一个着色器实例。
    // 现在所有调用点都是字面量、不会变，但别让这里成为暗坑。
    if (_lens == null) _attach();
  }

  @override
  void dispose() {
    _lens?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = FitTheme.isDark(context);
    final shape = BorderRadius.circular(widget.radius);
    final base = widget.tint ?? (dark ? const Color(0xFF1B232D) : Colors.white);
    final alpha = widget.tintAlpha ?? (dark ? 0.56 : 0.66);
    final fill = widget.gradient ??
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
    final body = widget.padding == null
        ? widget.child
        : Padding(padding: widget.padding!, child: widget.child);
    final content = DecoratedBox(
      decoration: BoxDecoration(gradient: fill),
      child: widget.ink
          ? Material(type: MaterialType.transparency, child: body)
          : body,
    );

    Widget glassed(Size? size) {
      final lens = _lens;
      final depth = widget.refraction;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cacheKey = Object.hash(
        size,
        dpr,
        widget.radius,
        widget.blur,
        depth,
        dark,
        lens == null,
      );
      if (cacheKey == _cachedKey) {
        final cached = _cachedFilter;
        if (cached == null) {
          return ClipRRect(
            borderRadius: shape,
            clipBehavior: Clip.antiAlias,
            child: content,
          );
        }
        return ClipRRect(
          borderRadius: shape,
          clipBehavior: Clip.antiAlias,
          child: BackdropFilter(filter: cached, child: content),
        );
      }
      final optical = (lens != null && depth != 0 && size != null)
          ? lens.filter(
              size: size,
              devicePixelRatio: dpr,
              radius: widget.radius,
              blurSigma: widget.blur * 0.55,
              bevel: math.min(widget.radius * 0.55, 18),
              refraction: depth ??
                  (widget.blur * 0.55).clamp(4.0, 12.0).toDouble(),
              // 小面板（胶囊、按钮）色散收一点，否则边缘会发紫。
              dispersion: math.min(size.shortestSide * 0.035, 1.8),
              rim: dark ? 0.26 : 0.34,
              line: dark ? 0.10 : 0.06,
              saturation: dark ? 1.18 : 1.24,
            )
          : null;
      final filter = optical ??
          (widget.blur <= 0
              ? null
              : ui.ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur));
      _cachedKey = cacheKey;
      _cachedFilter = filter;
      if (filter == null) {
        return ClipRRect(
          borderRadius: shape,
          clipBehavior: Clip.antiAlias,
          child: content,
        );
      }
      return ClipRRect(
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(filter: filter, child: content),
      );
    }

    Widget surface = glassed(_size);
    // 既没有模糊也没有折射（比如扫描页的列表项）时不需要尺寸，
    // 也就不必为了量一次尺寸白白 setState 一轮。
    if (_lens != null && _needsOptics) {
      // 着色器需要知道玻璃的尺寸；布局完成后回填，在此之前先按磨砂画。
      surface = _GlassMetrics(
        onSize: (size) {
          if (!mounted || size == _size) return;
          setState(() => _size = size);
        },
        child: surface,
      );
    }

    surface = CustomPaint(
      foregroundPainter: widget.rim
          ? _GlassRimPainter(
              radius: widget.radius,
              dark: dark,
              // 着色器会自己画随法线变化的镜面，描边就退成陪衬，
              // 否则两层高光叠在边缘会发白。
              // 只看「会不会用着色器」而不是「量到尺寸没有」：第一帧还没
              // 量出尺寸时也按 0.45 画，尺寸一到就切换，避免描边闪一下。
              // 扫描页那种 `refraction: 0` 的玻璃没有着色器镜面，
              // 描边必须保持全强度，不然卡片会看起来没有边。
              strength: (_lens != null && (widget.refraction ?? 1) != 0)
                  ? 0.45
                  : 1.0,
            )
          : null,
      child: surface,
    );

    if (widget.shadow) {
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

/// 布局后把实际尺寸报给父级。
///
/// 不用 [LayoutBuilder]：它拿到的约束在 `ListView` 里高度是无限的，
/// 而着色器必须知道真实的 dp 尺寸才能算出圆角和法线。
class _GlassMetrics extends SingleChildRenderObjectWidget {
  const _GlassMetrics({required this.onSize, required Widget super.child});

  final ValueChanged<Size> onSize;

  @override
  _RenderGlassMetrics createRenderObject(BuildContext context) =>
      _RenderGlassMetrics(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGlassMetrics renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderGlassMetrics extends RenderProxyBox {
  _RenderGlassMetrics(this.onSize);

  ValueChanged<Size> onSize;

  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final current = size;
    if (_reported == current || !current.isFinite) return;
    _reported = current;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      onSize(current);
    });
  }
}

/// 小号玻璃片：降噪 / 场景 / 音效的选项按钮、实验室快捷指令都用它。
///
/// 和 [GlassSurface] 不同，这里**不做背景模糊**：这些块本来就叠在玻璃卡片上，
/// 再模糊一层只会糊成一团，而且一屏几十个 [BackdropFilter] 在手机上很贵。
/// 玻璃感来自四层：半透明渐变 + 顶部高光带 + 1 px 镜面圈 + 选中时的品牌色辉光。
class GlassChipSurface extends StatelessWidget {
  const GlassChipSurface({
    super.key,
    required this.child,
    this.radius = FitRadius.tile,
    this.selected = false,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final bool selected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final dark = FitTheme.isDark(context);
    final accent = FitTheme.accentOf(context);
    final fill = selected
        ? [
            // 选中：品牌色被「折」进玻璃里，上亮下暗。
            accent.withValues(alpha: dark ? 0.34 : 0.20),
            accent.withValues(alpha: dark ? 0.14 : 0.07),
          ]
        : dark
            ? [
                Colors.white.withValues(alpha: 0.10),
                Colors.white.withValues(alpha: 0.03),
              ]
            : [
                Colors.white.withValues(alpha: 0.88),
                Colors.white.withValues(alpha: 0.54),
              ];
    final rim = selected
        ? accent.withValues(alpha: dark ? 0.55 : 0.42)
        : dark
            ? Colors.white.withValues(alpha: 0.13)
            : Colors.black.withValues(alpha: 0.06);
    final shape = BorderRadius.circular(radius);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: fill,
        ),
        border: Border.all(width: 1, color: rim),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: accent.withValues(alpha: dark ? 0.26 : 0.16),
              blurRadius: 16,
              spreadRadius: -6,
              offset: const Offset(0, 4),
            )
          else if (dark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              spreadRadius: -6,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.55, 1],
                      colors: [
                        Colors.white.withValues(alpha: dark ? 0.12 : 0.50),
                        Colors.white.withValues(alpha: 0),
                        Colors.black.withValues(alpha: dark ? 0.10 : 0.02),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// 按下去轻微缩小：玻璃被手指压下去的那一下。
///
/// 用 [Listener] 而不是 [GestureDetector]：后者会和内部的 [InkWell] 抢手势，
/// 导致偶发的「点一下没反应」。
class GlassPressScale extends StatefulWidget {
  const GlassPressScale({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<GlassPressScale> createState() => _GlassPressScaleState();
}

class _GlassPressScaleState extends State<GlassPressScale> {
  bool _down = false;

  void _set(bool value) {
    if (_down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
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

  /// 重画间隔。36 秒走完一圈，200 ms 一次的位移只有零点几像素；
  /// 但背景一变，压在它上面的**每一块玻璃**都要重新模糊，
  /// 所以这里宁可再慢一点（5 fps）。
  static const int _paintIntervalMs = 200;

  int get _nowMs => (_controller.value * 36000).round();

  void _onTick() {
    final now = _nowMs;
    if ((now - _lastPaint).abs() < _paintIntervalMs) return;
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
            // 三团色光和反光/暗角合成一个 CustomPaint：原来是 4 个全屏图层，
            // 每层都要单独合成一次；合成后少 3 层，也少 3 次重绘调度。
            return RepaintBoundary(
              child: CustomPaint(
                painter: _BackdropPainter(
                  progress: t,
                  dark: dark,
                  glows: [
                    (
                      center: Offset(
                        w * 0.46 + drift(0.0) * w * 0.05 + w * 0.475,
                        -h * 0.18 + drift(0.25) * h * 0.04 + w * 0.475,
                      ),
                      radius: w * 0.475,
                      color: FitColors.accent,
                      alpha: dark ? 0.26 : 0.16,
                    ),
                    (
                      center: Offset(
                        -w * 0.40 + drift(0.5) * w * 0.05 + w * 0.44,
                        h * 0.34 + drift(0.75) * h * 0.04 + w * 0.44,
                      ),
                      radius: w * 0.44,
                      color: FitColors.accentLight,
                      alpha: dark ? 0.14 : 0.10,
                    ),
                    (
                      center: Offset(
                        w * 0.08 + drift(0.2) * w * 0.04 + w * 0.36,
                        h * 0.70 + drift(0.6) * h * 0.04 + w * 0.36,
                      ),
                      radius: w * 0.36,
                      color: FitColors.gold,
                      alpha: dark ? 0.07 : 0.09,
                    ),
                  ],
                ),
                child: const SizedBox.expand(),
              ),
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

/// 一团背景色光。
typedef _Glow = ({Offset center, double radius, Color color, double alpha});

/// 背景：三团色光 + 斜向反光 + 暗角，一个 painter 画完。
///
/// 合成一层是为了省重绘：背景每 200 ms 变一次，而它上面压着的每块玻璃
/// 都要重新模糊，图层越少、合成越轻。
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({
    required this.progress,
    required this.dark,
    required this.glows,
  });

  /// 0..1 的循环进度。
  final double progress;
  final bool dark;
  final List<_Glow> glows;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    // 先画三团色光：越靠边越淡，形成「有东西可折」的底色。
    for (final glow in glows) {
      if (glow.alpha <= 0 || glow.radius <= 0) continue;
      canvas.drawCircle(
        glow.center,
        glow.radius,
        Paint()
          ..shader = ui.Gradient.radial(
            glow.center,
            glow.radius,
            [
              glow.color.withValues(alpha: glow.alpha),
              glow.color.withValues(alpha: glow.alpha * 0.45),
              glow.color.withValues(alpha: 0),
            ],
            const [0.0, 0.42, 1.0],
          ),
      );
    }

    // 斜向高光带：从左上到右下扫过，位置随进度移动。
    final travel = (progress * 2) % 1.0;
    final center = -0.45 + travel * 1.9;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * (center - 0.5), -size.height * 0.2),
          Offset(size.width * (center + 0.5), size.height * 1.2),
          [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: dark ? 0.030 : 0.20),
            Colors.white.withValues(alpha: 0),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );

    // 暗角：四角沉下去，中间的玻璃才「浮」起来。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          size.longestSide * 0.72,
          [
            Colors.transparent,
            (dark ? Colors.black : const Color(0xFF8C96A8))
                .withValues(alpha: dark ? 0.24 : 0.10),
          ],
          const [0.55, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) {
    if (oldDelegate.progress != progress || oldDelegate.dark != dark) return true;
    // 记录类型（record）自带结构化相等，但 `List.==` 比的是引用，
    // 每次 build 都新建一个列表，直接比列表会永远为 true。
    if (oldDelegate.glows.length != glows.length) return true;
    for (var i = 0; i < glows.length; i++) {
      if (oldDelegate.glows[i] != glows[i]) return true;
    }
    return false;
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
/// 三层「液体」手感：
/// 1. 选中块由**弹簧**驱动（不是固定时长的曲线），快速连点会顺着当前速度走；
/// 2. 滑动途中按速度横向拉伸、刹车时压扁（jelly）；
/// 3. 手指按下时，玻璃从指尖亮起并漫开，松手后收回（`_TouchGlowPainter`）。
class GlassDock extends StatefulWidget {
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
  State<GlassDock> createState() => _GlassDockState();
}

class _GlassDockState extends State<GlassDock>
    with SingleTickerProviderStateMixin {
  /// 指尖位置（相对胶囊左上角，dp）。
  final ValueNotifier<Offset?> _glowAt = ValueNotifier<Offset?>(null);

  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 520),
  );

  @override
  void dispose() {
    _glow.dispose();
    _glowAt.dispose();
    super.dispose();
  }

  void _touch(Offset at) {
    // Listener 包的是整块玻璃，而光画在它的内边距里面，减掉这段偏移。
    _glowAt.value = at - const Offset(6, 5);
    if (!_glow.isAnimating) _glow.forward();
  }

  void _release() {
    _glowAt.value = null;
    _glow.reverse();
  }

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
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => _touch(event.localPosition),
        onPointerMove: (event) => _touch(event.localPosition),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: GlassSurface(
          radius: 28,
          blur: GlassBlur.bar,
          tint: dark ? const Color(0xFF141A22) : Colors.white,
          tintAlpha: dark ? 0.66 : 0.72,
          refraction: 11,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: SizedBox(
            height: GlassDock._height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_glow, _glowAt]),
                      builder: (context, _) => CustomPaint(
                        painter: _TouchGlowPainter(
                          center: _glowAt.value,
                          strength: _glow.value,
                          dark: dark,
                        ),
                      ),
                    ),
                  ),
                ),
                _LiquidIndex(
                  index: widget.index,
                  builder: (context, value, velocity) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final count = widget.destinations.length;
                        if (count == 0) return const SizedBox.shrink();
                        final slot = constraints.maxWidth / count;
                        final position = value.clamp(0.0, count - 1.0).toDouble();
                        final center = slot * (position + 0.5);
                        // 速度 → 拉伸 / 压扁：和 FlClash 的 jelly 同一思路。
                        final pull = (velocity * 0.055).clamp(-0.22, 0.26).toDouble();
                        final width = math.min(slot * 0.78, 96.0) * (1 + pull);
                        final height = GlassDock._height * (1 - pull.abs() * 0.30);
                        final travel = position - position.floorToDouble();
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: center - width / 2,
                              top: (GlassDock._height - height) / 2,
                              width: width,
                              height: height,
                              child: _DockIndicator(
                                travel: travel,
                                lift: pull.abs() / 0.26,
                                dark: dark,
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < count; i++)
                                  Expanded(
                                    child: _DockTab(
                                      destination: widget.destinations[i],
                                      selected: i == widget.index,
                                      onTap: () => widget.onSelected(i),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 指尖的光：按下时从触点漫开，松手后收回。
class _TouchGlowPainter extends CustomPainter {
  const _TouchGlowPainter({
    required this.center,
    required this.strength,
    required this.dark,
  });

  final Offset? center;
  final double strength;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final at = center;
    if (at == null || strength <= 0.001 || size.isEmpty) return;
    final reach = math.max(size.shortestSide, 120.0);
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        at,
        reach,
        [
          Colors.white.withValues(alpha: (dark ? 0.16 : 0.22) * strength),
          Colors.white.withValues(alpha: 0.04 * strength),
          Colors.white.withValues(alpha: 0),
        ],
        const [0.0, 0.35, 1.0],
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_TouchGlowPainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.strength != strength ||
      oldDelegate.dark != dark;
}

/// 把「当前分页」变成一个连续的动画值。
///
/// 用**弹簧**而不是固定时长曲线：`AnimationController.unbounded` +
/// [SpringSimulation]。好处是连续换页时从当前**速度**接着走，
/// 快速点 设备 → 设置 → 扫描 不会跳位，也不会像曲线那样在终点硬停。
class _LiquidIndex extends StatefulWidget {
  const _LiquidIndex({required this.index, required this.builder});

  final int index;
  final Widget Function(BuildContext context, double value, double velocity)
      builder;

  @override
  State<_LiquidIndex> createState() => _LiquidIndexState();
}

class _LiquidIndexState extends State<_LiquidIndex>
    with SingleTickerProviderStateMixin {
  /// 质量 1、刚度 165、阻尼比 0.82：约 0.35 s 到位，带一点点回弹。
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 165,
    ratio: 0.82,
  );

  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: widget.index.toDouble(),
  );

  @override
  void didUpdateWidget(covariant _LiquidIndex oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;
    // 从当前值和当前速度出发，弹簧会自己算出该走多快。
    _controller.animateWith(
      SpringSimulation(
        _spring,
        _controller.value,
        widget.index.toDouble(),
        _controller.velocity,
      ),
    );
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
      builder: (context, _) =>
          widget.builder(context, _controller.value, _controller.velocity),
    );
  }
}

/// 选中块：玻璃色块 + 一道跟着滑动走的高光。
class _DockIndicator extends StatelessWidget {
  const _DockIndicator({
    required this.travel,
    required this.lift,
    required this.dark,
  });

  /// 在一个格子里的进度 0..1。
  final double travel;

  /// 滑动强度 0..1（速度越大越亮）。
  final double lift;

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final accent = FitTheme.accentOf(context);
    return CustomPaint(
      painter: _IndicatorPainter(
        travel: travel,
        lift: lift,
        dark: dark,
        accent: accent,
      ),
    );
  }
}

class _IndicatorPainter extends CustomPainter {
  const _IndicatorPainter({
    required this.travel,
    required this.lift,
    required this.dark,
    required this.accent,
  });

  final double travel;
  final double lift;
  final bool dark;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.height / 2),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [
            accent.withValues(alpha: dark ? 0.30 : 0.18),
            accent.withValues(alpha: dark ? 0.14 : 0.08),
          ],
        ),
    );
    canvas.drawRRect(
      rrect.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accent.withValues(alpha: dark ? 0.34 : 0.22),
    );

    // 高光带：滑动时从一侧扫到另一侧，停下（lift→0）就淡掉。
    if (lift > 0.01) {
      canvas.save();
      canvas.clipRRect(rrect);
      final x = size.width * (0.15 + 0.70 * travel);
      final band = size.width * 0.42;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x - band, 0),
            Offset(x + band, size.height * 1.4),
            [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: (dark ? 0.16 : 0.30) * lift),
              Colors.white.withValues(alpha: 0),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_IndicatorPainter oldDelegate) =>
      oldDelegate.travel != travel ||
      oldDelegate.lift != lift ||
      oldDelegate.dark != dark ||
      oldDelegate.accent != accent;
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
  const _GlassRimPainter({
    required this.radius,
    required this.dark,
    this.strength = 1.0,
  });

  final double radius;
  final bool dark;

  /// 描边强度：着色器接管镜面时降到 0.45。
  final double strength;

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
                Colors.white.withValues(alpha: 0.30 * strength),
                Colors.white.withValues(alpha: 0.05 * strength),
                Colors.white.withValues(alpha: 0.14 * strength),
              ]
            : [
                Colors.black.withValues(alpha: 0.10 * strength),
                Colors.black.withValues(alpha: 0.03 * strength),
                Colors.black.withValues(alpha: 0.12 * strength),
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
            Colors.white.withValues(alpha: (dark ? 0.08 : 0.22) * strength),
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
      oldDelegate.radius != radius ||
      oldDelegate.dark != dark ||
      oldDelegate.strength != strength;
}
