#extension GL_EXT_buffer_reference2 : require // buffer_reference
#extension GL_EXT_scalar_block_layout : require // scalar
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require // uint64_t

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
struct Vertex{
    vec3 pos;
};

struct Triangle{
    Vertex vertices[3];
    vec3 normal;
};

layout(buffer_reference, scalar) buffer Vertices {vec4 v[]; };
layout(buffer_reference, scalar) buffer Indices {uint i[]; };

struct GeometryNode{
    uint64_t vertexBufferDeviceAddress;
    uint64_t indexBufferDeviceAddress;
};

vec3 getNormal01(vec3 v)
{
    v = (v + vec3(1.0)) * vec3(0.5);
    return v;
}
