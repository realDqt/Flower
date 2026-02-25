#ifndef COMMON_GLSL
#define COMMON_GLSL
#extension GL_EXT_buffer_reference2 : require // buffer_reference
#extension GL_EXT_scalar_block_layout : require // scalar
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require // uint64_t
#include "DDGIVolumeDescGPU.glsl"

#define M_PI 3.141592653589793f
#define M_2PI 6.2831853071795864f
#define RUSSIAN_ROULETTE 0.8f

// Probe classification states
#define DDGI_PROBE_STATE_ACTIVE 0     // probe shoots rays and may be sampled by a front facing surface or another probe (recursive irradiance)
#define DDGI_PROBE_STATE_INACTIVE 1   // probe doesn't need to shoot rays, it isn't near a front facing surface

// The number of fixed rays that are used by probe relocation and classification.
// These rays directions are always the same to produce temporally stable results.
#define DDGI_NUM_FIXED_RAYS 32

// Volume movement types
#define DDGI_VOLUME_MOVEMENT_TYPE_DEFAULT 0
#define DDGI_VOLUME_MOVEMENT_TYPE_SCROLLING 1

// Texture formats (matches EDDGIVolumeTextureFormat)
#define DDGI_VOLUME_TEXTURE_FORMAT_U32 0
#define DDGI_VOLUME_TEXTURE_FORMAT_F16 1
#define DDGI_VOLUME_TEXTURE_FORMAT_F16x2 2
#define DDGI_VOLUME_TEXTURE_FORMAT_F16x4 3
#define DDGI_VOLUME_TEXTURE_FORMAT_F32 4
#define DDGI_VOLUME_TEXTURE_FORMAT_F32x2 5
#define DDGI_VOLUME_TEXTURE_FORMAT_F32x4 6

#define DDGI_PROBE_DEPTH_WITH_BORDER_SIDE 18
#define DDGI_PROBE_DEPTH_SIDE 16
#define DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE 10
#define DDGI_PROBE_IRRADIANCE_SIDE 8

#define DDGI_CHEBVSHEV_BIAS 0.2

struct Material{
    vec4 baseColor;
    vec3 emission;
    float metallic;
    float roughness;
};

struct RayPayload{
    vec3 worldNormal;
    vec3 worldPos;
    Material mat;
    float dis;
    uint hitKind;
};


struct Vertex {
    vec3 pos;
    vec3 normal;
    vec2 uv;
    vec4 color;
};

struct Triangle{
    Vertex vertices[3];
    vec3 normal;
};

layout(buffer_reference, scalar) buffer Vertices {Vertex v[]; };
layout(buffer_reference, scalar) buffer Indices {uint i[]; };

struct GeometryNode{
    uint64_t vertexBufferDeviceAddress;
    uint64_t indexBufferDeviceAddress;
};

struct Ray{
    vec3 origin;
    vec3 direction;
    float tmin;
    float tmax;
};

struct DirectionalLight{
    vec3 lightDir;
    vec3 lightIntensity;
};

bool IsVolumeMovementScrolling(DDGIVolumeDescGPU volume)
{
    return (volume.movementType == DDGI_VOLUME_MOVEMENT_TYPE_SCROLLING);
}
#endif