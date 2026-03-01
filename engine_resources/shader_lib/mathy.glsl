#ifndef MATHY_GLSL
#define MATHY_GLSL

precision highp float;

#define PI 3.14159265359f
#define EPSILON_F32 1.192092896e-07f
#define HALF_PI 1.57079632679f
#define QUATER_PI 0.78539816339f
#define ONE_OVER_PI 0.31830988618f
#define GOLDEN_RATIO 1.618033988749894f
#define SQRT_TWO  1.414213562373095f
#define TAU 6.28318530718f
#define RAD_PER_DEG 0.01745329251994329577f // TAU / 360
#define PHI 1.61803398875f // = (1.0+sqrt(5.0))/2.0
#define FLOAT_INFINITY 34028234663852885981170418348451692544.0f

// saturate
float saturate(float value) {
    return clamp(value,0.0f,1.0f);
}
vec2 saturate(vec2 value) {
    return vec2(clamp(value.x,0.0f,1.0f),clamp(value.y,0.0f,1.0f));
}
vec3 saturate(vec3 value) {
    return vec3(clamp(value.x,0.0f,1.0f),clamp(value.y,0.0f,1.0f),clamp(value.z,0.0f,1.0f));
}
vec4 saturate(vec4 value) {
    return vec4(clamp(value.x,0.0f,1.0f),clamp(value.y,0.0f,1.0f),clamp(value.z,0.0f,1.0f),clamp(value.w,0.0f,1.0f));
}


// LERP
float lerp(const float a, const float b, const float t) {
    return fma((1.0f - t) , a , b * t); // (1.0f - t) * a + b * t;
}
vec2 lerp(vec2 a, vec2 b, float t) {
    return mix(a,b,t);
}
vec3 lerp(vec3 a,vec3 b, float t) {
    return mix(a,b,t);
}
vec4 lerp(vec4 a,vec4 b, float t) {
    return mix(a,b,t);
}

// INVERSE LERP
float inverse_lerp(float a, float b, float v) {
  return (v-a) / (b - a);
}


float remap(float iMin,float iMax,float oMin,float oMax, float v) {
  float t = inverse_lerp(iMin,iMax,v);
  return lerp(oMin,oMax,t);
}


float fast_acos(float val) {
    float x = abs(val); 
    float res = fma(-0.156583f, x , HALF_PI) * sqrt(1.0f - x);
    return (val >= 0) ? res : PI - res; 
}

vec2 fast_acos(vec2 val) {
    vec2 x = abs(val);
    vec2 res = fma(vec2(-0.156583f), x , vec2(HALF_PI)) * sqrt(1.0f - x);
    return vec2((val.x >= 0.0f) ? res.x : PI - res.x, (val.y >= 0.0f) ? res.y : PI - res.y);
}


// MATRIX STUFF

mat3 adjoint(mat3 m){
    // Faster way to do transpose inverse to get normal matrix: 'transpose(inverse(mat3(m)))'
    // https://www.shadertoy.com/view/3s33zj
    return mat3(cross(m[1].xyz, m[2].xyz),
        cross(m[2].xyz, m[0].xyz),
        cross(m[0].xyz, m[1].xyz)); 
}

mat4 scale_mat4(vec3 scale){
    return mat4(
        vec4(scale.x, 0.0f   , 0.0f   , 0.0f),
        vec4(0.0f   , scale.y, 0.0f   , 0.0f),
        vec4(0.0f   , 0.0f   , scale.z, 0.0f),
        vec4(0.0f   , 0.0f   , 0.0f   , 1.0f)
    );
}

mat4 translate_mat4(vec3 pos){
    return mat4(
        vec4(1.0f , 0.0f , 0.0f , 0.0f),
        vec4(0.0f , 1.0f , 0.0f , 0.0f),
        vec4(0.0f , 0.0f , 1.0f , 0.0f),
        vec4(pos.x, pos.y, pos.z, 1.0f)
    );
}

mat4 rotate_mat4_X(float phi){
    return mat4(
        vec4(1.0f, 0.0f    , 0.0f     , 0.0f),
        vec4(0.0f, cos(phi), -sin(phi), 0.0f),
        vec4(0.0f, sin(phi), cos(phi) , 0.0f),
        vec4(0.0f, 0.0f    , 0.0f     , 1.0f));
}

mat4 rotate_mat4_Y(float theta){
    return mat4(
        vec4(cos(theta), 0.0f , -sin(theta), 0.0f),
        vec4(0.0f      , 1.0f , 0.0f       , 0.0f),
        vec4(sin(theta), 0.0f , cos(theta) , 0.0f),
        vec4(0.0f      , 0.0f , 0.0f       , 1.0f));
}

mat3 rotate_mat3_Y(float theta){
    float cos_theta = cos(theta);
    float sin_theta = sin(theta);
    return mat3(
        vec3(cos_theta, 0.0f , -sin_theta),
        vec3(0.0f      , 1.0f , 0.0f      ),
        vec3(sin_theta, 0.0f , cos_theta ));
}

mat4 rotate_mat4_Z(float psi){
    return mat4(
        vec4(cos(psi),-sin(psi),0.0f ,0.0f),
        vec4(sin(psi),cos(psi) ,0.0f ,0.0f),
        vec4(0.0f    , 0.0f    ,1.0f ,0.0f),
        vec4(0.0f    , 0.0f    ,0.0f ,1.0f));
}

// rotate vector around an axis (by unity)
vec3 rotate_around_axis_radians(vec3 In, vec3 Axis, float Rotation) {
    float s = sin(Rotation);
    float c = cos(Rotation);
    float one_minus_c = 1.0f - c;
    Axis = normalize(Axis);

    mat3x3 rot_mat;
    rot_mat[0][0] = one_minus_c * Axis.x * Axis.x + c;
    rot_mat[1][0] = one_minus_c * Axis.x * Axis.y - Axis.z * s;
    rot_mat[2][0] = one_minus_c * Axis.z * Axis.x + Axis.y * s;
    rot_mat[0][1] = one_minus_c * Axis.x * Axis.y + Axis.z * s;
    rot_mat[1][1] = one_minus_c * Axis.y * Axis.y + c;
    rot_mat[2][1] = one_minus_c * Axis.y * Axis.z - Axis.x * s;
    rot_mat[0][2] = one_minus_c * Axis.z * Axis.x - Axis.y * s;
    rot_mat[1][2] = one_minus_c * Axis.y * Axis.z + Axis.x * s;
    rot_mat[2][2] = one_minus_c * Axis.z * Axis.z + c;
    return rot_mat * In;
}


// expects values to be in -1..1 range and outputs in -1..1 range
vec3 normal_reconstruct_z(vec2 In) {
    float reconstructZ = sqrt(1.0f - saturate(dot(In.xy, In.xy)));
    vec3 normalVector = vec3(In.x, In.y, reconstructZ);
    return normalize(normalVector);
}

// this scales normal between 0 and 1 // this is honestly weird implmentation
vec3 normal_strength(vec3 In, float Strength) {
  return vec3(In.xy * Strength, lerp(1.0f, In.z, saturate(Strength)));
}

vec3 normal_strength_spherical(vec3 n, float strength) {
  // convert to cartesian to spherical cooridnates
  float theta = atan(n.y,n.x);
  float phi = atan(sqrt(n.x*n.x + n.y*n.y),n.z);

  phi = clamp(phi * strength,0.0f,PI*0.5f);

  // convert back spherical to cartesian coordinates
  vec3 z = vec3(0.0f,0.0f,1.0f);
  z = rotate_around_axis_radians(z, vec3(0.0f,1.0f,0.0f), phi);
  z = rotate_around_axis_radians(z, vec3(0.0f,0.0f,1.0f), theta);

  vec3 normalOut = z.xyz;
  return normalOut;
}

vec2 cartesian_to_spherical(vec3 dir) {
    
    float length_xy = length(dir.xy);
    float theta = atan(length_xy, dir.z);
    float phi = atan(dir.y,dir.x);

    return vec2(theta, phi);
}

vec3 spherical_to_cartesian(float theta, float phi){
    float sin_theta = sin(theta);
    return vec3(sin_theta*cos(phi), sin_theta*sin(phi), cos(theta));
}


vec2 oct_wrap( vec2 v ) {
    vec2 w = 1.0f - abs( v.yx );
    if (v.x < 0.0f) w.x = -w.x;
    if (v.y < 0.0f) w.y = -w.y;
    return w;
}
 
vec2 oct_encode(vec3 n) {
    n /= ( abs( n.x ) + abs( n.y ) + abs( n.z ) );
    n.xy = n.z > 0.0f ? n.xy : oct_wrap( n.xy );
    n.xy = n.xy * 0.5f + 0.5f; // map from -1..1 to 0..1 range
    return n.xy;
}
 
vec3 oct_decode(vec2 f) {
    f = f * 2.0f - 1.0f; // map from 0..1 to -1..1 range 
    // https://twitter.com/Stubbesaurus/status/937994790553227264
    vec3 n = vec3( f.x, f.y, 1.0f - abs( f.x ) - abs( f.y ) );
    float t = max( -n.z, 0.0f );
    n.x += n.x >= 0.0f ? -t : t;
    n.y += n.y >= 0.0f ? -t : t;
    return normalize(n);
}

ivec2 oct_wrap_texel_coordinates(const in ivec2 texel, const in ivec2 texSize) {
  ivec2 wrapped = ((texel % texSize) + texSize) % texSize;
  return ((((abs(texel.x / texSize.x) + int(texel.x < 0)) ^ (abs(texel.y / texSize.y) + int(texel.y < 0))) & 1) != 0) ? (texSize - (wrapped + ivec2(1))) : wrapped;
}


// make depth linear given near clip and far clip plane camera values
float linearize_depth(float nonlin_depth , float z_near, float z_far) {
    return z_near * z_far / (z_far + nonlin_depth * (z_near - z_far));
}


vec3 reconstruct_position_from_depth(vec2 screen_uv, float nonlin_depth_sample, mat4 inv_mat) {
    
    // @Note - Pass either a inverse_view_projection matrix to get postion in world space
    // or just inverse_projection to get postion in view space.

    // screen_uv in 0..1 range
    
    // depth sample should come directly from depth texture also in 0..1 range.
    // one can also pass inv_proj matrix instead of inv_view_proj to arrive at view_space postion
    
    // https://wickedengine.net/2019/09/improved-normal-reconstruction-from-depth/

    screen_uv.y = 1.0f - screen_uv.y; // idk for some reason we have to flip this.

    screen_uv = fma(screen_uv, vec2(2.0f), vec2(-1.0f) );
    
    vec4 clip_pos  = vec4( screen_uv.xy, nonlin_depth_sample, 1.0f);
    vec4 world_pos = inv_mat * clip_pos;

    return world_pos.xyz / world_pos.w; // perspective divide
}

vec3 reconstruct_normal_from_depth(sampler2D depth_sampler, int mip, uvec2 depth_tex_dimentions, vec2 uv_center, float depth_at_uv_center, vec3 pos_at_uv_center, mat4 inv_matrix) {

    // ASSUMES DEPTH IS IN THE SAMPLERS .r channels

    // normal reconstruction based on this blog post: 
    // https://wickedengine.net/2019/09/improved-normal-reconstruction-from-depth/
    
    // @Note - Pass either a inverse_view_projection matrix to get normal in world space
    // or just inverse_projection to get normal in view space.
    // 'pos_at_uv_center' must match this the space ofcourse
    // use e.g. function above this one to get postion 

    // to construct normals from depth we must at least take 3 depth samples and reconstruct postion (world or view space)
    // from those 3 positions we can use cross product to calculate the normal

    // but in which direction should we take neighbouring samples ?
    // to reduce artifacts we can instead sample in a cross pattern 4 times.
    // so we take 4 depth samples around the center sample
    // up, down, left and right
    // we then compare which of those match the center depth values more
    
    // now given the up down left right samples we can form triangles
    // like this

    /*
    
     t2  / u \  t0
        /  |  \ 
       /   |   \
      l----c----r
       \   |   /
        \  |  /
    t3   \ d /  t1
    
    */

    // we will chose one best horizontal sample (left or right)
    // and one best vertical (up down)

    // using counter clockwise order we can than make form triangles 
    // with the center (p0) and the chosen corners to construct our normal 
    // here is how to chose p1 and p2 based on wich corners are better fit

    // t0 = p0: center, p1: right, p2: up
    // t1 = p0: center, p1: down,  p2: right
    // t2 = p0: center, p1: up,    p2: left
    // t3 = p0: center, p1: left,  p2: down
    
    // formula: normal = normalize(cross(p2 - p0, p1 - p0))

    ivec2 texel_center = ivec2(uv_center * vec2(depth_tex_dimentions));

    ivec2 texel_up      = texel_center + ivec2( 0,  1);
    ivec2 texel_right   = texel_center + ivec2( 1,  0);
    ivec2 texel_down    = texel_center + ivec2( 0, -1);
    ivec2 texel_left    = texel_center + ivec2(-1,  0);
    
    float z_center  = depth_at_uv_center;
    float z_up      = texelFetch(depth_sampler, texel_up   , mip).x;
    float z_right   = texelFetch(depth_sampler, texel_right, mip).x;
    float z_down    = texelFetch(depth_sampler, texel_down , mip).x;
    float z_left    = texelFetch(depth_sampler, texel_left , mip).x;

    vec2 uv_up      = uv_center + vec2( 0.0f,  1.0f) / vec2(depth_tex_dimentions);
    vec2 uv_right   = uv_center + vec2( 1.0f,  0.0f) / vec2(depth_tex_dimentions);
    vec2 uv_down    = uv_center + vec2( 0.0f, -1.0f) / vec2(depth_tex_dimentions);
    vec2 uv_left    = uv_center + vec2(-1.0f,  0.0f) / vec2(depth_tex_dimentions);
    
    // float z_center  = depth_at_uv_center;
    // float z_up      = textureLod(depth_sampler, uv_up   , mip).x;
    // float z_right   = textureLod(depth_sampler, uv_right, mip).x;
    // float z_down    = textureLod(depth_sampler, uv_down , mip).x;
    // float z_left    = textureLod(depth_sampler, uv_left , mip).x;

    // 0 means up is better, 1 mean down is better
    uint best_z_vertical = abs(z_up - z_center) < abs(z_down - z_center) ? 0 : 1;
    // 0 means right is better, 1 mean left is better
    uint best_z_horizontal   = abs(z_right - z_center) < abs(z_left - z_center) ? 0 : 1;


    vec3 p0 = pos_at_uv_center;
    vec3 p1 = vec3(0.0f);
    vec3 p2 = vec3(0.0f);

    if (best_z_vertical == 0 && best_z_horizontal == 0){
        // up and right
        p1 = reconstruct_position_from_depth(uv_right, z_right  , inv_matrix);
        p2 = reconstruct_position_from_depth(uv_up, z_up  , inv_matrix);
    } else if (best_z_vertical == 0 && best_z_horizontal == 1){
        // up and left        
        p1 = reconstruct_position_from_depth(uv_up  , z_up  , inv_matrix);
        p2 = reconstruct_position_from_depth(uv_left, z_left, inv_matrix);
    } else if (best_z_vertical == 1 && best_z_horizontal == 0){
        // down and right
        p1 = reconstruct_position_from_depth(uv_down, z_down, inv_matrix);
        p2 = reconstruct_position_from_depth(uv_right, z_right, inv_matrix);
    } else if (best_z_vertical == 1 && best_z_horizontal == 1){
        // down and left
        p1 = reconstruct_position_from_depth(uv_left, z_left, inv_matrix);
        p2 = reconstruct_position_from_depth(uv_down, z_down, inv_matrix);
    }

    vec3 normal = normalize(cross(p2 - p0, p1 - p0));

    return normal;
}


vec3 reconstruct_normal_from_depth_simple(sampler2D depth_sampler, uvec2 depth_tex_dimentions, vec2 uv_center, float depth_at_uv_center, vec3 pos_at_uv_center, mat4 inv_matrix) {


    //vec2 uv_center  = uv;
    vec2 uv_up      = uv_center + vec2( 0.0f,  1.0f) / vec2(depth_tex_dimentions);
    vec2 uv_right   = uv_center + vec2( 1.0f,  0.0f) / vec2(depth_tex_dimentions);
    
    float z_center  = depth_at_uv_center;
    float z_up      = texture(depth_sampler, uv_up).r;
    float z_right   = texture(depth_sampler, uv_right).r;

    vec3 p0 = pos_at_uv_center;

    vec3 p1 = reconstruct_position_from_depth(uv_right, z_right  , inv_matrix);
    vec3 p2 = reconstruct_position_from_depth(uv_up, z_up  , inv_matrix);

    vec3 normal = normalize(cross(p2 - p0, p1 - p0));

    return normal;
}

vec3 reconstruct_world_pos_from_uv_and_linear_depth(vec2 uv, float linear_depth, mat4 inv_view_mat, mat4 inv_proj_mat, float depth_bias) { 
    vec2 ndc = uv * 2.0f - 1.0f;

    vec4 clipPos = vec4(ndc.x, ndc.y, -1.0f, 1.0f);    

    vec4 viewPos = inv_proj_mat * clipPos;
    viewPos /= viewPos.w;
    
    float scale = linear_depth / abs(viewPos.z);
    float bias = 1.0 - depth_bias;

    vec3 viewPosAtDepth = viewPos.xyz * (scale * bias);
    
    vec4 worldPos = inv_view_mat * vec4(viewPosAtDepth, 1.0f);
    return worldPos.xyz;
}



// Easing funcitons

float ease_bezier_blend(float t)
{
    return t * t * (3.0f - 2.0f * t);
}

float ease_in_out_sine(float x) {
    return -(cos( PI * x) - 1.0f) / 2.0f;
}

float ease_out_circ(float x) {
    return sqrt(1 - pow(x - 1.0f, 2.0f));
}

float ease_in_out_circ(float x) {
    if( x < 0.5f){
        return (1.0f - sqrt(1.0f - pow(2.0f * x, 2.0f))) / 2.0f;
    }
    
     return (sqrt(1.0f - pow(-2.0f * x + 2.0f, 2.0f)) + 1.0f) / 2.0f;
}

#endif // MATHY_GLSL
