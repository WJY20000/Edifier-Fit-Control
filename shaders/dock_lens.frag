#version 460 core

// 底部胶囊的「真透镜」。
//
// 这里不用 ui.ImageFilter.shader（那是给背景做滤镜的），而是直接当
// Paint.shader 用：Flutter 让我们自己把一张纹理喂进来（setImageSampler），
// 于是可以做真正会放大、会弯折、会色散的透镜 —— 也就是 FlClash
// navigation_dock 里 _LensContent 那一层的独立实现。
//
// 纹理是「胶囊自己那排图标」的截图（由 RepaintBoundary 抓），
// 所以透镜里看到的是被折射放大的图标本身，而不是一张贴上去的副本。

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;        // 透镜尺寸（dp）
uniform sampler2D uTexture;

uniform vec2 uTexSize;     // 纹理尺寸（px）
uniform vec2 uSource;      // 透镜左上角在纹理坐标系里的位置（dp）
uniform float uScale;      // dp → 纹理 px 的倍率

uniform float uMagnify;    // 中心放大倍率（>1 放大）
uniform float uBend;       // 边缘弯折强度（dp）
uniform float uDispersion; // 红蓝分离（dp）
uniform float uRadius;     // 透镜圆角（dp）

uniform vec4 uTint;        // 玻璃染色 rgba（a=0 表示不染）
uniform float uBrightness; // 提亮
uniform float uRim;        // 边缘镜面
uniform float uDark;       // 底部暗边

out vec4 fragColor;

vec4 tap(vec2 uvDp) {
  vec2 px = (uSource + uvDp * uSize) * uScale;
  return texture(uTexture, clamp(px / uTexSize, vec2(0.0), vec2(1.0)));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 uv = p / uSize;
  vec2 halfSize = uSize * 0.5;
  vec2 c = p - halfSize;

  // 圆角矩形 SDF：用于边缘亮圈与弯折强度。
  float rr = min(uRadius, min(halfSize.x, halfSize.y));
  vec2 q = abs(c) - halfSize + rr;
  float sd = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rr;
  float inset = max(-sd, 0.0);

  // 归一化的「离中心多远」：0 中心，1 边缘（按宽高比拉圆）。
  vec2 pa = vec2(c.x / max(halfSize.x, 1.0), c.y / max(halfSize.y, 1.0));
  float r = clamp(length(pa), 0.0, 1.0);

  // 凸透镜：越靠边采样点越向外挤，画面在边缘被「压」出弧度。
  float bend = smoothstep(0.25, 1.0, r);
  vec2 dir = normalize(pa + vec2(1e-5));
  vec2 off = dir * bend * bend * (uBend / uSize);

  // 放大：绕中心收缩采样区域。
  vec2 zoom = (uv - 0.5) / max(uMagnify, 0.05) + 0.5;
  vec2 suv = clamp(zoom + off, vec2(0.0), vec2(1.0));

  // 色散：红 / 蓝沿法线错开，边缘才有一点彩虹边（中心几乎没有）。
  float disp = (uDispersion / max(uSize.y, 1.0)) * bend * bend;
  vec3 color = tap(suv).rgb;
  if (disp > 0.0001) {
    color.r = tap(suv + dir * disp).r;
    color.b = tap(suv - dir * disp).b;
  }

  // 磨砂感：中心轻微提亮，像玻璃把光聚了一下。
  color *= uBrightness;
  color = mix(color, uTint.rgb, clamp(uTint.a, 0.0, 1.0));

  // 边缘镜面：上下最强、左右收窄，靠边迅速衰减。
  float band = 1.0 - clamp(inset / max(rr * 0.45 + 3.0, 1.0), 0.0, 1.0);
  float facing = 0.30 + 0.70 * clamp(abs(pa.y), 0.0, 1.0);
  color += vec3(uRim * band * band * facing);

  // 底部暗边：光从上面来，玻璃有厚度。
  float low = clamp((uv.y - 0.62) / 0.38, 0.0, 1.0);
  color *= 1.0 - uDark * low;

  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
