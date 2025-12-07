struct Material{
    vec4 baseColor;
    vec3 emission;
    float metallic;
    float roughness;
};
struct RayPayload{
    vec3 normal;
    vec3 pos;
    Material mat;
    float dis;
};

vec3 getNormal01(vec3 v)
{
    v = (v + vec3(1.0)) * vec3(0.5);
    return v;
}