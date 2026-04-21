#ifndef NOISE_PERLIN_GLSL
#define NOISE_PERLIN_GLSL

// Perlin Noise by:
// https://www.shadertoy.com/view/slB3z3

// fast high-quality hash https://www.shadertoy.com/view/wfVczm
uint noise_perlin_hash(uvec3 key, uint seed) { 
    uvec3 k = key;
    k *= 0x27d4eb2fu; 
    k ^= k >> 16;
    k *= 0x85ebca77u; 
    uint h = seed;
    h ^= k.x;
    h ^= h >> 16;
    h *= 0x9e3779b1u;
    h ^= k.y;
    h ^= h >> 16;
    h *= 0x9e3779b1u;
    h ^= k.z;
    h ^= h >> 16;
    h *= 0x9e3779b1u;
    h ^= h >> 16;
    h *= 0xed5ad4bbu;
    h ^= h >> 16;
    return h;
}

// generates a distinct seed for each octave
// that will behave like a 4th coordinate  
// when mixed into the final hash
uint noise_perlin_hash(uint key, uint seed) {
    uint k = key;
    k *= 0x27d4eb2fu; 
    k ^= k >> 16;
    k *= 0x85ebca77u; 
    uint h = seed;
    h ^= k;
    h ^= h >> 16;
    h *= 0x9e3779b1u;
    return h;
}

vec3 noise_perlin_gradient(uint h) {
    const vec3 gradients[12] = vec3[12](
        vec3(1, 1, 0), vec3(-1, 1, 0), vec3(1, -1, 0), vec3(-1, -1, 0),
        vec3(1, 0, 1), vec3(-1, 0, 1), vec3(1, 0, -1), vec3(-1, 0, -1),
        vec3(0, 1, 1), vec3(0, -1, 1), vec3(0, 1, -1), vec3(0, -1, -1)
    ); 
    return gradients[int(h % 12u)];
}

vec3 noise_perlin_fade(vec3 t) {
    // 6t^5 - 15t^4 + 10t^3
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float noise_perlin_interpolate_triliniear(float value1, float value2, float value3, float value4, float value5, float value6, float value7, float value8, vec3 t) {
    return mix(
        mix(mix(value1, value2, t.x), mix(value3, value4, t.x), t.y),
        mix(mix(value5, value6, t.x), mix(value7, value8, t.x), t.y),
        t.z
    );
}


float noise_perlin_3D(vec3 position, uint seed) {
    vec3 floorPosition = floor(position);
    vec3 fractPosition = position - floorPosition;
    uvec3 cellCoordinates = uvec3(ivec3(floorPosition));
    float value1 = dot(noise_perlin_gradient(noise_perlin_hash(cellCoordinates, seed)), fractPosition);
    float value2 = dot(noise_perlin_gradient(noise_perlin_hash(cellCoordinates + uvec3(1, 0, 0), seed)), fractPosition - vec3(1, 0, 0));
    float value3 = dot(noise_perlin_gradient(noise_perlin_hash(cellCoordinates + uvec3(0, 1, 0), seed)), fractPosition - vec3(0, 1, 0));
    float value4 = dot(noise_perlin_gradient(noise_perlin_hash(cellCoordinates + uvec3(1, 1, 0), seed)), fractPosition - vec3(1, 1, 0));
    float value5 = dot(noise_perlin_gradient(noise_perlin_hash(cellCoordinates + uvec3(0, 0, 1), seed)), fractPosition - vec3(0, 0, 1));
    float value6 = dot(noise_perlin_gradient(noise_perlin_hash(cellCoordinates + uvec3(1, 0, 1), seed)), fractPosition - vec3(1, 0, 1));
    float value7 = dot(noise_perlin_gradient(noise_perlin_hash(cellCoordinates + uvec3(0, 1, 1), seed)), fractPosition - vec3(0, 1, 1));
    float value8 = dot(noise_perlin_gradient(noise_perlin_hash(cellCoordinates + uvec3(1, 1, 1), seed)), fractPosition - vec3(1, 1, 1));
    return noise_perlin_interpolate_triliniear(value1, value2, value3, value4, value5, value6, value7, value8, noise_perlin_fade(fractPosition));
}


float noise_perlin_3D(vec3 position, int octaveCount, float persistence, float lacunarity, uint seed) {
    float value = 0.0;
    float amplitude = 1.0;
    for (int i = 0; i < octaveCount; i++) {
        uint s = noise_perlin_hash(uint(i), seed); 
        value += noise_perlin_3D(position, s) * amplitude;
        amplitude *= persistence;
        position *= lacunarity;
    }
    return value;
}

#endif // NOISE_PERLIN_GLSL