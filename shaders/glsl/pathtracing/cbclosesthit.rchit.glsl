#version 460

#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require

#include "cbcommon.glsl"
layout(location = 0) rayPayloadInEXT RayPayload hitValue;
hitAttributeEXT vec2 attribs;

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;

layout(binding = 3, set = 0) buffer GeometryNodes {GeometryNode nodes[];}geometryNodes;


layout(binding = 4, set = 0) buffer Materials {Material mats[];} materials;

bool neadToReverseNormal()
{
    return gl_GeometryIndexEXT == 0 || gl_GeometryIndexEXT == 4 || gl_GeometryIndexEXT == 5;
}

Triangle unpackTriangle(uint index){
    Triangle tri;
    const uint triIndex = index * 3;

    GeometryNode geometryNode = geometryNodes.nodes[gl_GeometryIndexEXT];

    Indices indices = Indices(geometryNode.indexBufferDeviceAddress);
    Vertices vertices = Vertices(geometryNode.vertexBufferDeviceAddress);

    for(uint i = 0; i < 3; i++){
        const uint offset = indices.i[triIndex + i] * 3;
        vec4 d0 = vertices.v[offset + 0];
        tri.vertices[i].pos = d0.xyz;
    }

    vec3 barycentricCoords = vec3(1.0f - attribs.x - attribs.y, attribs.x, attribs.y);
    tri.normal = normalize(cross(tri.vertices[1].pos - tri.vertices[0].pos, tri.vertices[2].pos - tri.vertices[1].pos));
    if(neadToReverseNormal())tri.normal = -tri.normal; // hack
    return tri;
}

Material getMat()
{
    return materials.mats[gl_GeometryIndexEXT];
}

vec4 getBaseColor()
{
    return getMat().baseColor;
}

vec3 getEmission()
{
    return getMat().emission;
}

vec3 cacWorldPosByInterpolation(Triangle tri)
{
    const vec3 barycentrics = vec3(1.0f - attribs.x - attribs.y, attribs.x, attribs.y);
    vec3 p0 = tri.vertices[0].pos;
    vec3 p1 = tri.vertices[1].pos;
    vec3 p2 = tri.vertices[2].pos;
    vec3 localPos = p0 * barycentrics.x + p1 * barycentrics.y + p2 * barycentrics.z;
    return vec3(gl_ObjectToWorldEXT * vec4(localPos, 1.0));
}

vec3 cacWorldPosByRayHitInfo()
{
    return gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;
}

void main()
{
    Triangle tri = unpackTriangle(gl_PrimitiveID);
    
    hitValue.mat = getMat();
    vec3 worldNormal = normalize(tri.normal * mat3(gl_WorldToObjectEXT)); // m^(-1)^T
    hitValue.worldNormal = worldNormal;
    //hitValue.worldPos = cacWorldPosByRayHitInfo(); // 正常
    hitValue.worldPos = cacWorldPosByInterpolation(tri); // 除了光源，全黑bug
    hitValue.dis = gl_HitTEXT;
}
