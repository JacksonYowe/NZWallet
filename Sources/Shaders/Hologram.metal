// SPDX-License-Identifier: GPL-3.0-only
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Holographic foil for SwiftUI `.colorEffect`.
// Our own approach: fractal value noise + a thin-film interference palette,
// with sparse glints. The view's alpha (the guilloche pattern) is the mask.

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i), b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0, amp = 0.5;
    for (int i = 0; i < 4; i++) { v += amp * valueNoise(p); p *= 2.03; amp *= 0.5; }
    return v;
}

// Approximates the colours of a thin transparent film as the viewing angle changes.
static float3 thinFilm(float t) {
    return 0.5 + 0.5 * cos(6.28318 * (t + float3(0.0, 0.33, 0.67)));
}

[[ stitchable ]] half4 hologramFoil(float2 position, half4 color, float2 size, float2 tilt) {
    float2 uv = position / max(size, float2(1.0));
    float n = fbm(uv * float2(3.0, 2.0) + tilt * 0.8);
    // Pseudo viewing angle: varies across the card and with device tilt.
    float angle = dot(uv - 0.5, float2(0.8, 0.6)) + tilt.x * 1.25 + tilt.y * 0.95;
    float3 rgb = thinFilm(angle * 1.6 + n * 0.7);
    float sweep = pow(0.5 + 0.5 * cos((uv.x * 0.7 + uv.y * 0.4 + tilt.x * 1.4 + tilt.y) * 6.28318), 3.0);
    rgb = mix(rgb * 0.70, float3(1.0), sweep * 0.60);
    float glint = smoothstep(0.86, 1.0, valueNoise(position / 3.0 + tilt * 25.0));
    rgb = mix(rgb, float3(1.0), glint * 0.7);
    return half4(half3(rgb), 1.0h) * color.a;
}
