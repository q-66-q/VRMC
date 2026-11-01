// S1a console-style probe: JLI_Launch from main(), no UIApplication/SwiftUI.
// This mirrors Amethyst's game-launch pattern and avoids JLI apple_main re-entry
// into the app's UI main.
#include <dlfcn.h>
#include <libgen.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef int (*JLI_LaunchFn)(int argc, char **argv,
                            int jargc, char **jargv,
                            int appclassc, char **appclassv,
                            const char *fullversion, const char *dotversion,
                            const char *pname, const char *lname,
                            unsigned char javaargs, unsigned char cpwildcard,
                            unsigned char javaw, int ergo);

static void bundle_path(char *out, size_t n) {
    char exe[4096];
    uint32_t sz = sizeof(exe);
    if (_NSGetExecutablePath(exe, &sz) != 0) { snprintf(out, n, "."); return; }
    char resolved[4096];
    if (realpath(exe, resolved) == NULL) { snprintf(out, n, "."); return; }
    char *d1 = dirname(resolved);          // .../S1AProbe.app
    snprintf(out, n, "%s", d1);
}

int main(int argc, char **argv) {
    const char *home = getenv("HOME");
    char log[4096];
    snprintf(log, sizeof(log), "%s/Documents/s1a-jit.log", home ? home : "/tmp");
    FILE *f = fopen(log, "a");
    if (f) {
        setvbuf(f, NULL, _IONBF, 0);
        dup2(fileno(f), STDOUT_FILENO);
        dup2(fileno(f), STDERR_FILENO);
    }
    printf("[S1A] console-start pid=%d log=%s\n", getpid(), log);

    char bundle[4096], jre[4096], libjli[4096], classes[4096], libpath[4096];
    bundle_path(bundle, sizeof(bundle));
    snprintf(jre, sizeof(jre), "%s/Frameworks/jre", bundle);
    snprintf(libjli, sizeof(libjli), "%s/lib/libjli.dylib", jre);
    snprintf(classes, sizeof(classes), "%s/s1a", bundle);
    snprintf(libpath, sizeof(libpath), "%s/lib", jre);
    printf("[S1A] bundle=%s classes=%s\n", bundle, classes);

    void *h = dlopen(libjli, RTLD_NOW | RTLD_GLOBAL);
    if (!h) { printf("[S1A] dlopen failed: %s\n", dlerror()); return 4; }
    JLI_LaunchFn launch = (JLI_LaunchFn)dlsym(h, "JLI_Launch");
    if (!launch) { printf("[S1A] no JLI_Launch: %s\n", dlerror()); return 5; }

    setenv("XNU_HAS_TXM", "1", 1);
    setenv("JAVA_HOME", jre, 1);
    setenv("HACK_IGNORE_START_ON_FIRST_THREAD", "1", 1);

    char homearg[4200], libarg[4200];
    snprintf(homearg, sizeof(homearg), "-Djava.home=%s", jre);
    snprintf(libarg, sizeof(libarg), "-Djava.library.path=%s", libpath);
    const char *jargv[] = {
        "java",
        "-XX:+UnlockExperimentalVMOptions",
        "-XX:+MirrorMappedCodeCache",
        "-XX:+PrintCompilation",
        "-XX:ReservedCodeCacheSize=64m",
        "-Xmx512m",
        "-XX:-UseCompressedClassPointers",
        homearg, libarg,
        "-cp", classes,
        "HelloJit",
        NULL
    };
    int jargc = (int)(sizeof(jargv) / sizeof(jargv[0])) - 1;
    printf("[S1A] JLI_Launch argc=%d\n", jargc);
    int rc = launch(jargc, (char **)jargv, 0, NULL, 0, NULL,
                    "25.0.4", "25", "java", "java", 0, 0, 0, 0);
    printf("[S1A] JLI_Launch returned %d\n", rc);
    return rc;
}
