#include <metal_stdlib>
using namespace metal;

// StarCatch 介质层：胶片颗粒 + 阈下扫描线。
//
// 颗粒幅度 0.02，种子按 8fps 步进（time 由 Swift 侧量化后传入亦可，
// 此处直接 floor(time * 8) —— 温和的胶片颗粒，不是每帧刷新的电视雪花）。
// 扫描线 ±0.006 亮度调制，知觉阈值以下，只提供"介质存在感"。
// 颗粒同时为 OLED 低灰阶渐变提供 dither，消除 banding。

static float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

[[ stitchable ]] half4 grain(float2 position, half4 color, float time, float intensity) {
    float seed = floor(time * 8.0);
    float n = hash21(position + float2(seed * 17.13, seed * 9.71));
    float g = (n - 0.5) * 2.0 * intensity;

    // 扫描线与颗粒属于同一介质层；强度归零时必须一起彻底关闭。
    float scan = sin(position.y * (M_PI_F / 3.0)) * intensity * 0.3;

    half3 rgb = color.rgb + half3(g + scan);
    return half4(max(rgb, half3(0.0)), color.a);
}
