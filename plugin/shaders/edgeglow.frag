#version 440

// Edge Glow (HUDEdgeGlowView and EdgeGlow.metal): the shape's open silhouette
// — down the left flank, across the bottom, up the right flank, never the top
// edge, which is the screen's — stroked with the palette's angular gradient
// three times (a crisp line and two blurred copies, the gist's GlowModifier),
// then masked by distance from an origin sweeping along that silhouette.
//
// SwiftUI built the picture from strokes and blurs and only the mask was a
// shader. Here the strokes are distance profiles, so the whole beam is one
// pass, and the mask is EdgeGlow.metal's function unchanged.
//
// The same beam can also trace a closed rounded rectangle (a window's halo, a
// pill's ring). A window-sized glow is drawn as four strips along its edges
// rather than one quad over the whole window, so each strip says where it
// sits inside the full glow (`viewOrigin`, `fullSize`).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 viewSize;
  // Where this item sits inside the whole glow, and the whole glow's size.
  vec2 viewOrigin;
  vec2 fullSize;
  // The silhouette inside the whole glow: left, right, bottom, corner radius.
  vec4 silhouette;
  // 0 traces the open silhouette hanging from the screen edge; 1 a closed
  // rounded rectangle whose top is `silhouetteTop`.
  float closedPath;
  float silhouetteTop;
  // Turns the palette around the center, in turns.
  float angleOffset;
  // Scales the origin mask's reach: 1 is Talkify's; below 1 a large frame
  // keeps light along its far edges.
  float maskScale;
  float topRadius;
  float lineWidth;
  float blurRadius;
  float blurScale;
  vec2 origin;
  // Voice-driven brightness; the gist used a constant 3.
  float amplitude;
  // The session ramp, 0..1.
  float progress;
  float micAlive;
  // The beam's colour when it stops (micAlive 0), straight alpha: amber for
  // a dead microphone, the muted colour for a paused session.
  vec4 stillColor;
  float stopCount;
  vec4 c0; vec4 c1; vec4 c2; vec4 c3; vec4 c4; vec4 c5; vec4 c6;
  // Stop locations, four per vector.
  vec4 l0; vec4 l1;
  float dpr;
};

const float PI = 3.14159265;

float erfApprox(float x) {
  float x2 = x * x;
  float a = 0.147;
  float t = sqrt(1.0 - exp(-x2 * (1.2732395 + a * x2) / (1.0 + a * x2)));
  return x < 0.0 ? -t : t;
}

float phi(float x) {
  return 0.5 + 0.5 * erfApprox(x * 0.70710678);
}

float stroke(float distance, float width, float sigma) {
  sigma = max(sigma, 0.45 / dpr);
  return phi((distance + width * 0.5) / sigma) - phi((distance - width * 0.5) / sigma);
}

float segment(vec2 p, vec2 a, vec2 b) {
  vec2 ab = b - a;
  float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
  return length(p - (a + ab * t));
}

// Distance to a quarter arc in the quadrant `signs` points into; outside that
// quadrant the neighboring pieces own the nearest point.
float quarter(vec2 p, vec2 center, float radius, vec2 signs) {
  if (radius <= 0.0) return 1e4;
  vec2 d = (p - center) * signs;
  if (d.x < 0.0 || d.y < 0.0) return 1e4;
  return abs(length(p - center) - radius);
}

float closedDistance(vec2 p) {
  vec2 lo = vec2(silhouette.x, silhouetteTop);
  vec2 hi = vec2(silhouette.y, silhouette.z);
  float radius = min(silhouette.w, min(hi.x - lo.x, hi.y - lo.y) * 0.5);
  vec2 q = abs(p - (lo + hi) * 0.5) - (hi - lo) * 0.5 + radius;
  return abs(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius);
}

float silhouetteDistance(vec2 p) {
  if (closedPath > 0.5) return closedDistance(p);
  float left = silhouette.x;
  float right = silhouette.y;
  float bottom = silhouette.z;
  float radius = min(silhouette.w, max(0.0, bottom * 0.5));
  float top = min(topRadius, max(0.0, bottom * 0.5));

  float d = segment(p, vec2(left, top), vec2(left, bottom - radius));
  d = min(d, segment(p, vec2(left + radius, bottom), vec2(right - radius, bottom)));
  d = min(d, segment(p, vec2(right, top), vec2(right, bottom - radius)));
  d = min(d, quarter(p, vec2(left + radius, bottom - radius), radius, vec2(-1.0, 1.0)));
  d = min(d, quarter(p, vec2(right - radius, bottom - radius), radius, vec2(1.0, 1.0)));
  // The fillets curl the flanks out along the screen edge.
  d = min(d, quarter(p, vec2(left - top, top), top, vec2(1.0, -1.0)));
  d = min(d, quarter(p, vec2(right + top, top), top, vec2(-1.0, -1.0)));
  // Round caps where the path meets the screen edge.
  d = min(d, length(p - vec2(left - top, 0.0)));
  d = min(d, length(p - vec2(right + top, 0.0)));
  return d;
}

vec4 stopColor(int i) {
  if (i == 0) return c0;
  if (i == 1) return c1;
  if (i == 2) return c2;
  if (i == 3) return c3;
  if (i == 4) return c4;
  if (i == 5) return c5;
  return c6;
}

float stopLocation(int i) {
  if (i == 0) return l0.x;
  if (i == 1) return l0.y;
  if (i == 2) return l0.z;
  if (i == 3) return l0.w;
  if (i == 4) return l1.x;
  if (i == 5) return l1.y;
  return l1.z;
}

// SwiftUI's angular gradient: angle zero points right, turning clockwise on
// screen, centered on the view.
vec4 palette(vec2 p) {
  if (micAlive < 0.5) return stillColor;
  vec2 d = p - fullSize * 0.5;
  float angle = atan(d.y, d.x);
  if (angle < 0.0) angle += 2.0 * PI;
  float u = fract(angle / (2.0 * PI) + angleOffset);
  int count = int(stopCount + 0.5);
  vec4 color = stopColor(0);
  for (int i = 1; i < 7; i++) {
    if (i >= count) break;
    float from = stopLocation(i - 1);
    float to = stopLocation(i);
    if (u >= from && u <= to) {
      color = mix(stopColor(i - 1), stopColor(i), (u - from) / max(to - from, 1e-5));
    }
  }
  return color;
}

vec4 over(vec4 top, vec4 bottom) {
  return top + bottom * (1.0 - top.a);
}

void main() {
  vec2 p = viewOrigin + qt_TexCoord0 * viewSize;
  float d = silhouetteDistance(p);

  vec4 tint = palette(p);
  tint = vec4(tint.rgb * tint.a, tint.a);

  float sigma = blurRadius * blurScale;
  vec4 color = tint * stroke(d, lineWidth * 0.5, 0.0);
  color = over(tint * stroke(d, lineWidth, sigma), color);
  color = over(tint * stroke(d, lineWidth, sigma * 0.5), color);

  // EdgeGlow.metal: intensity falls off with normalized distance from the
  // origin, spreads outward as the ramp grows, and scales with the voice.
  vec2 uvPosition = p / fullSize;
  vec2 uvOrigin = origin / fullSize;
  float distance = length(uvPosition - uvOrigin) * maskScale;
  float intensity = smoothstep(0.0, 1.0, progress)
    * exp(-distance * distance)
    * amplitude;
  intensity *= smoothstep(0.0, 1.0, 1.0 - distance / max(progress, 1e-3));

  fragColor = clamp(color * intensity, 0.0, 1.0) * qt_Opacity;
}
