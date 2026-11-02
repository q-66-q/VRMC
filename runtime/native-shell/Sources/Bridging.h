#ifndef VRMCShell_Bridging_h
#define VRMCShell_Bridging_h
#include <CompositorServices/CompositorServices.h>
#ifdef __cplusplus
extern "C" {
#endif
void VRMCCompositor_InitAndRun(cp_layer_renderer_t layerRenderer);
void VRMCCompositor_RequestStop(void);
void VRMCCompositor_NotifyGameStopping(void);
int32_t VRMCCompositor_CurrentGeneration(void);
#ifdef __cplusplus
}
#endif
#endif
