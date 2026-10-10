#version 440

// The waveform's bar-family styles (HUDWaveformView, WaveShapes) and the
// finish laid over them (WaveformSheen.metal): chromatic fringing that grows
// toward the edges and with the voice, a cheap four-tap bloom, and a metallic
// specular band ping-ponging across.
//
// SwiftUI drew the shape and then sampled its pixels from a layer effect. The
// shapes here are distance fields, so the sheen evaluates the shape at each
// offset it needs instead of sampling a texture — same taps, no layer.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 viewSize;
  // Room around the drawn shape for the sheen's offset taps.
  float margin;
  // 0 article, 1 silver, 2 capsules, 3 dots, 4 curve, 5 filled, 6 chart area.
  float style;
  float level;
  float time;
  float micAlive;
  // What the fill turns when it stops (micAlive 0), straight alpha: amber
  // for a dead microphone, the muted colour for a paused session.
  vec4 stillColor;
  float dpr;
  // The fill's colours, straight alpha: the cool ends and the bright body.
  vec4 waveEdge;
  vec4 coreColor;
  vec4 s0; vec4 s1; vec4 s2; vec4 s3; vec4 s4; vec4 s5; vec4 s6;
  vec4 s7; vec4 s8; vec4 s9; vec4 s10; vec4 s11; vec4 s12; vec4 s13;
};

const int COUNT = 56;

vec4 samples[14];
vec2 rectSize;
int kind;

// Written without bit operations or dynamic component indexing, so the
// GLSL ES 1.00 variant the GL backend may pick still compiles.
float sampleAt(int i) {
  if (i < 0) i = 0;
  if (i > COUNT - 1) i = COUNT - 1;
  int slot = i / 4;
  int lane = i - slot * 4;
  vec4 four = samples[slot];
  if (lane == 0) return four.x;
  if (lane == 1) return four.y;
  if (lane == 2) return four.z;
  return four.w;
}

float coverage(float distance) {
  return clamp(0.5 - distance * dpr, 0.0, 1.0);
}

float roundedBox(vec2 p, vec2 center, vec2 halfSize, float radius) {
  vec2 q = abs(p - center) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// One color language for every style: the edge glow's silver, a hot white
// body cooling at the extremes into a faint blue-violet, top to bottom across
// `u`. The still colour when the microphone dies or the session pauses.
// Premultiplied.
vec4 silver(float u) {
  if (micAlive < 0.5) return vec4(stillColor.rgb * stillColor.a, stillColor.a);
  vec4 c = mix(waveEdge, coreColor, 1.0 - abs(clamp(u, 0.0, 1.0) * 2.0 - 1.0));
  return vec4(c.rgb * c.a, c.a);
}

// Bars: Article's square ones (linear heights, 2 apart) and Silver's rounded
// ones (square-root heights, 3 apart).
float barCoverage(vec2 p, float spacing, bool rounded, bool perceptual) {
  float barWidth = max(1.0, (rectSize.x - spacing * float(COUNT - 1)) / float(COUNT));
  float pitch = barWidth + spacing;
  int nearest = int(floor(p.x / pitch));
  float best = 1e4;
  for (int k = -1; k <= 1; k++) {
    int i = nearest + k;
    if (i < 0 || i >= COUNT) continue;
    float value = sampleAt(i);
    float scaled = perceptual ? sqrt(max(value, 0.0)) : value;
    float height = max(2.0, scaled * rectSize.y);
    vec2 center = vec2(float(i) * pitch + barWidth * 0.5, rectSize.y * 0.5);
    float radius = rounded ? min(barWidth * 0.5, height * 0.5) : 0.0;
    best = min(best, roundedBox(p, center, vec2(barWidth, height) * 0.5, radius));
  }
  return coverage(best);
}

// Capsules: width from the slot, dampened heights, each capsule carrying its
// own gradient.
vec4 capsules(vec2 p) {
  float step = rectSize.x / float(COUNT);
  float barWidth = max(step * 0.55, 1.0);
  float origin = (step - barWidth) * 0.5;
  int nearest = int(floor((p.x - origin) / step));
  vec4 color = vec4(0.0);
  for (int k = -1; k <= 1; k++) {
    int i = nearest + k;
    if (i < 0 || i >= COUNT) continue;
    float height = max(barWidth, sampleAt(i) * 0.75 * rectSize.y);
    vec2 center = vec2(origin + float(i) * step + barWidth * 0.5, rectSize.y * 0.5);
    float c = coverage(roundedBox(p, center, vec2(barWidth, height) * 0.5, barWidth * 0.5));
    if (c > 0.0) {
      float u = (p.y - (center.y - height * 0.5)) / height;
      color = max(color, silver(u) * c);
    }
  }
  return color;
}

// WaveformScrubber's dots: a mirrored pair per sample.
float dots(vec2 p) {
  float spacing = rectSize.x / float(COUNT);
  int nearest = int(floor(p.x / spacing + 0.5));
  float best = 1e4;
  for (int k = -1; k <= 1; k++) {
    int i = nearest + k;
    if (i < 0 || i >= COUNT) continue;
    float extent = sampleAt(i) * rectSize.y * 0.5;
    float x = float(i) * spacing;
    float y = abs(p.y - rectSize.y * 0.5);
    best = min(best, length(vec2(p.x - x, y - extent)) - 1.6);
  }
  return coverage(best);
}

// Half-heights through midpoint quadratic curves, as y(x), for Curve.
float smoothHalf(float x) {
  float step = rectSize.x / float(COUNT - 1);
  float u = x / step;
  float lastIndex = float(COUNT - 1);
  if (u <= 0.5) {
    float first = max(1.0, sampleAt(0) * rectSize.y * 0.5);
    float second = max(1.0, sampleAt(1) * rectSize.y * 0.5);
    return mix(first, 0.5 * (first + second), clamp(u / 0.5, 0.0, 1.0));
  }
  if (u >= lastIndex - 0.5) {
    float last = max(1.0, sampleAt(COUNT - 1) * rectSize.y * 0.5);
    float before = max(1.0, sampleAt(COUNT - 2) * rectSize.y * 0.5);
    return mix(0.5 * (before + last), last, clamp((u - lastIndex + 0.5) / 0.5, 0.0, 1.0));
  }
  float j = floor(u + 0.5);
  int index = int(j);
  float t = u - (j - 0.5);
  float previous = max(1.0, sampleAt(index - 1) * rectSize.y * 0.5);
  float control = max(1.0, sampleAt(index) * rectSize.y * 0.5);
  float next = max(1.0, sampleAt(index + 1) * rectSize.y * 0.5);
  float from = 0.5 * (previous + control);
  float to = 0.5 * (control + next);
  float rest = 1.0 - t;
  return rest * rest * from + 2.0 * t * rest * control + t * t * to;
}

// AudioKit's min/max region: straight segments between samples.
float linearHalf(float x) {
  float step = rectSize.x / float(COUNT - 1);
  float u = clamp(x / step, 0.0, float(COUNT - 1));
  int i = int(floor(u));
  float a = max(0.75, sampleAt(i) * rectSize.y * 0.5);
  float b = max(0.75, sampleAt(i + 1) * rectSize.y * 0.5);
  return mix(a, b, u - float(i));
}

// Swift Charts' catmull-rom area, filled from the line down to the baseline.
float areaTop(float x) {
  float step = rectSize.x / float(COUNT - 1);
  float u = clamp(x / step, 0.0, float(COUNT - 1));
  int i = int(floor(u));
  float t = u - float(i);
  float p0 = sampleAt(i - 1);
  float p1 = sampleAt(i);
  float p2 = sampleAt(i + 1);
  float p3 = sampleAt(i + 2);
  float v = 0.5 * ((2.0 * p1) + (-p0 + p2) * t
    + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
    + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t);
  return rectSize.y * (1.0 - clamp(v, 0.0, 1.0));
}

vec4 shapeAt(vec2 p) {
  if (p.x < -2.0 || p.x > rectSize.x + 2.0) return vec4(0.0);
  float u = p.y / rectSize.y;
  if (kind == 2) return capsules(p);
  float c = 0.0;
  if (kind == 0) c = barCoverage(p, 2.0, false, false);
  else if (kind == 1) c = barCoverage(p, 3.0, true, true);
  else if (kind == 3) c = dots(p);
  else if (kind == 4) c = coverage(abs(p.y - rectSize.y * 0.5) - smoothHalf(p.x));
  else if (kind == 5) c = coverage(abs(p.y - rectSize.y * 0.5) - linearHalf(p.x));
  else c = coverage(areaTop(p.x) - p.y) * step(p.y, rectSize.y);
  return silver(u) * c;
}

void main() {
  samples[0] = s0; samples[1] = s1; samples[2] = s2; samples[3] = s3;
  samples[4] = s4; samples[5] = s5; samples[6] = s6; samples[7] = s7;
  samples[8] = s8; samples[9] = s9; samples[10] = s10; samples[11] = s11;
  samples[12] = s12; samples[13] = s13;

  rectSize = viewSize - vec2(margin * 2.0);
  kind = int(style + 0.5);
  vec2 p = qt_TexCoord0 * viewSize - vec2(margin);

  // Fringe grows from the horizontal center outward and with the voice.
  float centered = (p.x / max(rectSize.x, 1.0)) * 2.0 - 1.0;
  float aberration = (1.0 + 2.2 * level) * centered;

  vec4 base = shapeAt(p);
  float r = shapeAt(p + vec2(aberration, 0.0)).r;
  float b = shapeAt(p - vec2(aberration, 0.0)).b;
  vec4 color = vec4(r, base.g, b, base.a);

  // Bloom: four taps folded in, so bright bars halo softly.
  vec4 spread = shapeAt(p + vec2(3.0, 0.0)) + shapeAt(p - vec2(3.0, 0.0))
    + shapeAt(p + vec2(0.0, 3.0)) + shapeAt(p - vec2(0.0, 3.0));
  color += spread * (0.12 + 0.10 * level);

  // Metallic sweep: a soft specular band ping-ponging across the strip.
  float phase = mod(time / 2.8, 2.0);
  float linear = phase < 1.0 ? phase : 2.0 - phase;
  float sweep = linear * linear * (3.0 - 2.0 * linear);
  float x = p.x / max(rectSize.x, 1.0);
  float band = exp(-pow((x - sweep) * 7.0, 2.0));
  color.rgb *= 1.0 + (0.55 + 0.45 * level) * band;

  // Fringe taps can leave color where the base has no coverage. That is kept
  // as Metal kept it: with premultiplied blending it adds light over the black
  // shape rather than covering anything.
  fragColor = min(color, vec4(1.0)) * qt_Opacity;
}
