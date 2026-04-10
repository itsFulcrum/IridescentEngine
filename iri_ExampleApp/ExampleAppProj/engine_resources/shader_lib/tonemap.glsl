#ifndef TONEMAP_GLSL
#define TONEMAP_GLSL

#include "vendor/agx/agx.glsl"


vec3 tonemap_agx(const vec3 linearHdr) {
  return agx(linearHdr);
}

// Narkowicz 2015, "ACES Filmic Tone Mapping Curve"
vec3 tonemap_aces(const vec3 x) {
  const float a = 2.51f;
  const float b = 0.03f;
  const float c = 2.43f;
  const float d = 0.59f;
  const float e = 0.14f;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0f, 1.0f);
}

// default values could be sigma=0.7, n = 1.1;
vec3 tonemap_SCurve(const vec3 value, const float sigma, const float n) {
  vec3 pow_value = pow(value, vec3(n));
  return pow_value / (pow_value + pow(sigma, n));
}

vec3 tonemap_reinhard(const vec3 hdrColor) {
  return hdrColor / (1.0f + hdrColor);
}

vec3 tonemap_filmic(const vec3 x) {
  vec3 X = max(vec3(0.0f), x - 0.004f);
  vec3 result = (X * (6.2f * X + 0.5f)) / (X * (6.2f * X + 1.7f) + 0.06f);
  //return result;
  return pow(result, vec3(2.2f));
}

vec3 tonemap_clamp(const vec3 value) {
  return clamp(value.rgb, 0.0f, 1.0f);
}

#endif // TONEMAP_GLSL

