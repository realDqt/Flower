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
// 必须开启此扩展，因为 common.glsl 中使用了 uint64_t
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#include "common.glsl"

layout(location = 0) rayPayloadInEXT vec3 hitValue;
layout(location = 2) rayPayloadEXT bool shadowed;
hitAttributeEXT vec2 attribs;

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;
layout(binding = 3, set = 0) uniform sampler2D image;

layout(binding = 4, set = 0) buffer GeometryNodes { GeometryNode nodes[]; } geometryNodes;

layout(binding = 5, set = 0) uniform sampler2D textures[];

// 辅助函数：解包三角形数据
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

	// 计算模型空间 (Object Space) 下的几何法线
	tri.normal = normalize(cross(tri.vertices[1].pos - tri.vertices[0].pos, tri.vertices[2].pos - tri.vertices[1].pos));
	return tri;
}

void main()
{
	Triangle tri = unpackTriangle(gl_PrimitiveID);

	GeometryNode geometryNode = geometryNodes.nodes[gl_GeometryIndexEXT];

	// 1. 计算 UV 和获取基础颜色
	vec2 uv = tri.vertices[0].uv * (1.0f - attribs.x - attribs.y) +
	tri.vertices[1].uv * attribs.x +
	tri.vertices[2].uv * attribs.y;

	vec3 color = texture(textures[nonuniformEXT(geometryNode.textureIndexBaseColor)], uv).rgb;

	// -------------------------------------------------------------------------
	// 修复逻辑开始
	// -------------------------------------------------------------------------

	// 2. 【关键修复】计算世界空间法线 (World Space Normal)
	vec3 worldNormal =  normalize(vec3(tri.normal * gl_WorldToObjectEXT));

	// 3. 定义指向光源的方向向量 L
	// 原代码 lightDir = (0.01, -1.0, 1.0) 是光线射出的方向
	// 我们需要指向光源的方向，所以取反：(-0.01, 1.0, -1.0)
	vec3 lightVec = normalize(vec3(-0.01, 1.0, -1.0));

	// 4. 【关键修复】计算 Lambertian (N dot L)
	// 这一步决定了表面是“受光”还是“背光”
	float NdotL = max(0.0, dot(worldNormal, lightVec));

	hitValue = encodeNormal(worldNormal);
	/*
	// 默认将结果设为黑色（阴影中）
	hitValue = vec3(0.0);

	// 5. 只有当表面面向光源时，才进行阴影判断和光照计算
	if (NdotL > 0.0)
	{
		shadowed = true;

		// 6. 【优化】阴影偏移 (Shadow Bias)
		// 起点沿着法线向外偏移一点点，防止浮点数精度导致的“自遮挡”噪点
		float tmin = 0.001;
		float tmax = 10000.0;
		vec3 origin = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;
		vec3 shadowOrigin = origin + worldNormal * 0.001;

		// 7. 发射阴影射线
		// flags 增加了 gl_RayFlagsTerminateOnFirstHitEXT，只要碰到任何遮挡物就立即停止，提高性能
		traceRayEXT(topLevelAS,
					gl_RayFlagsSkipClosestHitShaderEXT | gl_RayFlagsTerminateOnFirstHitEXT,
					0xFF, 0, 0, 1,
					shadowOrigin, tmin, lightVec, tmax, 2);

		if (!shadowed) {
			// 8. 【关键修复】应用 Lambertian 光照
			// 最终颜色 = 材质本色 * (N dot L)
			// 这样侧面对着光的墙会比正对着光的暗一些，增加立体感
			hitValue = color;
		}
	}
	// 如果 NdotL <= 0，hitValue 保持为 0.0，正确表现为黑色背光面
	*/
}