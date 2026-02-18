#version 460

#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require

#include "Utils.glsl"
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
		const uint offset = indices.i[triIndex + i];
		tri.vertices[i] = vertices.v[offset];
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
	hitValue.dis = gl_HitTEXT;

	vec3 worldNormal = normalize(tri.normal * mat3(gl_WorldToObjectEXT)); // m^(-1)^T

	if (gl_HitKindEXT == gl_HitKindBackFacingTriangleEXT) {
		worldNormal = -worldNormal;
	}
	hitValue.worldNormal = worldNormal;
	hitValue.worldPos = cacWorldPosByInterpolation(tri);
	hitValue.hitKind = gl_HitKindEXT;
}
