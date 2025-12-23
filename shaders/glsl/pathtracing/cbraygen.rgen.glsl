#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_shader_image_load_formatted : enable

#include "cbcommon.glsl"
layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;
layout(binding = 1, set = 0) uniform image2D image;
layout(binding = 2, set = 0) uniform CameraProperties{
    mat4 viewInverse;
    mat4 projInverse;
    uint frame;
} cam;

layout(binding = 3, set = 0) buffer GeometryNodes {GeometryNode nodes[];}geometryNodes;

layout(binding = 4, set = 0) buffer Materials {Material mats[];} materials;

layout(binding = 5, set = 0) buffer LightData{
    mat4 objectToWorld;
    int lightGeometryIndex;
} lightData;

layout(location = 0) rayPayloadEXT RayPayload hitValue;

struct LightSampleRes{
    vec3 pos;
    vec3 normal;
    vec3 emit;
};


void uniformSampleLight(vec3 tri0WorldPositions[3], vec3 tri1WorldPositions[3], inout uint seed, out LightSampleRes sampleRes, out float pdf)
{
    float area0 = cacTriangleArea(tri0WorldPositions);
    float area1 = cacTriangleArea(tri1WorldPositions);
    
    float p = rnd(seed);
    float ratio = area0 / (area0 + area1);
    if(p <= ratio){
        sampleRes.pos = uniformSampleTriangle(tri0WorldPositions, seed);
        sampleRes.normal = getTriNormalFromTriPositions(tri0WorldPositions);
    }else{
        sampleRes.pos = uniformSampleTriangle(tri1WorldPositions, seed);
        sampleRes.normal = getTriNormalFromTriPositions(tri1WorldPositions);
    }
    Material lightMat = materials.mats[lightData.lightGeometryIndex];
    sampleRes.emit = lightMat.emission;
    
    pdf = 1.0f / (area0 + area1);
}

void unpackLightWorldPositions(out vec3 tri0WorldPositions[3], out vec3 tri1WorldPositions[3])
{
    GeometryNode node = geometryNodes.nodes[lightData.lightGeometryIndex];
    
    Vertices vertices = Vertices(node.vertexBufferDeviceAddress);
    Indices indices = Indices(node.indexBufferDeviceAddress);
    
    for(int k = 0; k < 3; ++k){
        tri0WorldPositions[k] = vec3(lightData.objectToWorld * vec4(vertices.v[indices.i[k]].pos, 1.0));
        tri1WorldPositions[k] = vec3(lightData.objectToWorld * vec4(vertices.v[indices.i[k + 3]].pos, 1.0));
    }
}

void sampleLight(inout uint seed, out LightSampleRes sampleRes, out float pdf)
{
    vec3 tri0Positions[3];
    vec3 tri1Positions[3];
    unpackLightWorldPositions(tri0Positions, tri1Positions);
    uniformSampleLight(tri0Positions, tri1Positions, seed, sampleRes, pdf);
}

// 幂启发式 (Power Heuristic): w1 = p1^2 / (p1^2 + p2^2)
float powerHeuristic(float a, float b)
{
    float a2 = a * a;
    float b2 = b * b;
    return a2 / (max(a2 + b2, 1e-6f)); // 防止除零
}

// 获取光源的总面积 (用于反推 PDF)
float getLightArea()
{
    vec3 t0[3];
    vec3 t1[3];
    unpackLightWorldPositions(t0, t1);
    return cacTriangleArea(t0) + cacTriangleArea(t1);
}

uint getSeed()
{
    uint seed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, cam.frame);
    return seed;
}

Ray getRayFromCamera(float tmin, float tmax, inout uint seed)
{

    float r1 = rnd(seed);
    float r2 = rnd(seed);

    vec2 subpixel_jitter = cam.frame == 0 ? vec2(0.5f, 0.5f) : vec2(r1, r2);
    const vec2 pixelCenter = vec2(gl_LaunchIDEXT.xy) + subpixel_jitter;
    const vec2 inUV = pixelCenter / vec2(gl_LaunchSizeEXT.xy);
    vec2 d = inUV * 2.0 - 1.0;
    
    vec4 origin = cam.viewInverse * vec4(0, 0, 0, 1);
    vec4 target = cam.projInverse * vec4(d.x, d.y, 1, 1);
    vec4 direction = cam.viewInverse * vec4(normalize(target.xyz), 0.0);
    
    Ray ray;
    ray.origin = origin.xyz;
    ray.direction = direction.xyz;
    ray.tmin = tmin;
    ray.tmax = tmax;
    return ray;
}

vec3 cacDirectLight(vec3 pos, vec3 normal, vec3 wo, inout uint seed, Material mat)
{
    if (isSpecularMat(hitValue.mat)) return vec3(0.0);
    
    // 计算pos处，沿着wo方向的直接光照
    vec3 L_dir = vec3(0.0);
    float pdfLightArea = 0;
    LightSampleRes lightSampleRes;
    sampleLight(seed, lightSampleRes, pdfLightArea);
    vec3 p = pos;
    vec3 x = lightSampleRes.pos;
    vec3 ws = normalize(x - p);
    float lightDist = length(x - p);
    
    uint rayFlags = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsSkipClosestHitShaderEXT;
    traceRayEXT(topLevelAS, rayFlags, 0xff, 0, 0, 0, p, 0.001, ws, lightDist - 0.0001f, 0);
    if(hitValue.dis < 0.0f){
        // p对光源x可见
        vec3 f_r = evalDiffuseBRDF(ws, wo, normal, mat);
        float distance2 = dot(x - p, x - p);
        float cosThetaLight = max(0.0, dot(-ws, lightSampleRes.normal));
        float cosThetaObj = max(0.0, dot(ws, normal));

        // MIS 权重计算
        // 将光源 Area PDF 转换为 Solid Angle PDF
        float pdfLightSA = pdfLightArea * distance2 / max(cosThetaLight, 1e-6f);
        // 计算 BSDF 采样这个方向的 PDF (Diffuse = cosTheta / PI)
        float pdfBSDFSA = cosThetaObj / M_PI;
        // 计算权重
        float weight = powerHeuristic(pdfLightSA, pdfBSDFSA);
        
        L_dir = lightSampleRes.emit * f_r * cosThetaObj * cosThetaLight / distance2 / pdfLightArea * weight;
    }
    return L_dir;
}

vec3 pathTracing(int maxBounce, inout uint seed)
{
    Ray ray = getRayFromCamera(0.001, 10000.0, seed);
    uint rayFlags = gl_RayFlagsOpaqueEXT;
    vec3 totalRadiance = vec3(0.0);
    vec3 throughput = vec3(1.0);

    // MIS 需要记录上一次 BSDF采样的 PDF 和 类型
    float lastPdfBSDF = 0.0;
    bool lastBounceWasSpecular = true; // 第一帧(摄像机射线)视为绝对准确，相当于 Specular，避免误杀
    
    for(int i = 0; i < maxBounce; ++i){
        traceRayEXT(topLevelAS, rayFlags, 0xff, 0, 0, 0, ray.origin, ray.tmin, ray.direction, ray.tmax, 0);
        if(hitValue.dis > 0.0f) {
            if(hasEmission(hitValue.mat)){
                float misWeight = 1.0;
                // 如果是镜面，说明 NEE 无法采样到这里，必须全盘接受 BSDF 结果，权重为 1
                // 如果上一次不是镜面反射且不是第一条摄像机射线 (i > 0) 
                if(!lastBounceWasSpecular && i > 0) {
                    // 反推 NEE 采样该点的概率 (PDF Solid Angle)
                    float dist2 = dot(hitValue.worldPos - ray.origin, hitValue.worldPos - ray.origin);
                    float cosThetaLight = max(0.0, dot(hitValue.worldNormal, -ray.direction));
                    float lightArea = getLightArea(); 
                    float pdfLightArea = 1.0 / lightArea;
                    float pdfLightSA = pdfLightArea * dist2 / max(cosThetaLight, 1e-6f);

                    // 计算 MIS 权重: BSDF / (BSDF + Light)
                    misWeight = powerHeuristic(lastPdfBSDF, pdfLightSA);
                }
                
                totalRadiance += hitValue.mat.emission * throughput * misWeight;
                break;
            }
            vec3 radiance = cacDirectLight(hitValue.worldPos, hitValue.worldNormal, -ray.direction, seed, hitValue.mat);
            
            totalRadiance += radiance * throughput;
            
            ray.origin = hitValue.worldPos;
            // sampling
            float pdf;
            vec3 sampleDir;
            bool isSpecular = false;
            if(isSpecularMat(hitValue.mat)){
                sampleSpecular(hitValue.worldNormal, ray.direction, sampleDir, pdf);
                isSpecular = true;
            }else{
                cosineSampleHemisphere(hitValue.worldNormal, seed, sampleDir, pdf);
                isSpecular = false;
            }
            
            vec3 f_r = evalDiffuseBRDF(sampleDir, -ray.direction, hitValue.worldNormal, hitValue.mat);
            if (isSpecular) {
                // Specular 处理:
                // 简单起见假设 specular 完美反射：
                throughput *= hitValue.mat.baseColor.rgb / RUSSIAN_ROULETTE / pdf;
            } else {
                throughput *= f_r * dot(sampleDir, hitValue.worldNormal) / RUSSIAN_ROULETTE / pdf;
            }
            
            // 更新状态供下一次迭代使用
            lastPdfBSDF = pdf;
            lastBounceWasSpecular = isSpecular;
            ray.direction = sampleDir;
        }else{
            break;
        }
        
        float x = rnd(seed);
        if(x > RUSSIAN_ROULETTE) break;
    }
    return totalRadiance;
}

void temporalAccumulation(vec3 finalColor)
{
    if(cam.frame > 0)
    {
        float a         = 1.0f / float(cam.frame + 1);
        vec3  old_color = imageLoad(image, ivec2(gl_LaunchIDEXT.xy)).xyz;
        imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(mix(old_color, finalColor, a), 1.f));
    }
    else
    {
        // First frame, replace the value in the buffer
        imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(finalColor, 1.f));
    }
}

void main()
{
    uint seed = getSeed();

    vec3 accumulatedColor = vec3(0.0);
    const int SPP = 1;
    const int BOUNCE = 128;

    for(int i = 0; i < SPP; ++i)
    {
        accumulatedColor += pathTracing(BOUNCE, seed);
    }
    
    vec3 finalColor = accumulatedColor / float(SPP);
    
    imageStore(image, ivec2(gl_LaunchIDEXT.xy), vec4(finalColor, 1.0f));
}