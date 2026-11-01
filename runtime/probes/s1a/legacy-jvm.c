// S1a JVM launcher (SwiftUI harness). Loads the embedded iOS JRE and runs HelloJit.
#include <dlfcn.h>
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

static FILE *gLog;

void vrmc_open_log(const char *path) {
    gLog = fopen(path, "a");
    if (gLog != NULL) {
        setvbuf(gLog, NULL, _IONBF, 0);
        dup2(fileno(gLog), STDOUT_FILENO);
        dup2(fileno(gLog), STDERR_FILENO);
    }
    printf("[S1A] log opened at %s\n", path);
}

int vrmc_run_java(const char *bundlePath) {
    char jre[4096], libjli[4096], classes[4096], libpath[4096], homearg[4200], libarg[4200];
    snprintf(jre, sizeof(jre), "%s/Frameworks/jre", bundlePath);
    snprintf(libjli, sizeof(libjli), "%s/lib/libjli.dylib", jre);
    snprintf(classes, sizeof(classes), "%s/s1a", bundlePath);
    snprintf(libpath, sizeof(libpath), "%s/lib", jre);
    snprintf(homearg, sizeof(homearg), "-Djava.home=%s", jre);
    snprintf(libarg, sizeof(libarg), "-Djava.library.path=%s", libpath);

    printf("[S1A] jre=%s\n", jre);
    void *h = dlopen(libjli, RTLD_NOW | RTLD_GLOBAL);
    if (h == NULL) { printf("[S1A] dlopen failed: %s\n", dlerror()); return 4; }
    JLI_LaunchFn launch = (JLI_LaunchFn)dlsym(h, "JLI_Launch");
    if (launch == NULL) { printf("[S1A] no JLI_Launch: %s\n", dlerror()); return 5; }

    setenv("XNU_HAS_TXM", "1", 1);
    setenv("JAVA_HOME", jre, 1);
    setenv("HACK_IGNORE_START_ON_FIRST_THREAD", "1", 1);

    const char *argv[] = {
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
    int argc = (int)(sizeof(argv) / sizeof(argv[0])) - 1;
    printf("[S1A] JLI_Launch argc=%d classes=%s\n", argc, classes);
    int rc = launch(argc, (char **)argv, 0, NULL, 0, NULL,
                    "25.0.4", "25", "java", "java", 0, 0, 0, 0);
    printf("[S1A] JLI_Launch returned %d\n", rc);
    return rc;
}
