#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdint.h>

// Minimal simulator host for the real VRMCShell.framework (same dlopen hook as the Amethyst app).
int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *fw = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/VRMCShell.framework/VRMCShell"];
        void *handle = dlopen(fw.UTF8String, RTLD_NOW | RTLD_GLOBAL);
        if (handle != NULL) {
            typedef int32_t (*vrmc_shell_start_fn)(void);
            vrmc_shell_start_fn start = (vrmc_shell_start_fn)dlsym(handle, "vrmc_shell_start");
            if (start != NULL) return start();
            NSLog(@"[provider-sim] dlsym failed: %s", dlerror());
        } else {
            NSLog(@"[provider-sim] dlopen failed: %s", dlerror());
        }
    }
    return 1;
}
