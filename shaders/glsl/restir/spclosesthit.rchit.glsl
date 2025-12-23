#version 460

#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#include "spcommon.glsl"

layout(location = 0) rayPayloadInEXT RayPayload hitValue;
hitAttributeEXT vec2 attribs;

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;
layout(binding = 3, set = 0) buffer DirectionalLight{
    vec4 direction; // 平行光方向 (从光源指向场景)
    vec4 emission;  // 强度/颜色
} directionalLight;
layout(binding = 4, set = 0) buffer GeometryNodes { GeometryNode nodes[]; } geometryNodes;
layout(binding = 5, set = 0) uniform sampler2D textures[];


Triangle unpackTriangle(uint index){
    Triangle tri;
    const uint triIndex = index * 3;

    GeometryNode geometryNode = geometryNodes.nodes[gl_GeometryIndexEXT];

    Indices indices = Indices(geometryNode.indexBufferDeviceAddress);
    Vertices vertices = Vertices(geometryNode.vertexBufferDeviceAddress);

    for(uint i = 0; i < 3; i++){
        const uint offset = indices.i[triIndex + i];
        tri.vertices[i] = vertices.v[offset];
    }

    vec3 barycentricCoords = vec3(1.0f - attribs.x - attribs.y, attribs.x, attribs.y);
    tri.normal = normalize(cross(tri.vertices[1].pos - tri.vertices[0].pos, tri.vertices[2].pos - tri.vertices[1].pos));
    return tri;
}

vec3 calcWorldPosByInterpolation(Triangle tri)
{
    const vec3 barycentrics = vec3(1.0f - attribs.x - attribs.y, attribs.x, attribs.y);
    vec3 p0 = tri.vertices[0].pos;
    vec3 p1 = tri.vertices[1].pos;
    vec3 p2 = tri.vertices[2].pos;
    vec3 localPos = p0 * barycentrics.x + p1 * barycentrics.y + p2 * barycentrics.z;
    return vec3(gl_ObjectToWorldEXT * vec4(localPos, 1.0));
}

vec3 calcWorldPosByRayHitInfo()
{
    return gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;
}

vec2 getSampleUV(Triangle tri)
{
    const vec3 barycentrics = vec3(1.0f - attribs.x - attribs.y, attribs.x, attribs.y);
    vec2 uv0 = tri.vertices[0].uv;
    vec2 uv1 = tri.vertices[1].uv;
    vec2 uv2 = tri.vertices[2].uv;
    vec2 uv = uv0 * barycentrics.x + uv1 * barycentrics.y + uv2 * barycentrics.z;
    return uv;
}

vec3 calcWorldNormalByInterpolation(Triangle tri)
{
    const vec3 barycentrics = vec3(1.0f - attribs.x - attribs.y, attribs.x, attribs.y);
    vec3 vNormal = tri.vertices[0].normal * barycentrics.x +
                   tri.vertices[1].normal * barycentrics.y +
                   tri.vertices[2].normal * barycentrics.z;
    vec3 worldNormal = normalize(vNormal * mat3(gl_WorldToObjectEXT)); // m^(-1)^T
    return worldNormal;
}

vec3 calcWorldNormalBySampling(Triangle tri, vec2 sampleUV)
{
    GeometryNode geometryNode = geometryNodes.nodes[gl_GeometryIndexEXT];
    vec3 localNormalSample = texture(textures[nonuniformEXT(geometryNode.textureIndexNormal)], sampleUV).rgb;
    
    const vec3 barycentrics = vec3(1.0f - attribs.x - attribs.y, attribs.x, attribs.y);
    
    // 1. 重心坐标插值获取顶点法线和切线 (Object Space)
    vec3 vNormal = tri.vertices[0].normal * barycentrics.x +
                   tri.vertices[1].normal * barycentrics.y +
                   tri.vertices[2].normal * barycentrics.z;

    vec4 vTangent = tri.vertices[0].tangent * barycentrics.x +
                    tri.vertices[1].tangent * barycentrics.y +
                    tri.vertices[2].tangent * barycentrics.z;

    // 2. 将法线贴图采样值从 [0, 1] 映射到 [-1, 1]
    vec3 tangentNormal = localNormalSample * 2.0 - 1.0;

    // 3. 构建 TBN 矩阵 (Object Space)
    // 重新正交化切线 (Gram-Schmidt process)
    vec3 N = normalize(vNormal);
    vec3 T = normalize(vTangent.xyz - dot(vTangent.xyz, N) * N);
    // 根据顶点切线的 w 分量决定副切线方向（处理 UV 镜像）
    vec3 B = cross(N, T) * vTangent.w;

    mat3 TBN = mat3(T, B, N);

    // 4. 将法线转到物体空间
    vec3 objectNormal = normalize(TBN * tangentNormal);

    // 5. 变换到世界空间
    // 使用 gl_WorldToObjectEXT 的转置来处理法线变换，以应对非统一缩放
    // 变换公式：NormalWorld = NormalObject * ModelInverse
    vec3 worldNormal = normalize(objectNormal * mat3(gl_WorldToObjectEXT)); // m^(-1)^T

    return worldNormal;
}

void main()
{
    Triangle tri = unpackTriangle(gl_PrimitiveID);
    GeometryNode geometryNode = geometryNodes.nodes[gl_GeometryIndexEXT];

    vec2 sampleUV = getSampleUV(tri);
    vec3 color = texture(textures[nonuniformEXT(geometryNode.textureIndexBaseColor)], sampleUV).rgb;

    hitValue.baseColor.rgb = color;
    hitValue.worldPos = calcWorldPosByInterpolation(tri);

    if (geometryNode.textureIndexNormal > -1) {
        hitValue.worldNormal = calcWorldNormalBySampling(tri, sampleUV);
    }else{
        hitValue.worldNormal = calcWorldNormalByInterpolation(tri);
    }
    hitValue.dis = gl_HitTEXT;

    //traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT, 0xff, 0, 0, 0, hitValue.worldPos, 0.001, -directionalLight.direction, 10000, 0);
    
}
