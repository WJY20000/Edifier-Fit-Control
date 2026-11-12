import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'dock_lens.dart';
import 'glass_render.dart';
import 'theme.dart';

/// 液态玻璃的公共数值。
///
/// 参考 FlClash 的「极致液态玻璃」：玻璃不是一块半透明色块，而是
/// **磨砂背板 + 带方向的染色 + 一圈镜面高光**。数值按面板尺寸分组，
/// 卡片轻、顶栏/胶囊透。
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

/// 玻璃面板：从共享纹理里采样（折射 + 磨砂 + 镜面）+ 半透明染色。
///
/// 结构（从外到内）：
/// 1. 外阴影（只有浅色主题真正看得见，深色主题等于给玻璃一个落点）；
/// 2. [CustomPaint] + [GlassPanePainter]：按面板自己的屏幕位置，
///    从 [GlassTextures] 的纹理里采样，着色器做折射/磨砂/镜面；
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
    this.source = GlassSourceKind.backdrop,
  });

  final Widget child;
  final double radius;

  /// 磨砂半径：纹理是清晰的，模糊由着色器做，这里给的是采样半径（dp）。
  final double blur;

  /// 玻璃底色。默认深色 `#1B232D`、浅色纯白。
  final Color? tint;

  /// 底色透明度。深色 0.62、浅色 0.72。
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

  /// 折射深度（dp）。空时按磨砂半径推一个；传 0 表示只要磨砂、不要弯折。
  final double? refraction;

  /// 从哪张纹理里取背景：
  /// * [GlassSourceKind.backdrop] —— 卡片、面板（背后是背景色光）；
  /// * [GlassSourceKind.content] —— 顶栏、底部胶囊（背后是滚动的内容）。
  final GlassSourceKind source;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  /// 面板自己的 render object：绘制时用它把「全局坐标」换算成纹理坐标。
  final GlobalKey _paneKey = GlobalKey();

  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    if (_shader != null) return;
    GlassPaneProgram.warmUp();
    // 先同步取一次：着色器已经预热好时，这里直接就拿到了，
    // 不需要在 initState 里 setState（那会多排一次构建）。
    _shader = GlassPaneProgram.create();
    if (_shader != null) return;
    GlassPaneProgram.whenReady(() {
      if (!mounted) return;
      setState(() => _shader = GlassPaneProgram.create());
    });
  }

  @override
  void dispose() {
    try {
      _shader?.dispose();
    } catch (_) {
      // 引擎已经回收时忽略。
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = FitTheme.isDark(context);
    final shape = BorderRadius.circular(widget.radius);
    final base = widget.tint ?? (dark ? const Color(0xFF1B232D) : Colors.white);
    final alpha = widget.tintAlpha ?? (dark ? 0.62 : 0.72);
    final fill = widget.gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: math.min(1.0, alpha + 0.08)),
            base.withValues(alpha: math.max(0.0, alpha - 0.10)),
          ],
        );

    // padding 必须在染色层**里面**：否则内边距那一条不会被玻璃盖住。
    final body = widget.padding == null
        ? widget.child
        : Padding(padding: widget.padding!, child: widget.child);
    final content = DecoratedBox(
      decoration: BoxDecoration(gradient: fill),
      child: widget.ink
          ? Material(type: MaterialType.transparency, child: body)
          : body,
    );

    final depth = widget.refraction ??
        (widget.blur * 0.55).clamp(4.0, 12.0).toDouble();

    Widget surface = Stack(
      key: _paneKey,
      children: [
        // 1. 玻璃底：从共享纹理里采样（折射 + 磨砂 + 镜面），永远在内容和染色下面。
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: shape,
              child: GlassPaneMotionRepaint(
                child: CustomPaint(
                  painter: GlassPanePainter(
                    target: _paneKey,
                    source: widget.source,
                    radius: widget.radius,
                    refraction: widget.blur <= 0 && depth == 0 ? 0 : depth,
                    frost: widget.blur,
                    tint: base,
                    dark: dark,
                    brightness: dark ? 1.04 : 1.02,
                    shaderProvider: () => _shader,
                  ),
                ),
              ),
            ),
          ),
        ),
        // 2. 染色 + 内容
        ClipRRect(
          borderRadius: shape,
          clipBehavior: Clip.antiAlias,
          child: content,
        ),
      ],
    );

    if (widget.rim && widget.blur > 0) {
      surface = CustomPaint(
        foregroundPainter: _GlassRimPainter(
          radius: widget.radius,
          dark: dark,
        ),
        child: surface,
      );
    }

    if (widget.shadow) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.30 : 0.07),
              blurRadius: 34,
              spreadRadius: -12,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: surface,
      );
    }
    return surface;
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
///
/// 采样的是 `backdrop` 纹理：body 在 AppBar **下面**（Scaffold 没有
/// `extendBodyBehindAppBar`），顶栏背后只有背景，采内容纹理只会钳到第一行像素。
/// 纹理没准备好时退化成半透明纯色，**不是** `BackdropFilter`：
/// 0.8.11–0.8.17 的闪屏，根源就是 `BackdropFilter` 的图层在重建。
class GlassBarVeil extends StatelessWidget {
  const GlassBarVeil({
    super.key,
    this.blur = GlassBlur.bar,
    this.source = GlassSourceKind.backdrop,
  });

  final double blur;
  final GlassSourceKind source;

  @override
  Widget build(BuildContext context) {
    final dark = FitTheme.isDark(context);
    final tint = dark ? const Color(0xFF0B0F14) : const Color(0xFFF7F8FB);
    return GlassSurface(
      radius: 0,
      blur: blur,
      tint: tint,
      tintAlpha: dark ? 0.52 : 0.58,
      refraction: 0,
      source: source,
      rim: false,
      shadow: false,
      ink: false,
      child: const SizedBox.expand(),
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

  /// 重画间隔。36 秒走完一圈，200 ms 一次的位移只有零点几像素。
  /// 背景一变，玻璃采样到的纹理就要重新截一次（8 帧一次），
  /// 所以这里不能太快：5 fps 已经看不出顿，再快只是白烧电。
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
        // 整个背景层被截成一张纹理，所有卡片从这里采样。
        // 只包背景（不含页面内容）—— 所以卡片永远不会采样到卡片，没有反馈。
        GlassCapture(
          kind: GlassSourceKind.backdrop,
          interval: 8,
          child: Stack(
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
                  double drift(double phase) =>
                      math.sin((t + phase) * 2 * math.pi);
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
                            alpha: dark ? 0.26 : 0.20,
                          ),
                          (
                            center: Offset(
                              -w * 0.40 + drift(0.5) * w * 0.05 + w * 0.44,
                              h * 0.34 + drift(0.75) * h * 0.04 + w * 0.44,
                            ),
                            radius: w * 0.44,
                            color: FitColors.accentLight,
                            alpha: dark ? 0.14 : 0.12,
                          ),
                          (
                            center: Offset(
                              w * 0.08 + drift(0.2) * w * 0.04 + w * 0.36,
                              h * 0.70 + drift(0.6) * h * 0.04 + w * 0.36,
                            ),
                            radius: w * 0.36,
                            color: FitColors.gold,
                            alpha: dark ? 0.07 : 0.10,
                          ),
                        ],
                      ),
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
            ],
          ),
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
/// 合成一层是为了省重绘：背景每 200 ms 变一次，纹理每 8 帧重截一次，
/// 图层越少、合成越轻。
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
/// 对齐 FlClash 的「液态玻璃」导航条：
/// 1. 选中块（透镜）宽度刚好一个格子，图标和文字都严丝合缝地居中；
/// 2. 透镜用**弹簧**驱动，可以手指左右拖着走，松开吸附到最近的格子；
/// 3. 拖动时按速度横向拉伸、纵向压扁（jelly），并有一道跟着走的高光；
/// 4. 透镜里是同一排内容的**放大**版本（1.16 倍），像一块真的放大镜；
/// 5. 玻璃本身是「外发光 + 亮边 + 内亮线 + 顶部反光 + 底部暗边」几层叠出来的。
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

  /// 和 FlClash 的 `_barHeight` 一致。
  static const double _height = 62;

  /// 透镜比胶囊上下各让出这么多，看起来是「浮在里面」。
  /// 不能太大：透镜里是 1.12 倍的放大内容，让太多会把文字裁掉。
  static const double _lensInset = 3;

  @override
  State<GlassDock> createState() => _GlassDockState();
}

class _GlassDockState extends State<GlassDock>
    with SingleTickerProviderStateMixin {
  /// 指尖位置（相对胶囊左上角，dp）。
  final ValueNotifier<Offset?> _glowAt = ValueNotifier<Offset?>(null);

  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 460),
  );

  /// 被透镜采样的那一层（胶囊里的一排图标 + 一层底色）。
  final GlobalKey _rowKey = GlobalKey();

  /// 透镜的连续位置（单位是「第几个格子」）。
  late final AnimationController _slide = AnimationController.unbounded(
    vsync: this,
    value: widget.index.toDouble(),
  );

  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 320,
    ratio: 0.86,
  );

  @override
  void initState() {
    super.initState();
    // 预热：第一帧就开始加载，免得第一次滑动时透镜还是静态的。
    DockLensProgram.warmUp();
  }

  @override
  void didUpdateWidget(GlassDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;
    _settle(widget.index.toDouble());
  }

  void _settle(double target) => _settleWith(target, _slide.velocity);

  void _settleWith(double target, double velocity) {
    // 甩得越快，起点速度越大：弹簧会顺势多冲一点，再回来。
    _slide.animateWith(
      SpringSimulation(
        _spring,
        _slide.value,
        target,
        velocity.clamp(-4000.0, 4000.0).toDouble(),
      ),
    );
  }

  @override
  void dispose() {
    _glow.dispose();
    _slide.dispose();
    _glowAt.dispose();
    super.dispose();
  }

  void _touch(Offset at) {
    // Listener 就在内边距里面，localPosition 已经是相对内容区的坐标。
    _glowAt.value = at;
    if (!_glow.isAnimating) _glow.forward();
  }

  void _release() {
    // 只把强度收回，位置留着让光在原地淡掉；否则会「啪」一下消失。
    _glow.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.viewPaddingOf(context);
    final dark = FitTheme.isDark(context);
    final count = widget.destinations.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        14 + view.left,
        6,
        14 + view.right,
        math.max(10.0, view.bottom),
      ),
      child: GlassSurface(
        // 胶囊实际高度是 62 + 上下 5 的内边距 = 72，半径取 34 接近正圆端。
        radius: GlassDock._height / 2 + 3,
        blur: GlassBlur.bar,
        tint: dark ? const Color(0xFF0E141C) : Colors.white,
        tintAlpha: dark ? 0.42 : 0.46,
        refraction: 13,
        // 胶囊背后是滚动的页面内容，所以从 content 纹理里采样，
        // 列表从底下穿过去时会被真的折进玻璃。
        source: GlassSourceKind.content,
        ink: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: SizedBox(
          height: GlassDock._height,
          child: count == 0
              ? const SizedBox.shrink()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final slot = width / count;
                    return Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) => _touch(event.localPosition),
                      onPointerMove: (event) => _touch(event.localPosition),
                      onPointerUp: (_) => _release(),
                      onPointerCancel: (_) => _release(),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        // 左右拖：透镜跟手走，松手吸附到最近的格子。
                        onHorizontalDragStart: (_) => _slide.stop(),
                        onHorizontalDragUpdate: (details) {
                          if (slot <= 0) return;
                          _slide.value =
                              (_slide.value + details.delta.dx / slot)
                                  .clamp(0.0, (count - 1).toDouble())
                                  .toDouble();
                        },
                        onHorizontalDragEnd: (details) {
                          final target = _slide.value.round();
                          _settleWith(
                            target.toDouble(),
                            details.velocity.pixelsPerSecond.dx,
                          );
                          if (target != widget.index) {
                            widget.onSelected(target);
                          }
                        },
                        child: AnimatedBuilder(
                        animation: Listenable.merge([_slide, _glow, _glowAt]),
                        builder: (context, _) {
                          final value = _slide.value
                              .clamp(0.0, (count - 1).toDouble())
                              .toDouble();
                          final velocity = _slide.velocity;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // 1. 指尖的光
                              if (_glow.value > 0.001 && _glowAt.value != null)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      painter: _TouchGlowPainter(
                                        center: _glowAt.value,
                                        strength: _glow.value,
                                        dark: dark,
                                      ),
                                    ),
                                  ),
                                ),
                              // 2. 内容（透镜会盖在它上面，并且采样它）
                              Positioned.fill(
                                child: RepaintBoundary(
                                  key: _rowKey,
                                  // 垫一层底色：截图带 alpha 的话，透镜
                                  // 采样到透明处会发黑。
                                  child: ColoredBox(
                                    color: dark
                                        ? const Color(0xFF0E141C)
                                        : Colors.white,
                                    child: _dockRow(
                                      count: count,
                                      selected: widget.index,
                                      onTap: widget.onSelected,
                                      magnified: false,
                                    ),
                                  ),
                                ),
                              ),
                              // 3. 透镜 + 透镜里被折射放大的内容
                              ..._lens(
                                width: width,
                                slot: slot,
                                value: value,
                                velocity: velocity,
                                dark: dark,
                              ),
                            ],
                          );
                        },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  /// 透镜：玻璃块 + 里面放大的那排内容。
  List<Widget> _lens({
    required double width,
    required double slot,
    required double value,
    required double velocity,
    required bool dark,
  }) {
    const height = GlassDock._height;
    // 速度 → 拉伸 / 压扁。钳得比 FlClash 保守一点，免得低帧率下抽动。
    final pull = (velocity * 0.020).clamp(-0.14, 0.16).toDouble();
    final baseWidth = math.max(slot - 8, 48.0);
    final lensWidth = baseWidth * (1 + pull);
    final lensHeight = (height - GlassDock._lensInset * 2) * (1 - pull.abs() * 0.22);
    final center = slot * (value + 0.5);
    final left = center - lensWidth / 2;
    final top = (height - lensHeight) / 2;

    // 放大镜的缩放中心：让透镜中心那一点在放大后仍然落在透镜中心。
    final alignX = width <= 0 ? 0.0 : (center / width) * 2 - 1;
    // 拖动强度 0..1：拖得越快，边缘镜面越亮。
    final lift = (pull.abs() / 0.16).clamp(0.0, 1.0).toDouble();

    return [
      Positioned(
        left: left,
        top: top,
        width: lensWidth,
        height: lensHeight,
        child: IgnorePointer(
          child: CustomPaint(
            painter: _DockLensPainter(
              dark: dark,
              radius: lensHeight / 2,
              lift: lift,
            ),
          ),
        ),
      ),
      Positioned(
        left: left,
        top: top,
        width: lensWidth,
        height: lensHeight,
        child: IgnorePointer(
          child: DockLensContent(
            // 用真·折射：抓胶囊自己那一层，按透镜形状放大 + 弯折 + 色散。
            sourceKey: _rowKey,
            rect: Rect.fromLTWH(left, top, lensWidth, lensHeight),
            radius: lensHeight / 2,
            dark: dark,
            magnify: 1.14,
            bend: math.min(10.0, lensHeight * 0.22),
            dispersion: 2.4,
            rim: 0.20 + 0.14 * lift,
            darken: 0.10,
            // 着色器 / 截图不可用时，退回旧的「复制一份再放大」。
            fallback: ClipRRect(
              borderRadius: BorderRadius.circular(lensHeight / 2),
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: width,
                maxWidth: width,
                minHeight: height,
                maxHeight: height,
                child: Transform.translate(
                  offset: Offset(-left, -top),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: Transform.scale(
                      scale: 1.12,
                      alignment: Alignment(alignX, 0),
                      child: _dockRow(
                        count: widget.destinations.length,
                        selected: value.round(),
                        onTap: null,
                        magnified: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// 一排图标 + 文字。`magnified` 时只画一次（透镜里的副本）。
  Widget _dockRow({
    required int count,
    required int selected,
    required ValueChanged<int>? onTap,
    required bool magnified,
  }) {
    final select = onTap;
    return ExcludeSemantics(
      excluding: magnified,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: _DockTab(
                destination: widget.destinations[i],
                selected: i == selected,
                onTap: select == null ? null : () => select(i),
                interactive: !magnified,
              ),
            ),
        ],
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
          Colors.white.withValues(alpha: (dark ? 0.14 : 0.20) * strength),
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

/// 透镜本体：外发光 + 玻璃底 + 两道亮边 + 顶部反光 + 底部暗边。
class _DockLensPainter extends CustomPainter {
  const _DockLensPainter({
    required this.dark,
    required this.radius,
    required this.lift,
  });

  final bool dark;
  final double radius;

  /// 拖动强度 0..1：越拖越亮，停下来回到常态。
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final accent = dark ? const Color(0xFF7FB6FF) : const Color(0xFF2E7BD6);

    // 1. 外发光：透镜浮在玻璃上，边缘有一圈很淡的投影。
    canvas.drawRRect(
      shape,
      Paint()
        ..color = (dark ? Colors.black : accent).withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 2. 玻璃底：上亮下暗，像一块被折起来的玻璃。
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          dark
              ? [
                  Colors.white.withValues(alpha: 0.22),
                  Colors.white.withValues(alpha: 0.06),
                ]
              : [
                  Colors.white.withValues(alpha: 0.92),
                  Colors.white.withValues(alpha: 0.58),
                ],
        ),
    );

    // 3. 顶部反光：只铺上半部分，透镜才有弧度。
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.55),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height * 0.55),
          [
            Colors.white.withValues(alpha: dark ? 0.20 : 0.55),
            Colors.white.withValues(alpha: 0),
          ],
        ),
    );
    canvas.restore();

    // 4. 外沿亮边 + 内圈细亮线：两道反射。
    canvas.drawRRect(
      shape.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = (dark ? Colors.white : Colors.white)
            .withValues(alpha: dark ? 0.36 : 0.95),
    );
    canvas.drawRRect(
      shape.deflate(2.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = accent.withValues(alpha: 0.20 + 0.25 * lift),
    );

    // 5. 底部暗边：光从上面来，下面要沉下去。
    canvas.drawRRect(
      shape.deflate(1.0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [
            Colors.transparent,
            Colors.black.withValues(alpha: dark ? 0.26 : 0.10),
          ],
          const [0.5, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_DockLensPainter oldDelegate) =>
      oldDelegate.dark != dark ||
      oldDelegate.radius != radius ||
      oldDelegate.lift != lift;
}

class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.interactive = true,
  });

  final GlassDestination destination;
  final bool selected;
  final VoidCallback? onTap;

  /// 透镜里的放大副本不可点。
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = FitTheme.accentOf(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final base = theme.textTheme.labelSmall ?? const TextStyle();

    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            selected ? destination.selectedIcon : destination.icon,
            size: 21,
            color: selected ? accent : muted,
          ),
          const SizedBox(height: 3),
          Text(
            destination.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: base.copyWith(
              fontSize: 10,
              height: 1.1,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? accent : muted,
            ),
          ),
        ],
      ),
    );

    if (!interactive || onTap == null) {
      return IgnorePointer(child: content);
    }
    // 不用 InkWell：水波是圆的、半径还跟着 Material 祖先走，
    // 在胶囊上会画出一个比格子还大的蓝圈（0.8.14 之前的截图就是这样）。
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
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
    // 0.8.17 为了让 BackdropFilter 的图层「永远是热的」，把四页**全部**
    // 画在同一个 Stack 里 —— 四个页面互相透出来，滚到哪儿都是拼在一起的。
    //
    // 0.8.18 换了架构：玻璃不再各自截背景，而是采样同一张纹理，
    // 切页不会重建任何滤镜层，所以这里不需要再让非当前页绘制。
    // [IndexedStack] 保留所有页的 State（滚动位置、输入框内容），
    // 只画当前页 —— 不会叠、不会闪。
    return IndexedStack(
      index: index,
      sizing: StackFit.expand,
      children: children,
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

    // 第二道：内圈 0.8 px 的亮线。玻璃边缘不止一道反射，
    // 只有外圈时看起来像塑料贴纸。
    canvas.drawRRect(
      rrect.deflate(2.0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [
            Colors.white.withValues(alpha: (dark ? 0.16 : 0.34) * strength),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: (dark ? 0.06 : 0.12) * strength),
          ],
          const [0, 0.5, 1],
        ),
    );

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
