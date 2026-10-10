#version 440

// The black body of the floating HUD shapes (the bottom pill, the window
// caption, the pointer's label): a rounded rectangle with a soft drop shadow
// and the theme hairline, the same treatment the notch's housing gets, minus
// the screen edge it hangs from. A distance field, so the shape stays crisp
// while its width and height spring.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec2 viewSize;
  // The body inside this item: x, y, width, height.
  vec4 boxRect;
  float radius;
  vec4 fillColor;
  // Premultiplied; alpha 0 leaves the plain black edge.
  vec4 edgeColor;
  float edgeWidth;
  float shadowAlpha;
  float shadowSigma;
  float shadowOffset;
  float dpr;
};

float erfApprox(float x) {
  float x2 = x * x;
  float a = 0.147;
  float t = sqrt(1.0 - exp(-x2 * (1.2732395 + a * x2) / (1.0 + a * x2)));
  return x < 0.0 ? -t : t;
}

float phi(float x) {
  return 0.5 + 0.5 * erfApprox(x * 0.70710678);
}

float boxDistance(vec2 p) {
  vec2 halfSize = boxRect.zw * 0.5;
  float r = min(radius, min(halfSize.x, halfSize.y));
  vec2 q = abs(p - (boxRect.xy + halfSize)) - halfSize + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float coverage(float distance) {
  return clamp(0.5 - distance * dpr, 0.0, 1.0);
}

vec4 over(vec4 top, vec4 bottom) {
  return top + bottom * (1.0 - top.a);
}

void main() {
  vec2 p = qt_TexCoord0 * viewSize;

  // A box blurred by a Gaussian is the product of two blurred edges: exact
  // for the sides, close enough at the rounded corners.
  float sigma = max(shadowSigma, 0.001);
  vec2 lo = boxRect.xy + vec2(0.0, shadowOffset);
  vec2 hi = lo + boxRect.zw;
  float spread = (phi((p.x - lo.x) / sigma) - phi((p.x - hi.x) / sigma))
    * (phi((p.y - lo.y) / sigma) - phi((p.y - hi.y) / sigma));
  vec4 shadow = vec4(0.0, 0.0, 0.0, shadowAlpha * spread);

  float d = boxDistance(p);
  float body = coverage(d);
  vec4 color = fillColor * body;
  if (edgeColor.a > 0.0) {
    float edge = body * (1.0 - coverage(d + edgeWidth));
    color = over(edgeColor * edge, color);
  }
  fragColor = over(color, shadow) * qt_Opacity;
}
