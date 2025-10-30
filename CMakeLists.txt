# 1. 指定 CMake 最低版本要求
cmake_minimum_required(VERSION 3.15)

# 2. 声明项目名称、版本和语言
project(MyProject VERSION 1.0 LANGUAGES CXX)

# 3. 设置 C++ 标准 
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED True)

# 4. 添加可执行文件目标
# 它由 src/main.cpp 编译而来
add_executable(Flower src/main.cpp)

# (可选) 5. 如果你的源文件很多，可以用这个命令自动查找
# file(GLOB SOURCES "src/*.cpp")
# add_executable(Flowers ${SOURCES})
# (注意：GLOB 方式通常不被推荐用于大型项目，但对于小项目很方便)