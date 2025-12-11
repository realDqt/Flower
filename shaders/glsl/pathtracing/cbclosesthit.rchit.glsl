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

void main()
{
    Triangle tri = unpackTriangle(gl_PrimitiveID);
    
    vec3 color = getBaseColor().rgb + getEmission();
    
    hitValue.mat = getMat();
    vec3 worldNormal = normalize(tri.normal * mat3(gl_WorldToObjectEXT)); // m^(-1)^T
    hitValue.worldNormal = worldNormal;
    hitValue.worldPos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;
    hitValue.dis = gl_HitTEXT;
}
