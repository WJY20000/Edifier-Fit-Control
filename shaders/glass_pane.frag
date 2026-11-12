#version 460 core

// 液态玻璃面板 —— 由 `Paint.shader` 驱动，采样**我们自己截下来的**背景纹理。
//
// 和之前那套（ImageFilter.shader）的根本区别：
//   * ImageFilter.shader 是让引擎给「这一块」单独截一次背景，每块玻璃各截一次，
//     坐标、切页、重建全都不受我们控制（0.8.11–0.8.17 的所有问题都出在这里）；
//   * 现在是 FlClash 那种做法：`GlassCapture` 把背景/内容截成**一张**纹理，
//     所有玻璃从同一张纹理里按自己的屏幕位置取像素。玻璃再多也只有一次截取。
//
// 这个 shader 做：
//   1. 圆角矩形 SDF → 边缘法线；
//   2. 沿法线做「圆角剖面」的采样偏移 → 折射（边缘最强、向内衰减）；
//   3. 红/蓝错开 → 色散；
//   4. 12 tap 黄金角模糊 → 磨砂（纹理是清晰的，模糊在这里做）；
//   5. 双层镜面 + 边缘暗线 + 染色 + 饱和度/亮度。

#include <flutter/runtime_effect.glsl>

precision highp float;

// 玻璃面板尺寸（dp）
uniform vec2 uSize;
uniform sampler2D uTexture;

// 纹理像素尺寸、玻璃在纹理坐标系里的原点（dp）、设备像素比
uniform vec2 uTexSize;
uniform vec2 uOrigin;
uniform float uDpr;

// 四角圆角 + 斜面宽度
uniform vec4 uCorners;
uniform float uBevel;

// 折射深度（dp）、色散（dp）、磨砂半径（dp）
uniform float uRefraction;
uniform float uDispersion;
uniform float uFrost;

// 镜面、边缘暗线、饱和度、亮度
uniform float uRim;
uniform float uLine;
uniform float uSaturation;
uniform float uBrightness;

// 玻璃底色（rgb + alpha）
uniform vec4 uTint;

out vec4 fragColor;

const float kGolden = 2.39996323;

vec4 tap(vec2 dp) {
  vec2 px = (uOrigin + dp) * uDpr;
  return texture(uTexture, clamp(px / uTexSize, vec2(0.0005), vec2(0.9995)));
}

/// 12 个样本的黄金角圆盘：纹理是清晰的，磨砂在这里做。
vec4 frosted(vec2 dp, float radiusDp) {
  vec4 sum = tap(dp);
  float weight = 1.0;
  for (int i = 0; i < 12; i++) {
    float fi = float(i);
    float r = sqrt((fi + 0.5) / 12.0) * radiusDp;
    float a = fi * kGolden;
    sum += tap(dp + vec2(cos(a), sin(a)) * r);
    weight += 1.0;
  }
  return sum / weight;
}

float cornerOf(vec2 p) {
  if (p.x > 0.0) {
    return p.y > 0.0 ? uCorners.z : uCorners.y;
  }
  return p.y > 0.0 ? uCorners.w : uCorners.x;
}

float sdRoundBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
  vec2 p = FlutterFragCoord().xy;          // 面板局部坐标（dp，左上原点）
  vec2 halfSize = uSize * 0.5;
  vec2 c = p - halfSize;

  float radius = min(cornerOf(c), min(halfSize.x, halfSize.y));
  float sd = sdRoundBox(c, halfSize, radius);
  float inset = max(-sd, 0.0);             // 距边缘（内部为正，dp）

  // 法线：SDF 数值梯度，指向外。
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

  // 折射：圆角剖面（边缘陡、内部平）。
  float depth = uRefraction * (1.0 - sqrt(max(0.0, 1.0 - rise * rise)));
  vec2 sampleAt = p - normal * depth;

  // 磨砂 + 色散：中心三通道合一，边缘把 R/B 往相反方向掰开。
  vec4 base = frosted(sampleAt, uFrost);
  float part = uDispersion * rise * rise;
  if (part > 0.05) {
    base.r = frosted(sampleAt + normal * part, uFrost).r;
    base.b = frosted(sampleAt - normal * part, uFrost).b;
  }

  // 饱和度 / 亮度：玻璃把背后的颜色「提」一档。
  float luma = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
  vec3 color = mix(vec3(luma), base.rgb, uSaturation) * uBrightness;

  // 染色：同一颜色的斜向渐变，模拟玻璃厚度不均。
  vec3 tinted = mix(color, uTint.rgb, clamp(uTint.a, 0.0, 1.0));
  color = tinted;

  // 双层镜面：宽而暗的外层 + 窄而亮的内层，左右收窄、上下最强。
  float facing = 0.28 + 0.72 * clamp(abs(normal.y), 0.0, 1.0);
  float bandOuter = 1.0 - clamp(inset / max(bevel * 0.95, 1e-3), 0.0, 1.0);
  float bandInner = 1.0 - clamp(inset / max(bevel * 0.28, 1e-3), 0.0, 1.0);
  color += vec3(uRim * facing * (bandOuter * bandOuter * 0.75 +
                                bandInner * bandInner * 0.45));

  // 边缘暗线：玻璃与背景的分界。
  float hairline = 1.0 - clamp(inset / 1.1, 0.0, 1.0);
  color *= 1.0 - uLine * hairline;

  // 底部内阴影：光从上面来，玻璃有厚度。
  float low = clamp((p.y / max(uSize.y, 1.0) - 0.72) / 0.28, 0.0, 1.0);
  color *= 1.0 - 0.10 * low;

  // 抗锯齿：边缘一像素内渐隐。
  float alpha = clamp(-sd + 0.5, 0.0, 1.0);
  fragColor = vec4(clamp(color, 0.0, 1.0), alpha);
}
