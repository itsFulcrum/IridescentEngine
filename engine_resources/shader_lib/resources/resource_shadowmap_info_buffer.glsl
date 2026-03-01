#ifndef RES_SHADOWINFO_BUFFER
#define RES_SHADOWINFO_BUFFER


#ifndef RES_SHADOWINFO_BUFFER_SET
#define RES_SHADOWINFO_BUFFER_SET 0
#endif

#ifndef RES_SHADOWINFO_BUFFER_BIND
#define RES_SHADOWINFO_BUFFER_BIND 0
#endif

struct ShadowmapInfo {
  mat4  view_proj;
  int   array_layer; // -1 == unused 
  uint  mip_level;
  uint  resolution;
  float texels_per_world_unit; // resolution / frustum_extents
};

layout (std140, set=RES_SHADOWINFO_BUFFER_SET, binding=RES_SHADOWINFO_BUFFER_BIND) readonly buffer shadowmap_buffer {
    uint array_len;
    uint padding1; 
    uint padding2;
    uint padding3;
    ShadowmapInfo infos[];
} _shadowmap_buffer;

#endif