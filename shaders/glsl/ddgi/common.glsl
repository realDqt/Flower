#ifndef COMMON_GLSL
#define COMMON_GLSL
#extension GL_EXT_buffer_reference2 : require // buffer_reference
#extension GL_EXT_scalar_block_layout : require // scalar
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require // uint64_t

#define M_PI 3.141592653589793f
#define RUSSIAN_ROULETTE 0.8f

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
#endif