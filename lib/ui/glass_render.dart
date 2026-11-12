import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// 加载 `shaders/glass_pane.frag`，并给每块玻璃发一个独立实例
/// （uniform 各管各的：尺寸、原点、圆角都不一样）。
class GlassPaneProgram {
  GlassPaneProgram._();

  static const String asset = 'shaders/glass_pane.frag';

  static ui.FragmentProgram? _program;
  static bool _loading = false;
  static bool _failed = false;
  static final List<VoidCallback> _waiting = <VoidCallback>[];

  /// 这个后端能不能用（拿不到就退回纯色，不崩）。
  static bool get supported => _program != null && !_failed;

  static void warmUp() {
    if (_program != null || _loading || _failed) return;
    _loading = true;
    ui.FragmentProgram.fromAsset(asset).then(
      (program) {
        _program = program;
        final waiting = List<VoidCallback>.from(_waiting);
        _waiting.clear();
        for (final callback in waiting) {
          callback();
        }
      },
      onError: (Object error, StackTrace stack) {
        _failed = true;
        _waiting.clear();
        debugPrint('glass: 面板着色器不可用，退回纯色（$error）');
      },
    ).whenComplete(() {
      _loading = false;
    });
  }

  static void whenReady(VoidCallback callback) {
    if (_program != null) {
      callback();
      return;
    }
    if (_failed) return;
    _waiting.add(callback);
    warmUp();
  }

  static ui.FragmentShader? create() {
    final program = _program;
    if (program == null) return null;
    try {
      return program.fragmentShader();
    } catch (_) {
      return null;
    }
  }
}

/// 一张截下来的背景纹理。
class GlassTexture {
  const GlassTexture({
    required this.image,
    required this.bounds,
    required this.dpr,
    required this.generation,
  });

  final ui.Image image;

  /// 截取时的全局位置与尺寸（dp）。
  final Rect bounds;

  /// 截取时的设备像素比。
  final double dpr;

  /// 递增序号：让 painter 知道换图了。
  final int generation;

  double get pixelWidth => image.width.toDouble();
  double get pixelHeight => image.height.toDouble();
}

/// 纹理的发布处：玻璃面板监听它，纹理一换就重画（不需要重建 widget）。
class GlassTextureStore extends ValueNotifier<GlassTexture?> {
  GlassTextureStore() : super(null);
}

/// 全局就两份纹理（和 FlClash 的 atlas 一个思路，只是分了两层）：
///
/// * [backdrop]：只有背景（色光、扫光、暗角）。卡片采样它 ——
///   卡片背后本来就没有别的控件，采样背景既真实又不会自我循环；
/// * [content]：整页内容（含卡片）。顶栏和底部胶囊采样它 ——
///   滚动的列表从胶囊下面穿过去时，会被真的折进玻璃里。
///
/// 两层互不包含对方，所以永远不会出现「玻璃采样到自己」的反馈。
class GlassTextures {
  GlassTextures._();

  static final GlassTextureStore backdrop = GlassTextureStore();
  static final GlassTextureStore content = GlassTextureStore();

  static GlassTextureStore of(GlassSourceKind kind) =>
      kind == GlassSourceKind.content ? content : backdrop;
}

enum GlassSourceKind { backdrop, content }

/// 把一个子树持续截成纹理，发布给所有玻璃面板。
///
/// 关键点（和 FlClash 的 `_capture` 一样）：
/// * 截图在 **post-frame** 里做，绝不干扰本帧的绘制；
/// * 不是每帧都截：`interval` 控制节奏（内容 2 帧一次、背景 8 帧一次）；
/// * 没有帧的时候（界面静止）就不截 —— 不额外耗电；
/// * 旧图在新图发布后**下一帧**才 dispose，避免正在采样的图被回收。
class GlassCapture extends StatefulWidget {
  const GlassCapture({
    super.key,
    required this.kind,
    required this.child,
    this.interval = 2,
    this.maxPixelRatio = 2.0,
  });

  final GlassSourceKind kind;
  final Widget child;

  /// 每多少帧截一次（1 = 每帧）。
  final int interval;

  /// 截图的像素比上限：纹理太大既占显存又拖慢光栅化。
  final double maxPixelRatio;

  @override
  State<GlassCapture> createState() => _GlassCaptureState();
}

class _GlassCaptureState extends State<GlassCapture> {
  /// `flutter test` 会在子进程环境里写 `FLUTTER_TEST=true`。
  ///
  /// 测试里不截图：`toImageSync` 在测试光栅器上要么抛异常、要么分配一张
  /// 全屏纹理；而纹理一发布，监听它的画笔就会请求下一帧，
  /// `pumpAndSettle()` 会一直等下去。玻璃在测试里走纯色兜底即可。
  static final bool _inTest = _detectTest();

  static bool _detectTest() {
    try {
      return Platform.environment['FLUTTER_TEST'] == 'true';
    } catch (_) {
      return false;
    }
  }

  final GlobalKey _key = GlobalKey();
  GlassTexture? _current;
  int _generation = 0;
  int _frame = 0;
  bool _scheduled = false;

  /// 子树自上次截图之后有没有重画过。
  ///
  /// 这个标志是必须的：截图 → 发布新纹理 → 所有玻璃重画 → 排下一帧 →
  /// 又截图……如果没有它，界面即使完全静止也会以 `interval` 的节奏
  /// 一直产帧（每秒 30 次同步光栅化 + 几十 MB 的纹理分配）。
  bool _dirty = true;

  @override
  void initState() {
    super.initState();
    if (!_inTest) _schedule();
  }

  @override
  void dispose() {
    // 先把发布出去的纹理摘掉：否则别处还挂着的玻璃会去采样一张已经释放的图。
    final store = GlassTextures.of(widget.kind);
    if (identical(store.value, _current)) store.value = null;
    _current?.image.dispose();
    _current = null;
    super.dispose();
  }

  /// 由 [_CaptureWatcher] 在子树绘制时调用（绘制阶段，不能 setState）。
  void _markDirty() => _dirty = true;

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _tick();
    });
  }

  void _tick() {
    if (!mounted || _inTest) return;
    // 只把「下一个 post-frame」重新排上，本身**不会**产生帧：
    // 没有帧的时候它就静静等着，有帧的时候才轮到它判断要不要截。
    _schedule();
    _frame++;
    // 没变化就不截 —— 这一条是「界面静止时不烧电」的关键。
    if (!_dirty) return;
    // 还没有纹理时必须马上截一张，不能等 interval。
    if (_generation > 0 && _frame % widget.interval != 0) return;

    final object = _key.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return;
    if (object.size.isEmpty) return;

    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final dpr = ratio.clamp(1.0, widget.maxPixelRatio).toDouble();
    final ui.Image image;
    try {
      image = object.toImageSync(pixelRatio: dpr);
    } catch (_) {
      // 软件渲染 / 测试环境拿不到图：保持上一张，没有就退回纯色。
      // 不清 dirty：下一帧再试一次，成功为止。
      return;
    }
    _dirty = false;

    final texture = GlassTexture(
      image: image,
      bounds: object.localToGlobal(Offset.zero) & object.size,
      dpr: dpr,
      generation: ++_generation,
    );
    final previous = _current;
    _current = texture;
    GlassTextures.of(widget.kind).value = texture;
    if (previous != null) {
      // 等这一帧画完再释放，免得正在采样的纹理被回收。
      SchedulerBinding.instance.addPostFrameCallback((_) {
        previous.image.dispose();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 重建（换主题、换语言）也算一次变化。
    _dirty = true;
    return RepaintBoundary(
      key: _key,
      child: _CaptureWatcher(onPaint: _markDirty, child: widget.child),
    );
  }
}

/// 贴在采集子树最外层：子树只要重画一次，就把 [GlassCapture] 标脏。
///
/// 为什么要单独一个 render object：`RepaintBoundary` 会把重绘隔在自己内部，
/// 外面的 widget 根本不知道里面动过没有。
class _CaptureWatcher extends SingleChildRenderObjectWidget {
  const _CaptureWatcher({required this.onPaint, required Widget super.child});

  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCaptureWatcher(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCaptureWatcher renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

class _RenderCaptureWatcher extends RenderProxyBox {
  _RenderCaptureWatcher(this.onPaint);

  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}

/// 玻璃面板的画笔：从 [GlassTextures] 里取纹理，按自己的屏幕位置采样。
///
/// 面板自己在纹理里的位置由 [target] 在**绘制时**量（`localToGlobal`）——
/// 滚动、切页、旋转都不需要重建 widget，也就不会闪。
class GlassPanePainter extends CustomPainter {
  GlassPanePainter({
    required this.target,
    required this.source,
    required this.radius,
    required this.refraction,
    required this.frost,
    required this.tint,
    required this.dark,
    required this.brightness,
    required this.shaderProvider,
    this.padding = EdgeInsets.zero,
  }) : super(repaint: GlassTextures.of(source));

  final GlobalKey target;
  final GlassSourceKind source;
  final double radius;

  /// 折射深度（dp）。0 表示只要磨砂。
  final double refraction;

  /// 磨砂半径（dp）。0 表示完全清晰（纯折射）。
  final double frost;

  final Color tint;
  final bool dark;
  final double brightness;

  /// 由外部注入的 `FragmentShader`（加载失败时为 null → 走纯色回退）。
  final ui.FragmentShader? Function() shaderProvider;

  final EdgeInsets padding;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final texture = GlassTextures.of(source).value;
    final shader = shaderProvider();

    // —— 纹理还没准备好：纯色回退，绝不留白洞，也绝不闪 ——
    if (texture == null || shader == null) {
      _paintFallback(canvas, size);
      return;
    }

    // findRenderObject() 返回的是 RenderObject，而 localToGlobal 在 RenderBox 上
    // —— 必须先收窄，否则编译不过（CI 就是这么挂的）。
    final object = target.currentContext?.findRenderObject();
    final origin = object is RenderBox
        ? object.localToGlobal(Offset.zero) - texture.bounds.topLeft
        : Offset.zero;

    var index = 0;
    void put(double v) => shader.setFloat(index++, v);

    // 顺序必须和 shaders/glass_pane.frag 一致。
    put(size.width);
    put(size.height);
    put(texture.pixelWidth);
    put(texture.pixelHeight);
    put(origin.dx);
    put(origin.dy);
    put(texture.dpr);
    put(radius);
    put(radius);
    put(radius);
    put(radius);
    put((radius * 0.55).clamp(1.0, 18.0));
    put(refraction);
    put((size.shortestSide * 0.012).clamp(0.0, 0.8));
    put(frost);
    put(dark ? 0.30 : 0.42);
    put(dark ? 0.10 : 0.06);
    put(dark ? 1.14 : 1.20);
    put(brightness);
    put(tint.r);
    put(tint.g);
    put(tint.b);
    put(0.0); // tint 的透明度交给外层的渐变染色层，这里只提色相

    shader.setImageSampler(0, texture.image);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  void _paintFallback(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [
            tint.withValues(alpha: dark ? 0.62 : 0.72),
            tint.withValues(alpha: dark ? 0.50 : 0.62),
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(GlassPanePainter oldDelegate) =>
      oldDelegate.target != target ||
      oldDelegate.source != source ||
      oldDelegate.radius != radius ||
      oldDelegate.refraction != refraction ||
      oldDelegate.frost != frost ||
      oldDelegate.tint != tint ||
      oldDelegate.dark != dark ||
      oldDelegate.brightness != brightness ||
      oldDelegate.padding != padding;
}


/// 让面板在自己**移动**时也重画。
///
/// 为什么需要：滚动列表时，卡片本身不会 rebuild，`CustomPaint` 也就不会重画；
/// 但着色器用的 `uOrigin`（面板在纹理里的位置）变了。不重画的话，
/// 折射花纹会「粘」在原地，跟着内容走的时候看起来像贴纸。
///
/// 做法很轻：绘制时比较一下全局位置，变了就在帧末 `markNeedsPaint()` 一次。
class GlassPaneMotionRepaint extends SingleChildRenderObjectWidget {
  const GlassPaneMotionRepaint({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGlassPaneMotionRepaint();
}

class _RenderGlassPaneMotionRepaint extends RenderProxyBox {
  Offset? _last;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final at = localToGlobal(Offset.zero);
    if (_last == at) return;
    _last = at;
    // 这一帧用的是新位置，但着色器的 uniform 是上一帧写的 —— 下一帧补一次。
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) markNeedsPaint();
    });
  }
}
