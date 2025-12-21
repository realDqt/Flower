#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require

#include "spcommon.glsl"
layout(location = 0) rayPayloadInEXT RayPayload hitValue;

void main()
{
    hitValue.dis = -1.0f;
}