set "GLSLANG_VALIDATOR=E:/Vulkan/Bin/glslangValidator.exe"
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 raygen.rgen.glsl -o raygen.rgen.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 closesthit.rchit.glsl -o closesthit.rchit.spv
pause