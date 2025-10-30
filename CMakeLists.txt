# 1. 指定 CMake 最低版本要求
cmake_minimum_required(VERSION 3.15)

set(target_name Flower)

# 2. 声明项目名称、版本和语言
#    (注意：我去掉了你之前 project() 命令中多余的 "t")
project(${target_name} VERSION 1.0 LANGUAGES CXX)

# 3. 设置 C++ 标准 
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED True)

# 4. 查找源文件 (递归版本)
file(GLOB_RECURSE SOURCES 
    "src/*.cpp"
)
file(GLOB_RECURSE INCLUDES 
    "include/*.h" 
)

# 5. [FIX 1] 创建可执行文件目标
#    这一步必须在 target_link_libraries 之前！
add_executable(${target_name} 
    ${SOURCES}
    ${INCLUDES}
)

# 6. [FIX 2] 使用 target_include_directories (新方式)
#    替换所有旧的 include_directories()
#    这更安全，因为它只应用到 "Flower" 目标
target_include_directories(${target_name} PRIVATE
    external
    external/glm
    external/gli
    external/imgui
    external/tinygltf
    external/ktx/include
    external/ktx/other_include
    base
)

# 7. 查找并链接 Vulkan
find_package(Vulkan REQUIRED)
set(Vulkan_LIBRARY Vulkan::Vulkan)
#    [FIX 3] target_link_libraries 移到了 add_executable 之后
#    [FIX 4] 对于可执行文件，链接库应该使用 PRIVATE 而不是 PUBLIC
target_link_libraries(${target_name} PRIVATE
    ${Vulkan_LIBRARY}
)

# 8. 添加子目录
add_subdirectory(base)