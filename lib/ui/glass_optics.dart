import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 液态玻璃的「光学层」：把 `shaders/glass_refraction.frag` 接到
/// [ui.ImageFilter.shader] 上，让玻璃真的**弯折**背后的画面。
///
/// 和 `BackdropFilter` 的普通模糊不同，`ImageFilter.shader` 会把背景纹理
/// 直接交给着色器采样，于是可以做折射、色散和随法线变化的镜面 ——
/// 也就是 FlClash 底部胶囊那种「有反射」的观感。
///
/// 只在 Impeller 后端可用（Android 默认开启，Windows 走回退）；
/// 拿不到着色器、或在 `flutter test` 里，全部安静地退回磨砂，不会抛异常。
class GlassOptics {
  GlassOptics._();

  /// 与 pubspec.yaml 的 `flutter: shaders:` 同一路径。
  static const String asset = 'shaders/glass_refraction.frag';

  static ui.FragmentProgram? _program;
  static bool _loading = false;
  static bool _failed = false;
  static final List<VoidCallback> _waiting = <VoidCallback>[];

  /// 测试环境不加载资源：`flutter test` 里没有编译好的着色器，
  /// 而且 widget 测试也不该被一个异步加载左右。
  static bool get _inTest {
    try {
      return Platform.environment['FLUTTER_TEST'] == 'true';
    } catch (_) {
      return true;
    }
  }

  /// 这个后端能不能用着色器（Impeller 才支持 `ImageFilter.shader`）。
  static bool get supported {
    if (_inTest || _failed) return false;
    try {
      return ui.ImageFilter.isShaderFilterSupported;
    } catch (_) {
      return false;
    }
  }

  /// 着色器已经就绪：可以真的画折射了。
  static bool get ready => supported && _program != null;

  /// 提前加载，避免第一帧闪一下纯磨砂。
  static void warmUp() {
    if (!supported || _program != null || _loading) return;
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
        // 着色器编译失败、资源没打进去……都只是「没有折射」，不是错误。
        _failed = true;
        _waiting.clear();
        debugPrint('glass: 折射着色器不可用，退回磨砂（$error）');
      },
    ).whenComplete(() {
      _loading = false;
    });
  }

  /// 加载完成后回调一次；已经就绪则立即返回。
  static void whenReady(VoidCallback callback) {
    if (!supported) return;
    if (_program != null) return;
    _waiting.add(callback);
    warmUp();
  }

  /// 为一块玻璃创建独立着色器实例（uniform 各管各的）。
  static GlassLens? createLens() {
    final program = _program;
    if (program == null || !supported) return null;
    try {
      return GlassLens(program.fragmentShader());
    } catch (_) {
      return null;
    }
  }
}

/// 一块玻璃的着色器实例 + uniform 绑定。
class GlassLens {
  GlassLens(this.shader);

  final ui.FragmentShader shader;

  /// uniform 的排列必须和 shaders/glass_refraction.frag 一致；
  /// 前两个 float（纹理尺寸）由引擎写入，所以从下标 2 开始。
  ui.ImageFilter? filter({
    required Size size,
    required double devicePixelRatio,
    required double radius,
    required double blurSigma,
    double bevel = 18,
    double refraction = 9,
    double dispersion = 2.4,
    double rim = 0.30,
    double line = 0.10,
    double saturation = 1.22,
    Offset? glow,
    double glowStrength = 0,
    double glowReach = 64,
  }) {
    if (!size.isFinite || size.width < 2 || size.height < 2) return null;
    final values = <double>[
      size.width,
      size.height,
      devicePixelRatio <= 0 ? 1.0 : devicePixelRatio,
      radius,
      radius,
      radius,
      radius,
      bevel,
      refraction,
      dispersion,
      rim,
      line,
      saturation,
      glow?.dx ?? 0.0,
      glow?.dy ?? 0.0,
      glowStrength,
      glowReach,
      1,
    ];
    try {
      for (var i = 0; i < values.length; i++) {
        shader.setFloat(i + 2, values[i]);
      }
      // 这个 SDK 的 ImageFilter.shader 只有 shader 一个参数，
      // 采样质量用默认值（写 filterQuality: 会直接编译不过）。
      final optical = ui.ImageFilter.shader(shader);
      if (blurSigma <= 0.01) return optical;
      // 先磨砂、再折射：着色器读到的是已经糊过的背景，
      // 这样玻璃「厚」而不是一面镜子。
      return ui.ImageFilter.compose(
        outer: optical,
        inner: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    try {
      shader.dispose();
    } catch (_) {
      // 引擎已经回收时忽略。
    }
  }
}
