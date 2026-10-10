#version 440

// The HUD's black shape (HUDSurface's housing): a rectangle flush with the
// screen's top edge whose bottom corners round continuously, a soft drop
// shadow, the concave fillets that flare it into the screen edge, and the
// one-shot ripple (Ripple.metal) that rolls across it when an Edge Glow
// session starts.
//
// Drawn as a distance field rather than tessellated, so the shape stays crisp
// while its height springs and costs nothing to resize. Two instances share
// this source: one under the content (shadow and body), one over the overlays
// (fillets only), because Talkify stacks its fillets above the glow.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 viewSize;
  // The body in this item's coordinates: x, y, width, height.
  vec4 shapeRect;
  float cornerRadius;
  float fillet;
  // 0 draws the shadow and the body; 1 draws only the fillets.
  float layerMode;
  float shadowAlpha;
  float shadowSigma;
  float shadowOffset;
  vec4 fillColor;
  // A hairline along the open silhouette, premultiplied; alpha 0 disables it.
  vec4 edgeColor;
  float edgeWidth;
  vec2 rippleOrigin;
  // Seconds into the ripple, or below zero when it is not playing.
  float rippleTime;
  // What the wave lights the body toward: white for Talkify, the accent for
  // a theme.
  vec4 rippleTint;
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

// SwiftUI's .continuous corner is a smoother curve than a circular arc: it
// starts earlier along each edge and eases into the turn. A superellipse
// with a longer reach and a matching diagonal inset stands in for it.
float cornerLength(vec2 q, float n) {
  q = max(q, vec2(0.0));
  return pow(pow(q.x, n) + pow(q.y, n), 1.0 / n);
}

// Signed distance to the body: open at the top (it runs off past the screen
// edge), straight flanks, continuous bottom corners.
float bodyDistance(vec2 p) {
  float left = shapeRect.x;
  float right = shapeRect.x + shapeRect.z;
  float bottom = shapeRect.y + shapeRect.w;
  float reach = min(cornerRadius * 1.528, min(shapeRect.z, max(shapeRect.w, 0.0)) * 0.5);
  vec2 halfSize = vec2((right - left) * 0.5, 10000.0);
  vec2 center = vec2((left + right) * 0.5, bottom - 10000.0);
  vec2 q = abs(p - center) - halfSize + reach;
  return cornerLength(q, 3.25) + min(max(q.x, q.y), 0.0) - reach;
}

float boxDistance(vec2 p, vec2 lo, vec2 hi) {
  vec2 center = (lo + hi) * 0.5;
  vec2 q = abs(p - center) - (hi - lo) * 0.5;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// A square beside the flank with a quarter disc taken out of its outer bottom
// corner (NotchFilletShape). The square reaches back into the body and up past
// the screen edge so the union has no seam and no edge along the top.
float filletDistance(vec2 p) {
  if (fillet <= 0.0) return 1e4;
  float top = shapeRect.y;
  float left = shapeRect.x;
  float right = shapeRect.x + shapeRect.z;
  float leading = max(
    boxDistance(p, vec2(left - fillet, top - fillet), vec2(left + fillet, top + fillet)),
    fillet - length(p - vec2(left - fillet, top + fillet)));
  float trailing = max(
    boxDistance(p, vec2(right - fillet, top - fillet), vec2(right + fillet, top + fillet)),
    fillet - length(p - vec2(right + fillet, top + fillet)));
  return min(leading, trailing);
}

float coverage(float distance) {
  return clamp(0.5 - distance * dpr, 0.0, 1.0);
}

vec4 over(vec4 top, vec4 bottom) {
  return top + bottom * (1.0 - top.a);
}

void main() {
  vec2 p = qt_TexCoord0 * viewSize;

  if (layerMode > 0.5) {
    float d = filletDistance(p);
    // The flare only exists outside the body's flanks; inside, the body's own
    // layer already drew it, with the ripple.
    float outside = step(p.x, shapeRect.x) + step(shapeRect.x + shapeRect.z, p.x);
    vec4 color = fillColor * coverage(d) * min(outside, 1.0);
    if (edgeColor.a > 0.0) {
      float edge = coverage(d) * (1.0 - coverage(d + edgeWidth));
      color = over(edgeColor * edge * min(outside, 1.0), color);
    }
    fragColor = color * qt_Opacity;
    return;
  }

  // The shadow stays still under the ripple: it belongs outside the effect.
  float left = shapeRect.x;
  float right = shapeRect.x + shapeRect.z;
  float bottom = shapeRect.y + shapeRect.w + shadowOffset;
  float sigma = max(shadowSigma, 0.001);
  float spread = (phi((p.x - left) / sigma) - phi((p.x - right) / sigma))
    * phi((bottom - p.y) / sigma);
  vec4 shadow = vec4(0.0, 0.0, 0.0, shadowAlpha * spread);

  // The ripple displaces the body's pixels along the line from its origin and
  // lightens them by how far the wave has them: one light wave rolling out
  // from under the housing, once.
  vec2 sampleAt = p;
  float lighten = 0.0;
  if (rippleTime >= 0.0) {
    float amplitude = 3.0;
    float frequency = 6.0;
    float decay = 6.0;
    float speed = 1200.0;
    vec2 away = p - rippleOrigin;
    float distance = length(away);
    float t = max(0.0, rippleTime - distance / speed);
    float amount = amplitude * sin(frequency * t) * exp(-decay * t);
    vec2 direction = distance > 0.0001 ? away / distance : vec2(0.0);
    sampleAt = p + amount * direction;
    lighten = amount / amplitude;
  }

  float body = coverage(bodyDistance(sampleAt));
  vec4 color = fillColor * body;
  // On Talkify's black this is exactly Ripple.metal's lightening; on a
  // theme's fill it lights toward the tint instead of washing to grey.
  color.rgb = mix(color.rgb, rippleTint.rgb * color.a, clamp(lighten, 0.0, 1.0));
  color.rgb = min(color.rgb, vec3(color.a));

  if (edgeColor.a > 0.0) {
    // Inside the silhouette, so the hairline never reads as a border floating
    // off the shape.
    float d = min(bodyDistance(p), filletDistance(p));
    float edge = coverage(d) * (1.0 - coverage(d + edgeWidth));
    color = over(edgeColor * edge * body, color);
  }

  fragColor = over(color, shadow) * qt_Opacity;
}
