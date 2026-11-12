import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// 加载 `shaders/dock_lens.frag`。
///
/// 和 `GlassOptics`（折射滤镜）是两套独立的东西：这里拿到的
/// [ui.FragmentShader] 不做 `ImageFilter`，而是直接当 `Paint.shader` 用，
/// 由我们自己把「胶囊那排图标的截图」喂进去，做真正的放大 + 弯折 + 色散。
class DockLensProgram {
  DockLensProgram._();

  static const String asset = 'shaders/dock_lens.frag';

  static ui.FragmentProgram? _program;
  static bool _loading = false;
  static bool _failed = false;
  static final List<VoidCallback> _waiting = <VoidCallback>[];

  /// 着色器能不能用（拿不到就安静地退回静态透镜）。
  static bool get ready => _program != null;

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
        debugPrint('dock lens: 着色器不可用，退回静态透镜（$error）');
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

  /// 每块透镜一个独立实例（uniform 各管各的）。
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

/// 真·折射透镜。
///
/// 做法：
/// 1. 被截图的 [RepaintBoundary]（胶囊里那排图标 + 一层底色）在**上一帧**
///    已经画好，这里用 `toImageSync` 抓成一张小纹理（只有胶囊那么大，很便宜）；
/// 2. 透镜用 `Paint.shader` 画：围绕中心放大 [magnify] 倍，边缘再向外弯折
///    [bend] dp，红蓝通道错开 [dispersion] dp —— 真的在采样，不是复制一份
///    再 `Transform.scale`；
/// 3. 抓图有节流（33 ms），透镜停下后不再抓，也不占额外帧。
class DockLensContent extends StatefulWidget {
  const DockLensContent({
    super.key,
    required this.sourceKey,
    required this.rect,
    required this.radius,
    required this.dark,
    this.magnify = 1.14,
    this.bend = 9,
    this.dispersion = 2.4,
    this.rim = 0.20,
    this.darken = 0.10,
    this.fallback,
  });

  /// 被截图的边界（胶囊内容区，覆盖整条胶囊坐标）。
  final GlobalKey sourceKey;

  /// 透镜在胶囊坐标系里的位置（dp）。
  final Rect rect;

  final double radius;

  /// 是否深色主题。
  final bool dark;

  final double magnify;
  final double bend;
  final double dispersion;
  final double rim;
  final double darken;

  /// 着色器 / 截图不可用时画这个（保持旧观感，绝不白屏）。
  final Widget? fallback;

  @override
  State<DockLensContent> createState() => _DockLensContentState();
}

class _DockLensContentState extends State<DockLensContent> {
  /// 截图倍率：透镜还要再放大 1.14 倍，2 倍截图会糊；胶囊很小，
  /// 3 倍也只有 1100×190 左右，代价可以忽略。
  static const double _captureScale = 3.0;

  /// 两次抓图的最小间隔。
  static const int _minGapMs = 33;

  ui.FragmentShader? _shader;
  ui.Image? _image;
  int _lastCaptureMs = -100000;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    // 已经就绪就直接拿（不能在 initState 里 setState）；否则等它加载完。
    _shader = DockLensProgram.create();
    if (_shader == null) {
      DockLensProgram.warmUp();
      DockLensProgram.whenReady(() {
        if (!mounted) return;
        final shader = DockLensProgram.create();
        setState(() => _shader = shader);
        _scheduleCapture();
      });
    }
    _scheduleCapture();
  }

  @override
  void didUpdateWidget(DockLensContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 透镜动了才需要重新抓图（图标本身没变）。
    if (oldWidget.rect != widget.rect) _scheduleCapture();
  }

  @override
  void dispose() {
    _image?.dispose();
    try {
      _shader?.dispose();
    } catch (_) {
      // 引擎已经回收时忽略。
    }
    super.dispose();
  }

  void _scheduleCapture() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _capture();
    });
  }

  void _capture() {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCaptureMs < _minGapMs) {
      // 动画还在跑，下一帧再来；静止后就不会再抓了。
      _scheduleCapture();
      return;
    }
    final object = widget.sourceKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return;
    _lastCaptureMs = now;
    try {
      final image = object.toImageSync(pixelRatio: _captureScale);
      final previous = _image;
      setState(() => _image = image);
      if (previous != null) {
        // 等这一帧画完再释放旧纹理，免得正在采样的图被回收。
        SchedulerBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
    } catch (_) {
      // 测试环境 / 软件渲染拿不到图：保留上一张，没有就走 fallback。
    }
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    final image = _image;
    final fallback = widget.fallback ?? const SizedBox.shrink();
    if (shader == null || image == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: CustomPaint(
        painter: _LensShaderPainter(
          shader: shader,
          image: image,
          source: widget.rect.topLeft,
          scale: _captureScale,
          radius: widget.radius,
          dark: widget.dark,
          magnify: widget.magnify,
          bend: widget.bend,
          dispersion: widget.dispersion,
          rim: widget.rim,
          darken: widget.darken,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// 把 uniform 按 `shaders/dock_lens.frag` 的声明顺序写进去，然后当画笔用。
class _LensShaderPainter extends CustomPainter {
  const _LensShaderPainter({
    required this.shader,
    required this.image,
    required this.source,
    required this.scale,
    required this.radius,
    required this.dark,
    required this.magnify,
    required this.bend,
    required this.dispersion,
    required this.rim,
    required this.darken,
  });

  final ui.FragmentShader shader;
  final ui.Image image;

  /// 透镜左上角在纹理坐标系里的位置（dp）。
  final Offset source;
  final double scale;
  final double radius;
  final bool dark;
  final double magnify;
  final double bend;
  final double dispersion;
  final double rim;
  final double darken;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || image.width == 0) return;
    var index = 0;
    void put(double value) => shader.setFloat(index++, value);

    // uSize
    put(size.width);
    put(size.height);
    // uTexSize（px）
    put(image.width.toDouble());
    put(image.height.toDouble());
    // uSource（dp）
    put(source.dx);
    put(source.dy);
    // uScale / uMagnify / uBend / uDispersion / uRadius
    put(scale);
    put(magnify);
    put(bend);
    put(dispersion);
    put(radius);
    // uTint：一层很淡的底色，深色主题偏冷、浅色偏白
    final tint = dark ? const Color(0xFF0B1119) : Colors.white;
    put(tint.r);
    put(tint.g);
    put(tint.b);
    put(dark ? 0.10 : 0.04);
    // uBrightness / uRim / uDark
    put(dark ? 1.06 : 1.02);
    put(rim);
    put(darken);

    shader.setImageSampler(0, image);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_LensShaderPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.source != source ||
      oldDelegate.scale != scale ||
      oldDelegate.radius != radius ||
      oldDelegate.dark != dark ||
      oldDelegate.magnify != magnify ||
      oldDelegate.bend != bend ||
      oldDelegate.dispersion != dispersion ||
      oldDelegate.rim != rim ||
      oldDelegate.darken != darken;
}
