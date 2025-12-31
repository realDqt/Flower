#extension GL_EXT_buffer_reference2 : require // buffer_reference
#extension GL_EXT_scalar_block_layout : require // scalar
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require // uint64_t

#define M_PI 3.141592653589793f
#define RUSSIAN_ROULETTE 0.8f
#define WIDTH 1280
#define HEIGHT 760

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

vec3 evalDiffuseBRDF(vec3 wi, vec3 wo, vec3 normal, vec4 baseColor)
{
    float cosalpha = dot(wo, normal);
    if(cosalpha > 0.0){
        return baseColor.rgb / M_PI;
    }else{
        return vec3(0.0);
    }
}

vec3 toWorld(vec3 a, vec3 n)
{
    vec3 b, c;
    if(abs(n.x) > abs(n.y)){
        float invLen = 1.0f / length(vec2(n.x, n.z));
        c = vec3(n.z * invLen, 0.0, -n.x * invLen);
    }else{
        float invLen = 1.0f / length(vec2(n.y, n.z));
        c = vec3(0.0, n.z * invLen, -n.y * invLen);
    }
    b = cross(c, n);
    return a.x * b + a.y * c + a.z * n;
}

void cosineSampleHemisphere(vec3 normal, inout uint seed, out vec3 sampleDir, out float pdf)
{
    float r1 = rnd(seed);
    float r2 = rnd(seed);
    float r = sqrt(r1);
    float theta = 2.0 * M_PI * r2;

    // 在切线空间生成射线
    float x = r * cos(theta);
    float y = r * sin(theta);
    float z = sqrt(max(0.0, 1.0 - x*x - y*y)); // Z 轴对齐法线

    sampleDir = toWorld(vec3(x, y, z), normal);
    pdf = dot(sampleDir, normal) / M_PI;
}

uint getCoord1D(uvec2 coords2D)
{
    return coords2D.y * WIDTH + coords2D.x;
}