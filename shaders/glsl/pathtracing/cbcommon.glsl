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

struct Ray{
    vec3 origin;
    vec3 direction;
    float tmin;
    float tmax;
};

vec3 getNormal01(vec3 v)
{
    v = (v + vec3(1.0)) * vec3(0.5);
    return v;
}

bool hasEmission(Material mat)
{
    return dot(mat.emission, vec3(1.0)) > 0.01;
}

vec3 getTriNormalFromTriPositions(vec3 triPositions[3])
{
    return normalize(cross(triPositions[1] - triPositions[0], triPositions[2] - triPositions[1]));
}

vec3 evalDiffuseBRDF(vec3 wi, vec3 wo, vec3 normal, Material mat)
{
    float cosalpha = dot(wo, normal);
    if(cosalpha > 0.0){
        return mat.baseColor.rgb / M_PI;
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

vec3 uniformSampleHemisphere(vec3 normal, inout uint seed)
{
    float x_1 = rnd(seed);
    float x_2 = rnd(seed);
    float z = abs(1.0f - 2.0f * x_1);
    float r = sqrt(1.0f - z * z), phi = 2.0f * M_PI * x_2;
    vec3 localRay = vec3(r * cos(phi), r * sin(phi), z);
    return toWorld(localRay, normal);
}

vec3 cosineSampleHemisphere(vec3 normal, inout uint seed)
{
    float r1 = rnd(seed);
    float r2 = rnd(seed);
    float r = sqrt(r1);
    float theta = 2.0 * M_PI * r2;

    // 在切线空间生成射线
    float x = r * cos(theta);
    float y = r * sin(theta);
    float z = sqrt(max(0.0, 1.0 - x*x - y*y)); // Z 轴对齐法线

    return toWorld(vec3(x, y, z), normal);
}

// 计算三角形面积
// 原理：三角形面积等于两边叉积模长的一半
float cacTriangleArea(vec3 worldPositions[3])
{
    vec3 edge1 = vec3(worldPositions[1] - worldPositions[0]);
    vec3 edge2 = vec3(worldPositions[2] - worldPositions[0]);

    // cross(edge1, edge2) 得到法向量（长度为平行四边形面积）
    // length 取模长，然后除以 2 得到三角形面积
    float area = 0.5 * length(cross(edge1, edge2));

    return area;
}

// 均匀采样三角形表面的点
// 注意：必须传入 seed 用于生成随机数，且必须使用 sqrt 校正分布
vec3 uniformSampleTriangle(vec3 worldPositions[3], inout uint seed)
{
    // 1. 获取两个 [0, 1) 的随机数
    // 假设你有之前定义的 rnd() 函数
    float r1 = rnd(seed);
    float r2 = rnd(seed);

    // 2. 计算重心坐标 (Barycentric Coordinates)
    // 关键：必须对 r1 开根号，否则采样点会聚集在 worldPositions[0] 附近
    float sqrtR1 = sqrt(r1);

    float u = 1.0 - sqrtR1;
    float v = sqrtR1 * (1.0 - r2);
    float w = sqrtR1 * r2; // 或者 w = 1.0 - u - v;

    // 3. 混合顶点位置得到采样点
    vec3 samplePoint = vec3(worldPositions[0] * u +
    worldPositions[1] * v +
    worldPositions[2] * w);

    return samplePoint;
}