set "GLSLANG_VALIDATOR=E:/Vulkan/Bin/glslangValidator.exe"
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 spraygen.rgen.glsl -o spraygen.rgen.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 spmiss.rmiss.glsl -o spmiss.rmiss.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 spclosesthit.rchit.glsl -o spclosesthit.rchit.spv
pause