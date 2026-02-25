set "GLSLANG_VALIDATOR=E:/Vulkan/Bin/glslangValidator.exe"
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 SceneShading.rchit.glsl -o SceneShading.rchit.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 Miss.rmiss.glsl -o Miss.rmiss.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 Shadow.rmiss.glsl -o Shadow.rmiss.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 SceneShading.rgen.glsl -o SceneShading.rgen.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 ProbeTrace.rchit.glsl -o ProbeTrace.rchit.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 ProbeTrace.rgen.glsl -o ProbeTrace.rgen.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 ProbeBlendIrradiance.comp.glsl -o ProbeBlendIrradiance.comp.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 ProbeBlendDistance.comp.glsl -o ProbeBlendDistance.comp.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 ProbeRelocation.comp.glsl -o ProbeRelocation.comp.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 ProbeClassification.comp.glsl -o ProbeClassification.comp.spv
pause