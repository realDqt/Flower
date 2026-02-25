set "GLSLANG_VALIDATOR=E:/Vulkan/Bin/glslangValidator.exe"
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 cbraygen.rgen.glsl -o cbraygen.rgen.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 cbmiss.rmiss.glsl -o cbmiss.rmiss.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 cbclosesthit.rchit.glsl -o cbclosesthit.rchit.spv
pause