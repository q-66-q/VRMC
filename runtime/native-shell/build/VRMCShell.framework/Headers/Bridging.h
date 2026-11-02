#ifndef VRMCShell_Bridging_h
#define VRMCShell_Bridging_h
#include <CompositorServices/CompositorServices.h>
#ifdef __cplusplus
extern "C" {
#endif
void VRMCCompositor_InitAndRun(cp_layer_renderer_t layerRenderer);
void VRMCCompositor_RequestStop(void);
void VRMCCompositor_NotifyGameStopping(void);
/// M4-W2: publish a tracking-area activation from the SwiftUI onSpatialEvent handler.
/// phase: 1 active, 2 ended, 3 cancelled; kind: 1 indirectPinch, 2 directPinch, 3 touch.
void VRMCInput_PublishGazeEvent(uint64_t tileId, int32_t phase, int32_t kind);
int32_t VRMCCompositor_CurrentGeneration(void);
#ifdef __cplusplus
}
#endif
#endif
