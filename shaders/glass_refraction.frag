#version 460 core

// 液态玻璃的折射层。
//
// 由 ui.ImageFilter.shader 驱动：引擎会把「玻璃背后的画面」作为纹理
// 喂进 uTexture，并把纹理尺寸写进 uSize（第 0、1 个 float）。
// 其余 uniform 由 lib/ui/glass_optics.dart 写入，顺序必须与那里的
// _write() 一一对应。
//
// 这里做四件事（按 FlClash 的设计语言，公式为本项目独立推导）：
//   1. 圆角矩形的有符号距离 → 边缘法线；
//   2. 沿法线做「圆角剖面」采样偏移，边缘最强、向内衰减 —— 折射；
//   3. 红 / 蓝通道沿法线错开采样 —— 色散（边缘的彩边）；
//   4. 镜面高光 + 边缘暗线 + 跟手指的触摸光。

#include <flutter/runtime_effect.glsl>

precision highp float;

// —— 引擎写入 ——
uniform vec2 uSize;        // 纹理尺寸（px）
uniform sampler2D uTexture;

// —— 应用写入，顺序见 glass_optics.dart ——
uniform vec2 uDp;          // 玻璃尺寸（dp）
uniform float uDpr;        // 设备像素比
uniform vec4 uCorners;     // 圆角：左上、右上、右下、左下（dp）
uniform float uBevel;      // 边缘斜面宽度（dp）
uniform float uRefraction; // 折射深度（dp）
uniform float uDispersion; // 色散强度（dp）
uniform float uRim;        // 镜面强度
uniform float uLine;       // 边缘暗线强度
uniform float uSaturation; // 饱和度
uniform vec2 uGlow;        // 触摸光中心（dp）
uniform float uGlowStrength;
uniform float uGlowReach;
uniform float uAmount;     // 整体强度，0 时等于不做处理

out vec4 fragColor;

/// 该象限的圆角（p 是相对中心的 dp 坐标，y 向下）。
float cornerRadius(vec2 p) {
  if (p.x > 0.0) {
    return p.y > 0.0 ? uCorners.z : uCorners.y;
  }
  return p.y > 0.0 ? uCorners.w : uCorners.x;
}

/// 圆角矩形的有符号距离：内部为负，外部为正。
float sdRoundBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec4 sampleAt(vec2 px) {
  vec2 uv = px / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  // GLES 后端的 y 轴方向相反。
  uv.y = 1.0 - uv.y;
#endif
  return texture(uTexture, clamp(uv, vec2(0.0005), vec2(0.9995)));
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 p = px / max(uDpr, 1.0);          // dp
  vec2 halfSize = uDp * 0.5;
  vec2 c = p - halfSize;

  float radius = min(cornerRadius(c), min(halfSize.x, halfSize.y));
  float distance = sdRoundBox(c, halfSize, radius);
  float inset = max(-distance, 0.0);      // 距边缘多远（内部为正）

  // 法线：SDF 的数值梯度，指向外部。
  float eps = 0.75;
  vec2 normal = normalize(
    vec2(
      sdRoundBox(c + vec2(eps, 0.0), halfSize, radius) -
        sdRoundBox(c - vec2(eps, 0.0), halfSize, radius),
      sdRoundBox(c + vec2(0.0, eps), halfSize, radius) -
        sdRoundBox(c - vec2(0.0, eps), halfSize, radius)
    ) + vec2(1e-5)
  );

  float bevel = max(min(uBevel, min(halfSize.x, halfSize.y) * 0.5), 0.001);
  float rise = 1.0 - clamp(inset / bevel, 0.0, 1.0);

  // 圆角剖面：越靠近边缘越陡，向内迅速变平。
  float depth = uRefraction * (1.0 - sqrt(max(0.0, 1.0 - rise * rise)));
  vec2 shift = -normal * depth * uDpr;

  // 色散：红蓝通道沿法线相反方向各偏一点。
  float part = uDispersion * rise * rise * uDpr;
  vec4 base;
  if (part > 0.05) {
    vec4 mid = sampleAt(px + shift);
    float red = sampleAt(px + shift + normal * part).r;
    float blue = sampleAt(px + shift - normal * part).b;
    base = vec4(red, mid.g, blue, mid.a);
  } else {
    base = sampleAt(px + shift);
  }

  // 饱和度：玻璃会把背后的颜色「提亮」一档。
  float luma = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
  vec3 color = mix(vec3(luma), base.rgb, uSaturation);

  // 镜面高光：边缘一圈，上下最强、左右收窄；接近边缘时迅速衰减。
  float band = 1.0 - clamp(inset / max(bevel * 0.9, 1e-3), 0.0, 1.0);
  float facing = 0.30 + 0.70 * clamp(abs(normal.y), 0.0, 1.0);
  float shine = uRim * band * band * facing;
  color += vec3(shine);

  // 边缘暗线：玻璃和背景的分界，让轮廓「立」起来。
  float line = 1.0 - clamp(inset / 1.2, 0.0, 1.0);
  color *= 1.0 - uLine * line;

  // 触摸光：跟着手指，落在哪就亮在哪。
  if (uGlowStrength > 0.0) {
    vec2 toGlow = p - uGlow;
    float reach = max(uGlowReach, 1.0);
    color += vec3(uGlowStrength * exp(-dot(toGlow, toGlow) / (reach * reach)));
  }

  color = mix(base.rgb, color, clamp(uAmount, 0.0, 1.0));
  fragColor = vec4(min(color, vec3(1.0)), 1.0);
}
