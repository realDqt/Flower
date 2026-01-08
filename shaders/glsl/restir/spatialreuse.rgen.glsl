#version 460
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_shader_image_load_formatted : enable
#include "spcommon.glsl"
#include "restircommon.glsl"

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;

layout(binding = 1, set = 0) buffer TemporalReservoirBufferOut{
    Reservoir data[];
} temporalReservoirBufferOut;

layout(binding = 2, set = 0) buffer SpatialReservoirBufferIn{
    Reservoir data[];
} spatialReservoirBufferIn;

layout(binding = 3, set = 0) buffer SpatialReservoirBufferOut{
    Reservoir data[];
} spatialReservoirBufferOut;

layout(binding = 4, set = 0) uniform image2D curDepthImage;
layout(binding = 5, set = 0) uniform image2D curNormalImage;

layout(binding = 6, set = 0) uniform FrameData{
    mat4 currentInvViewProj;    // 当前帧矩阵信息
    mat4 prevViewProj;          // 上一帧矩阵信息
    uint frame;
} frameData;

layout(binding = 7, set = 0) uniform image2D image;
layout(binding = 8, set = 0) uniform image2D curWorldPositionImage;
layout(binding = 9, set = 0) uniform image2D curAlbedoImage;

layout(binding = 10, set = 0) buffer DirectionalLight{
    vec3 direction; // 平行光方向 (从光源指向场景)
    vec3 emission;  // 强度/颜色
} directionalLight;

layout(location = 0) rayPayloadEXT RayPayload hitValue;

vec3 getWorldPos(vec2 uv, float depth) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth, 1.0);
    vec4 worldPos = frameData.currentInvViewProj * ndc;
    return worldPos.xyz / worldPos.w;
}

uint getSeed()
{
    return tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, frameData.frame);
}

bool isGeometricSimilar(ivec2 pixel_q, ivec2 pixel_r)
{
    float depth_q = imageLoad(curDepthImage, pixel_q).r;
    vec3 norm_q = imageLoad(curNormalImage, pixel_q).xyz;

    float depth_r = imageLoad(curDepthImage, pixel_r).r;
    vec3 norm_r = imageLoad(curNormalImage, pixel_r).xyz;
    
    if(abs(depth_q - depth_r) > 0.05f) return false;
    if(dot(norm_q, norm_r) < 0.906307787f) return false;
    return true;
}

uvec2 randomlyChooseNeighbor(uvec2 center, inout uint seed)
{
    float r = sqrt(rnd(seed)) * SPATIAL_RADIUS;
    float theta = rnd(seed) * 2.0 * 3.14159265359;
    vec2 offset = vec2(cos(theta), sin(theta)) * r;

    ivec2 neighbor = ivec2(center) + ivec2(offset);
    neighbor = clamp(neighbor, ivec2(0), ivec2(WIDTH - 1, HEIGHT - 1));
    return uvec2(neighbor);
}

float calcJacobian(vec3 pos_r, vec3 pos_n, vec3 pos_s, vec3 norm_s)
{
    vec3 pos_s2pos_r = pos_r - pos_s;
    float cosPhi_r = dot(normalize(pos_s2pos_r), norm_s);
    
    vec3 pos_s2pos_n = pos_n - pos_s;
    float cosPhi_n = dot(normalize(pos_s2pos_n), norm_s);
    
    float jacobian = abs(cosPhi_r) / abs(cosPhi_n) * dot(pos_s2pos_n, pos_s2pos_n) / dot(pos_s2pos_r, pos_s2pos_r);
    return jacobian;
}

bool isVisibleAB(vec3 pos_a, vec3 pos_b)
{
    Ray ray;
    ray.origin = pos_a;
    ray.direction = normalize(pos_b - pos_a);
    ray.tmin = 0.001f;
    ray.tmax = 10000.0f;
    uint rayFlags = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsSkipClosestHitShaderEXT | gl_RayFlagsOpaqueEXT;
    hitValue.dis = 1.0f;
    traceRayEXT(topLevelAS, rayFlags, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);
    return hitValue.dis > 0.0f;
}
vec3 calcIndirectLighting(Reservoir r)
{
    uvec2 pixel_q = gl_LaunchIDEXT.xy;
    vec4 pos_q = imageLoad(curWorldPositionImage, ivec2(pixel_q));
    if(pos_q.w < 0.0f) return vec3(0.0f);
    if(dot(pos_q.xyz - r.z.x_s.xyz, r.z.n_s.xyz) < 0.0f) return vec3(0.0f);
    vec3 norm_q = imageLoad(curNormalImage, ivec2(pixel_q)).xyz;
    vec4 albedo = imageLoad(curAlbedoImage, ivec2(pixel_q));
    
    vec3 Li = r.z.Lo.rgb * r.W;
    vec3 fr = albedo.rgb / M_PI;
    float cosTheta = max(dot(normalize(r.z.x_s.xyz - pos_q.xyz), norm_q), 0.0f);
    return Li * fr * cosTheta;
}

vec3 calcDirectLighting()
{
    uvec2 pixel_q = gl_LaunchIDEXT.xy;
    vec4 pos_q = imageLoad(curWorldPositionImage, ivec2(pixel_q));
    if(pos_q.w < 0.0f) return vec3(0.0f);
    
    vec3 norm_q = decodeNormal(imageLoad(curNormalImage, ivec2(pixel_q)).xyz);
    vec4 albedo = imageLoad(curAlbedoImage, ivec2(pixel_q));
    
    vec3 L_dir = vec3(0.0);
    vec3 wi = normalize(-directionalLight.direction.xyz); // 指向光源的方向

    uint rayFlags = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsSkipClosestHitShaderEXT | gl_RayFlagsOpaqueEXT;
    hitValue.dis = 1.0f;
    // 逻辑：向着平行光方向追踪 10000 距离，看是否有遮挡
    traceRayEXT(topLevelAS, rayFlags, 0xff, 0, 0, 0, pos_q.xyz, 0.001, wi, 10000.0, 0);

    // hitValue.dis < 0 表示未击中任何物体（路径畅通）
    if(hitValue.dis < 0.0f) {
        vec3 brdf = albedo.rgb / M_PI; 
        L_dir = directionalLight.emission.xyz * brdf * max(dot(wi, norm_q), 0.0f);
    }
    return L_dir;
}

void main() {
    //return;
    uvec2 pixel_q = gl_LaunchIDEXT.xy;
    if(pixel_q.x >= WIDTH || pixel_q.y >= HEIGHT) return;
    
    uint idx_q = getCoord1D(pixel_q);
    uint seed = getSeed();

    vec2 uv_q = (vec2(pixel_q) + 0.5) / vec2(WIDTH, HEIGHT);
    float depth_q = imageLoad(curDepthImage, ivec2(pixel_q)).r;
    vec3 norm_q = decodeNormal(imageLoad(curNormalImage, ivec2(pixel_q)).xyz);
    vec3 pos_q = getWorldPos(uv_q, depth_q);
    
    Reservoir R_s = temporalReservoirBufferOut.data[idx_q];

    float p_hat_s = pq_hat(pos_q, norm_q, R_s.z);
    if (!isVisibleAB(pos_q, R_s.z.x_s.xyz)) p_hat_s = 0.0;

    struct NeighborInfo {
        vec3 pos_qn;
        vec3 norm_qn;
        uint M;
    } neighbors[MAX_ITERATIONS + 1];

    int neighborCount = 0;
    neighbors[neighborCount++] = NeighborInfo(pos_q, norm_q, R_s.M);
    
    for(int i = 0; i < MAX_ITERATIONS; ++i){
        uvec2 pixel_qn = randomlyChooseNeighbor(pixel_q, seed);
        if(!isGeometricSimilar(ivec2(pixel_q), ivec2(pixel_qn)))
            continue;
        uint idx_qn = getCoord1D(pixel_qn);
        Reservoir R_n = temporalReservoirBufferOut.data[idx_qn];
        
        vec2 uv_qn = (vec2(pixel_qn) + 0.5) / vec2(WIDTH, HEIGHT);
        float depth_qn = imageLoad(curDepthImage, ivec2(pixel_qn)).r;
        vec3 norm_qn = decodeNormal(imageLoad(curNormalImage, ivec2(pixel_qn)).xyz);
        vec3 pos_qn = getWorldPos(uv_qn, depth_qn);
        float jacobian = calcJacobian(pos_q, pos_qn, R_n.z.x_s.xyz, R_n.z.n_s.xyz);
        jacobian = clamp(jacobian, 0.1, 10.0);
        
        float pq_hat_prime = pq_hat(pos_q, norm_q, R_n.z) / jacobian;
        if (!isVisibleAB(pos_q, R_n.z.x_s.xyz)) {
            pq_hat_prime = 0.0;
        }

        mergeReservoir(R_s, R_n, pq_hat_prime, seed);
        neighbors[neighborCount++] = NeighborInfo(pos_qn, norm_qn, R_n.M);
    }
    
    uint Z = 0;
    float pq_hat_final = pq_hat(pos_q, norm_q, R_s.z);
    if(pq_hat_final > 0.0 && isVisibleAB(pos_q, R_s.z.x_s.xyz)){
        for(int i = 0; i < neighborCount; ++i){
            float pq_hat_neighbor = pq_hat(neighbors[i].pos_qn, neighbors[i].norm_qn, R_s.z);
            if(pq_hat_neighbor > 0){
                if(isVisibleAB(neighbors[i].pos_qn, R_s.z.x_s.xyz)) {
                    Z = Z + neighbors[i].M;
                }
            }
        }
        R_s.W = R_s.w / (float(Z) * pq_hat(pos_q, norm_q, R_s.z));
    }else{
        R_s.W = 0.0;
    }
    
    spatialReservoirBufferOut.data[idx_q] = R_s;
    vec3 directLighting = calcDirectLighting();
    vec3 indirectLighting = calcIndirectLighting(R_s);
    if(any(isnan(directLighting)) || any(isinf(directLighting))) directLighting = vec3(0.0);
    if(any(isnan(indirectLighting)) || any(isinf(indirectLighting))) indirectLighting = vec3(0.0);
    imageStore(image, ivec2(pixel_q), vec4(directLighting + indirectLighting, 1.0f));
}