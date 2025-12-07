#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : enable
#extension GL_ARB_shading_language_include : enable

#include "cbcommon.glsl"
layout(location = 0) rayPayloadInEXT RayPayload hitValue;

void main()
{
    hitValue.mat.baseColor = vec4(0.0, 0.0, 0.0, 1.0);
}