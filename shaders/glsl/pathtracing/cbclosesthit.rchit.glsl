#version 460

#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#include "cbcommon.glsl"
layout(location = 0) rayPayloadInEXT RayPayload hitValue;
hitAttributeEXT vec2 attribs;

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;


struct GeometryNode{
    uint64_t vertexBufferDeviceAddress;
    uint64_t indexBufferDeviceAddress;
};
layout(binding = 3, set = 0) buffer GeometryNodes {GeometryNode nodes[];}geometryNodes;


layout(binding = 4, set = 0) buffer Materials {Material mats[];} materials;

layout(buffer_reference, scalar) buffer Vertices {vec4 v[]; };
layout(buffer_reference, scalar) buffer Indices {uint i[]; };

struct Vertex{
    vec3 pos;
};

struct Triangle{
    Vertex vertices[3];
    vec3 normal;
};

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
    tri.normal = normalize(cross(tri.vertices[1].pos - tri.vertices[0].pos, tri.vertices[2].pos - tri.vertices[0].pos));
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
    
    GeometryNode geometryNode = geometryNodes.nodes[gl_GeometryIndexEXT];
    
    vec3 color = getBaseColor().rgb + getEmission();
    
    hitValue.mat = getMat();
    vec3 worldNormal = normalize(tri.normal * mat3(gl_WorldToObjectEXT)); // m^(-1)^T
    hitValue.normal = worldNormal;
    hitValue.pos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;
    hitValue.dis = gl_HitTEXT;
}
