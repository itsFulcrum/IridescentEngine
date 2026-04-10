#ifndef NOISE_GLSL
#define NOISE_GLSL


// random functions
// bit shifting is not supported on all drivers but anything newer should be fine / webGL and GLES 2.0 wont work for example
float radical_inverse_VdC(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

// ----------------------------------------------------------------------------
vec2 hammersley(uint i, uint N) {
    return vec2(float(i)/float(N), radical_inverse_VdC(i));
}

float simple_hash(vec2 uv) {
    return fract(sin(7.289f * uv.x + 11.23f * uv.y) * 23758.5453f);
}

float randf(int x, int y) {
    // https://blog.demofox.org/2022/01/01/interleaved-gradient-noise-a-different-kind-of-low-discrepancy-sequence/
    return mod(52.9829189f * mod(0.06711056f * float(x) + 0.00583715f * float(y), 1.0f), 1.0f);
}


const int ditherBayer[8][8] =
{
{ 0, 32,  8, 40,  2, 34, 10, 42},
{48, 16, 56, 24, 50, 18, 58, 26},
{12, 44,  4, 36, 14, 46,  6, 38},
{60, 28, 52, 20, 62, 30, 54, 22},
{ 3, 35, 11, 43,  1, 33,  9, 41},
{51, 19, 59, 27, 49, 17, 57, 25},
{15, 47,  7, 39, 13, 45,  5, 37},
{63, 31, 55, 23, 61, 29, 53, 21}
};

float dither_bayer(int x, int y) {
    float b = float(ditherBayer[x%8][y%8] ) / 64.0f;
    return b;
}


float white_noise_3D_to_1D(vec3 vec){

    vec3 smallValue = vec3(sin(vec.x),sin(vec.y),sin(vec.z));

    float random = dot(smallValue, vec3(12.9898f, 78.233f, 37.719f));
    
    random = fract(sin(random) * 143758.5453f);
    return random;
}


float white_noise_2D_to_1D(vec2 vec){

    vec3 smallValue = vec3( sin(vec.x) , sin(vec.y) , cos(vec.x * vec.y * 37.719f + 11.23f) );

    float random = dot(smallValue, vec3(12.9898f, 78.233f, 37.719f));
    
    random = fract(sin(random) * 143758.5453f);
    return random;
}


uint hilbert_index(uvec2 p) {
    uint i = 0u;
    for(uint l = 0x4000u; l > 0u; l >>= 1u) {
        uvec2 r = min(p & l, 1u);
        
        i = (i << 2u) | ((r.x * 3u) ^ r.y);       
        p = r.y == 0u ? (0x7FFFu * r.x) ^ p.yx : p;
    }
    return i;
}


uint owen_hash(uint x, uint seed) { // seed is any random number
    x ^= x * 0x3d20adeau;
    x += seed;
    x *= (seed >> 16) | 1u;
    x ^= x * 0x05526c56u;
    x ^= x * 0x53a22864u;
    return x;
}

uint reverse_bits(uint x) {
    x = ((x & 0xaaaaaaaau) >> 1) | ((x & 0x55555555u) << 1);
    x = ((x & 0xccccccccu) >> 2) | ((x & 0x33333333u) << 2);
    x = ((x & 0xf0f0f0f0u) >> 4) | ((x & 0x0f0f0f0fu) << 4);
    x = ((x & 0xff00ff00u) >> 8) | ((x & 0x00ff00ffu) << 8);
    return (x >> 16) | (x << 16);
}

float blue_noise_2D_to_1D(uvec2 uvCoords){

    uint m = hilbert_index(uvec2(uvCoords));
    m = owen_hash(reverse_bits(m), 0xe7843fbfu);
    m = owen_hash(reverse_bits(m), 0x8d8fb1e0u);
    //mask = float(ReverseBits(m)) / 4294967296.0;
    return float(reverse_bits(m)) / 4294967296.0;

}

float reshape_uniform_to_triangle(float v) {
    v = v * 2.0f - 1.0f;
    v = sign(v) * (1.0f - sqrt(max(0.0f, 1.0f - abs(v)))); // [-1, 1], max prevents NaNs
    return v + 0.5f; // [-0.5, 1.5]
}

#endif // NOISE_GLSL