#version 440

// The Edge Glow particle cloud's drawing half (ParticleCloud.metal's
// drawParticles). The simulation half — respawn, drift toward the sweeping
// origin, a hundred-frame life — runs in ParticleCloud.qml, because a fragment
// shader keeps no state between frames and 32 motes are nothing to move on the
// CPU. Each mote arrives here as x, y, radius, alpha.
//
// The kernel wrote every mote's pixels straight into the drawable, so where
// two overlap the later one wins rather than blending; that is kept. The
// whole cloud is clipped to the body, as Talkify clips it to the housing.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 viewSize;
  float cornerRadius;
  float dpr;
  vec4 color0; vec4 color1; vec4 color2;
  vec4 p0; vec4 p1; vec4 p2; vec4 p3; vec4 p4; vec4 p5; vec4 p6; vec4 p7;
  vec4 p8; vec4 p9; vec4 p10; vec4 p11; vec4 p12; vec4 p13; vec4 p14; vec4 p15;
  vec4 p16; vec4 p17; vec4 p18; vec4 p19; vec4 p20; vec4 p21; vec4 p22; vec4 p23;
  vec4 p24; vec4 p25; vec4 p26; vec4 p27; vec4 p28; vec4 p29; vec4 p30; vec4 p31;
};

vec4 motes[32];

float bodyCoverage(vec2 p) {
  float radius = min(cornerRadius, min(viewSize.x, viewSize.y) * 0.5);
  vec2 halfSize = vec2(viewSize.x * 0.5, 10000.0);
  vec2 center = vec2(viewSize.x * 0.5, viewSize.y - 10000.0);
  vec2 q = abs(p - center) - halfSize + radius;
  float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
  return clamp(0.5 - d * dpr, 0.0, 1.0);
}

void main() {
  motes[0] = p0; motes[1] = p1; motes[2] = p2; motes[3] = p3;
  motes[4] = p4; motes[5] = p5; motes[6] = p6; motes[7] = p7;
  motes[8] = p8; motes[9] = p9; motes[10] = p10; motes[11] = p11;
  motes[12] = p12; motes[13] = p13; motes[14] = p14; motes[15] = p15;
  motes[16] = p16; motes[17] = p17; motes[18] = p18; motes[19] = p19;
  motes[20] = p20; motes[21] = p21; motes[22] = p22; motes[23] = p23;
  motes[24] = p24; motes[25] = p25; motes[26] = p26; motes[27] = p27;
  motes[28] = p28; motes[29] = p29; motes[30] = p30; motes[31] = p31;

  vec2 p = qt_TexCoord0 * viewSize;
  vec4 color = vec4(0.0);
  for (int i = 0; i < 32; i++) {
    vec4 mote = motes[i];
    if (mote.w <= 0.0) continue;
    float d = length(p - mote.xy) - mote.z;
    float c = clamp(0.5 - d * dpr, 0.0, 1.0);
    if (c <= 0.0) continue;
    int slot = i - (i / 3) * 3;
    vec3 rgb = slot == 0 ? color0.rgb : (slot == 1 ? color1.rgb : color2.rgb);
    color = mix(color, vec4(rgb * mote.w, mote.w), c);
  }
  fragColor = color * bodyCoverage(p) * qt_Opacity;
}
