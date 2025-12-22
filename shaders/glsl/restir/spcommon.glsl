#extension GL_EXT_buffer_reference2 : require // buffer_reference
#extension GL_EXT_scalar_block_layout : require // scalar
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require // uint64_t

#define M_PI 3.141592653589793f
#define RUSSIAN_ROULETTE 0.8f

struct RayPayload{
    vec3 worldNormal;
    vec3 worldPos;
    vec4 baseColor;
    float dis;
};

struct Vertex {
    vec3 pos;
    vec3 normal;
    vec2 uv;
    vec4 color;
    vec4 joint0;
    vec4 weight0;
    vec4 tangent;
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
    int textureIndexBaseColor;
    int textureIndexNormal;
};

struct Ray{
    vec3 origin;
    vec3 direction;
    float tmin;
    float tmax;
};

// Tiny Encryption Algorithm
// By Fahad Zafar, Marc Olano and Aaron Curtis, see https://www.highperformancegraphics.org/previous/www_2010/media/GPUAlgorithms/HPG2010_GPUAlgorithms_Zafar.pdf
uint tea(uint val0, uint val1)
{
    uint sum = 0;
    uint v0 = val0;
    uint v1 = val1;
    for (uint n = 0; n < 16; n++)
    {
        sum += 0x9E3779B9;
        v0 += ((v1 << 4) + 0xA341316C) ^ (v1 + sum) ^ ((v1 >> 5) + 0xC8013EA4);
        v1 += ((v0 << 4) + 0xAD90777D) ^ (v0 + sum) ^ ((v0 >> 5) + 0x7E95761E);
    }
    return v0;
}

// Linear congruential generator based on the previous RNG state
// See https://en.wikipedia.org/wiki/Linear_congruential_generator
uint lcg(inout uint previous)
{
    const uint multiplier = 1664525u;
    const uint increment = 1013904223u;
    previous   = (multiplier * previous + increment);
    return previous & 0x00FFFFFFu;
}

// Generate a random float in [0, 1) given the previous RNG state
float rnd(inout uint previous)
{
    return (float(lcg(previous)) / float(0x01000000));
}

vec3 getNormal01(vec3 v)
{
    v = (v + vec3(1.0)) * vec3(0.5);
    return v;
}