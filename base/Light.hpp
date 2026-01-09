#ifndef LIGHT_HPP
#define LIGHT_HPP
#define GLM_FORCE_RADIANS
#define GLM_FORCE_DEPTH_ZERO_TO_ONE
#define GLM_ENABLE_EXPERIMENTAL
#include <glm/glm.hpp>

struct DirectionalLight
{
    glm::vec4 direction;
    glm::vec4 emission;
};
#endif
