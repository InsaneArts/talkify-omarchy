#version 440

// Talkify's Chart Line (ChartLineWaveView), the default voice visual: a
// smoothed line through the last 56 levels gliding left like a conveyor, with
// its whole treatment drawn in one pass — an ambient pool of light beneath
// it, a glass-floor reflection, a wide halo and a tight bloom that breathe
// with the voice, a crisp white-hot core, and a specular band sweeping along.
//
// SwiftUI stroked the path five times and blurred four of the copies. Here
// each layer is the same stroke seen through its own blur: the distance to the
// curve goes through the profile a Gaussian-blurred stroke of that width
// would have, which is exact for a straight run and close on the bends.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 viewSize;
  // How far the conveyor has moved toward the next slot, 0..1.
  float scroll;
  float level;
  float time;
  float micAlive;
  // What the line turns when it stops (micAlive 0), straight alpha: amber
  // for a dead microphone, the muted colour for a paused session.
  vec4 stillColor;
  // Lifts the rest line toward the shape's visual center (negative is up).
  float restOffset;
  float dpr;
  // SwiftUI's blur radius to a Gaussian sigma.
  float blurScale;
  // The treatment's colours, straight alpha: the ends of the gradient, its
  // middle, and the bright core. Talkify's are a cool silver around white;
  // a theme tints the ends and keeps the core bright.
  vec4 lineEdge;
  vec4 lineMid;
  vec4 coreColor;
  vec4 s0; vec4 s1; vec4 s2; vec4 s3; vec4 s4; vec4 s5; vec4 s6;
  vec4 s7; vec4 s8; vec4 s9; vec4 s10; vec4 s11; vec4 s12; vec4 s13;
};

const int COUNT = 56;

vec4 samples[14];
float span;
float restY;
float lift;
float slot;

float erfApprox(float x) {
  float x2 = x * x;
  float a = 0.147;
  float t = sqrt(1.0 - exp(-x2 * (1.2732395 + a * x2) / (1.0 + a * x2)));
  return x < 0.0 ? -t : t;
}

float phi(float x) {
  return 0.5 + 0.5 * erfApprox(x * 0.70710678);
}

// How much of a stroke `width` wide, blurred by `sigma`, lands at `distance`
// from its centerline.
float stroke(float distance, float width, float sigma) {
  sigma = max(sigma, 0.45 / dpr);
  return phi((distance + width * 0.5) / sigma) - phi((distance - width * 0.5) / sigma);
}

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

float pointY(int i) {
  return restY - max(lift, sampleAt(i) * span);
}

// The path SmoothLineShape builds — a straight lead-in, quadratic curves
// through the midpoints with each sample as the control, a straight lead-out —
// written as y(x). With evenly spaced samples every curve is quadratic in x.
float curveY(float x) {
  float u = x / slot + scroll;
  float lastIndex = float(COUNT - 1);
  if (u <= 0.5) {
    float first = pointY(0);
    return mix(first, 0.5 * (first + pointY(1)), clamp(u / 0.5, 0.0, 1.0));
  }
  if (u >= lastIndex - 0.5) {
    float last = pointY(COUNT - 1);
    return mix(0.5 * (pointY(COUNT - 2) + last), last, clamp((u - lastIndex + 0.5) / 0.5, 0.0, 1.0));
  }
  float j = floor(u + 0.5);
  int index = int(j);
  float t = u - (j - 0.5);
  float previous = pointY(index - 1);
  float control = pointY(index);
  float next = pointY(index + 1);
  float from = 0.5 * (previous + control);
  float to = 0.5 * (control + next);
  float rest = 1.0 - t;
  return rest * rest * from + 2.0 * t * rest * control + t * t * to;
}

// Distance from `z` to the curve: a scan across the reach that could still
// matter, then a few halvings around the nearest sample.
float curveDistance(vec2 z, float reach) {
  float vertical = abs(curveY(z.x) - z.y);
  float best = vertical * vertical;
  float bestX = z.x;
  float range = min(vertical, reach);
  if (range > 0.25) {
    float h = range / 8.0;
    for (int k = -8; k <= 8; k++) {
      if (k == 0) continue;
      float x = z.x + float(k) * h;
      float dy = curveY(x) - z.y;
      float dx = x - z.x;
      float d2 = dx * dx + dy * dy;
      if (d2 < best) {
        best = d2;
        bestX = x;
      }
    }
    for (int i = 0; i < 3; i++) {
      h *= 0.5;
      float center = bestX;
      for (int side = -1; side <= 1; side += 2) {
        float x = center + float(side) * h;
        float dy = curveY(x) - z.y;
        float dx = x - z.x;
        float d2 = dx * dx + dy * dy;
        if (d2 < best) {
          best = d2;
          bestX = x;
        }
      }
    }
  }
  return sqrt(best);
}

// The treatment's gradient, left to right: the core colour in the body
// cooling into the edge colour at the ends. Premultiplied.
vec4 silver(float u) {
  u = clamp(u, 0.0, 1.0);
  vec4 c;
  if (u < 0.25) c = mix(lineEdge, coreColor, u / 0.25);
  else if (u < 0.5) c = mix(coreColor, lineMid, (u - 0.25) / 0.25);
  else if (u < 0.75) c = mix(lineMid, coreColor, (u - 0.5) / 0.25);
  else c = mix(coreColor, lineEdge, (u - 0.75) / 0.25);
  return vec4(c.rgb * c.a, c.a);
}

vec4 core(float a) {
  return vec4(coreColor.rgb, 1.0) * a;
}

vec4 over(vec4 top, vec4 bottom) {
  return top + bottom * (1.0 - top.a);
}

void main() {
  samples[0] = s0; samples[1] = s1; samples[2] = s2; samples[3] = s3;
  samples[4] = s4; samples[5] = s5; samples[6] = s6; samples[7] = s7;
  samples[8] = s8; samples[9] = s9; samples[10] = s10; samples[11] = s11;
  samples[12] = s12; samples[13] = s13;

  vec2 p = qt_TexCoord0 * viewSize;
  // The whole stack is drawn lifted by restOffset and clipped to the band.
  vec2 z = vec2(p.x, p.y - restOffset);

  span = viewSize.y * 0.5;
  restY = span;
  // Concert's 0.75pt floor, scaled with the span so a short band does not
  // clamp quiet speech to a straight line.
  lift = min(0.75, span * 0.025);
  slot = viewSize.x / float(COUNT - 2);

  if (micAlive < 0.5) {
    // A dead microphone or a paused session: one plain line, motionless.
    float d = curveDistance(z, 3.0);
    vec4 still = vec4(stillColor.rgb * stillColor.a, stillColor.a);
    fragColor = still * stroke(d, 2.0, 0.0) * qt_Opacity;
    return;
  }

  float u = p.x / max(viewSize.x, 1.0);
  vec4 color = vec4(0.0);

  // Ambient under-glow: a wide soft pool of light beneath the line,
  // breathing with the voice. An ellipse 26 tall, inset 60 each side,
  // blurred 22.
  {
    float sigma = 22.0 * blurScale;
    float a = max((viewSize.x - 120.0) * 0.5, 1.0);
    vec2 c = vec2(viewSize.x * 0.5, viewSize.y * 0.5);
    float pool = 0.0;
    // Five taps across the blur stand in for its horizontal spread; the
    // vertical one is exact for the ellipse's height at each tap.
    for (int k = -2; k <= 2; k++) {
      float x = z.x + float(k) * sigma * 0.6;
      float dx = (x - c.x) / a;
      float halfHeight = 13.0 * sqrt(max(0.0, 1.0 - dx * dx));
      float dy = z.y - c.y;
      float weight = exp(-0.5 * float(k * k) * 0.36);
      pool += weight * (phi((halfHeight - dy) / sigma) - phi((-halfHeight - dy) / sigma));
    }
    pool /= 1.0 + 2.0 * exp(-0.18) + 2.0 * exp(-0.72);
    float ellipseU = (z.x - 60.0) / max(viewSize.x - 120.0, 1.0);
    color = over(silver(ellipseU) * pool * (0.08 + 0.22 * level), color);
  }

  // Glass-floor reflection: the wave mirrored about its rest line, soft and
  // fading away from it.
  {
    float sigma = 2.5 * blurScale;
    vec2 mirrored = vec2(z.x, 2.0 * restY - z.y);
    float d = curveDistance(mirrored, 1.1 + 3.0 * sigma);
    float fade = 0.8 * (1.0 - abs(z.y - viewSize.y * 0.5) / max(viewSize.y * 0.5, 1.0));
    float a = stroke(d, 2.2, sigma) * (0.16 + 0.22 * level) * max(fade, 0.0);
    color = over(silver(u) * a, color);
  }

  float haloWidth = 4.0 + 8.0 * level;
  float haloSigma = 9.0 * blurScale;
  float d = curveDistance(z, haloWidth * 0.5 + 3.0 * haloSigma);

  // Wide halo: cool silver, so the bloom reads as light on glass.
  color = over(silver(u) * stroke(d, haloWidth, haloSigma) * (0.2 + 0.6 * level), color);
  // Tight bloom hugging the core.
  color = over(silver(u) * stroke(d, 2.5 + 3.0 * level, 2.5 * blurScale) * 0.8, color);
  // The crisp core, never blurred.
  color = over(core(stroke(d, 1.7, 0.0) * (0.75 + 0.25 * level)), color);

  // Metallic specular: a soft band of extra light ping-ponging along the line.
  {
    float phase = mod(time / 3.2, 2.0);
    float linear = phase < 1.0 ? phase : 2.0 - phase;
    float eased = linear * linear * (3.0 - 2.0 * linear);
    float bandWidth = viewSize.x * 0.3;
    float start = eased * (viewSize.x + bandWidth) - bandWidth;
    float t = (p.x - start) / max(bandWidth, 1.0);
    float band = (t > 0.0 && t < 1.0) ? 1.0 - abs(t * 2.0 - 1.0) : 0.0;
    color = over(core(stroke(d, 2.6, 0.8 * blurScale) * band), color);
  }

  // The band clips the stack, as Talkify's clipped() does; a few pixels of
  // feather keep the cut from reading as a seam inside the black.
  float feather = smoothstep(0.0, 3.0, p.y) * smoothstep(0.0, 3.0, viewSize.y - p.y);
  fragColor = clamp(color, 0.0, 1.0) * feather * qt_Opacity;
}
