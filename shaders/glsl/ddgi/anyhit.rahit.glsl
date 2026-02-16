/* Copyright (c) 2023, Sascha Willems
 *
 * SPDX-License-Identifier: MIT
 *
 */
#version 460

#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference2 : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#include "common.glsl"

layout(location = 3) rayPayloadInEXT uint payloadSeed;

hitAttributeEXT vec2 attribs;

layout(binding = 3, set = 0) uniform sampler2D image;

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



void main()
{
	Triangle tri = unpackTriangle(gl_PrimitiveID);
	GeometryNode geometryNode = geometryNodes.nodes[gl_GeometryIndexEXT];

	vec2 uv = tri.vertices[0].uv * (1.0f - attribs.x - attribs.y) + tri.vertices[1].uv * attribs.x + tri.vertices[2].uv * attribs.y;
	vec4 color = texture(textures[nonuniformEXT(geometryNode.textureIndexBaseColor)], uv);
	// If the alpha value of the texture at the current UV coordinates is below a given threshold, we'll ignore this intersection
	// That way ray traversal will be stopped and the miss shader will be invoked
	if (color.a < 0.9) {
		ignoreIntersectionEXT;
	}
}