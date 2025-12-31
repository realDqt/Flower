#define GLM_FORCE_RADIANS
#define GLM_FORCE_DEPTH_ZERO_TO_ONE
#define GLM_ENABLE_EXPERIMENTAL
#include <glm/glm.hpp>

// 强制所有 vec3 升级为 vec4，确保 100% 内存安全
struct Sample
{
    // xyzw: w 分量可以留作 padding，或者存别的（比如材质ID）
    glm::vec4 x_v;       // Offset 0
    glm::vec4 n_v;       // Offset 16
    glm::vec4 x_s;       // Offset 32
    glm::vec4 n_s;       // Offset 48
    
    // 把 Lo 和 Random 压缩到一个 vec4 里？
    // 或者保持原样但用 vec4 占位
    glm::vec4 Lo;        // Offset 64 (w分量闲置，或者存Random?)
    
    uint32_t Random;     // Offset 80 (紧跟在 Lo 的 16字节之后)
    uint32_t _pad[3];    // Offset 84-96 (手动填充到 16 字节对齐)
};

// 确保 C++ 编译器对 Sample 的理解也是 16 字节对齐
static_assert(sizeof(Sample) % 16 == 0, "Sample size alignment error");

struct Reservoir
{
    Sample z;            // Offset 0, Size 96
    float w = 0.0f;             // Offset 96
    uint32_t M = 0;          // Offset 100
    float W = 0.0f;             // Offset 104
    uint32_t _pad;       // Offset 108-112 (手动填充，凑整结构体)
};