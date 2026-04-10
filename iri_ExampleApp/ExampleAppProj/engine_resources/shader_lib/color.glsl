#ifndef COLOR_GLSL
#define COLOR_GLSL

float grayscale_linear(vec3 color) {
  return (color.r * 0.333333333f) + (color.g * 0.333333333f) + (color.b * 0.333333333f);
}

float grayscale_natural(vec3 color) {
  return (color.r * 0.333333333f) + (color.g * 0.599999999f) + (color.b * 0.111111111f);
}

float grayscale_weighted(vec3 color,float redWeight, float greenWeight, float blueWeight) {
  return (color.r * redWeight) + (color.g * greenWeight) + (color.b * blueWeight);
}

vec3 desaturate_linear(vec3 color,float saturation) {
    float grayscale = (color.r * 0.333333333f) + (color.g * 0.333333333f) + (color.b * 0.333333333f);
    return mix(vec3(grayscale,grayscale,grayscale),color,saturation);
}

vec3 desaturate_natural(vec3 color, float saturation) {
    float grayscale = (color.r * 0.333333333f) + (color.g * 0.599999999f) + (color.b * 0.111111111f);
    return mix(vec3(grayscale,grayscale,grayscale),color,saturation);
}

vec3 desaturate_weighted(vec3 color, float redWeight, float greenWeight, float blueWeight, float saturation) {
    float grayscale = (color.r * redWeight) + (color.g * greenWeight) + (color.b * blueWeight);
    return mix(vec3(grayscale,grayscale,grayscale),color,saturation);
}

float luma_srgb(vec3 sRGB) {
  return dot(sRGB, vec3(0.299f, 0.587f, 0.114f));
}

float luma_linear(vec3 linearRGB) {
    return dot(linearRGB.rgb, vec3(0.2126729f,  0.7151522f, 0.0721750f) );
}

// meant for high dynamic ranges
vec3 apply_exposure(vec3 color,float exposure) {
  return color.rgb * pow(2,exposure);
}


//////////// Gamma Functions
// =============================================================================================================
// input is asumed to be in 0 to 1 range
float linear_to_srgb_float(float linear){
  if(linear <= 0.0031308f){
    return linear * 12.92f;
  }
  return 1.055f*pow(linear,(1.0f / 2.4f) ) - 0.055f;
}

// input is asumed to be in 0 to 1 range
float srgb_to_linear_float(float srgb){
  if(srgb <= 0.04045f){
    return srgb/12.92f;
  }
  return pow( (srgb + 0.055f)/ 1.055f, 2.4f);
}

// correct srgb transform functions but not super efficiant
vec3 srgb_to_linear(vec3 sRGBColor) {
    float r = srgb_to_linear_float(sRGBColor.r);
    float g = srgb_to_linear_float(sRGBColor.g);
    float b = srgb_to_linear_float(sRGBColor.b);
    return vec3(r,g,b);
}

vec3 linear_to_srgb(vec3 linearColor) {
  float r = linear_to_srgb_float(linearColor.r);
  float g = linear_to_srgb_float(linearColor.g);
  float b = linear_to_srgb_float(linearColor.b);
  return vec3(r,g,b);
}


float linear_to_srgb_float_gamma_2_2(float linear) {
  return pow(linear, 0.454545f);
}

float srgb_to_linear_float_gamma_2_2(float linear) {
  return pow(linear, 2.2f);
}

// cheap srgb but not 100% accurate
vec3 linear_to_srgb_gamma_2_2(vec3 linearColor) {
  return pow(linearColor.rgb, vec3(0.454545f));
}

vec3 srgb_to_linear_gamma_2_2(vec3 sRGBColor) {
  return pow(sRGBColor.rgb, vec3(2.2f));
}

#endif // COLOR_GLSL
