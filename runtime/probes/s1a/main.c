// S1a console-style probe: JLI_Launch from main(), no UIApplication/SwiftUI.
// This mirrors Amethyst's game-launch pattern and avoids JLI apple_main re-entry
// into the app's UI main.
#include <dlfcn.h>
#include <libgen.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

typedef int (*JLI_LaunchFn)(int argc, char **argv,
                            int jargc, char **jargv,
                            int appclassc, char **appclassv,
                            const char *fullversion, const char *dotversion,
                            const char *pname, const char *lname,
                            unsigned char javaargs, unsigned char cpwildcard,
                            unsigned char javaw, int ergo);

// JIT26 handshake, same as Amethyst's JavaLauncher.m. StikDebug only runs a script when one is
// assigned to this app (long-press S1AProbe -> Assign Script -> universal.js); otherwise it just
// attaches and detaches. The universal script refuses the JVM's allocation-style brk #0x69, so we
// send it UniversalJIT26Extension.js, which maps 0x69 (x0 = size) onto JIT26PrepareRegion(NULL, size).
#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000
#define JIT26_LEGACY_REFUSED 0x690000E0u  // universal.js writes E0000069 into x0 for brk #0x69
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

static const char kJIT26Extension[] =
    "logLevel = LOG_INFO;\n"
    "let detachAfterFirstBr = false;\n"
    "legacyCommands[0x69] = function(brkResponse) {\n"
    "    x1 = x0;\n"
    "    x0 = 0;\n"
    "    JIT26PrepareRegion(brkResponse);\n"
    "    if (detachAfterFirstBr) {\n"
    "        JIT26Detach();\n"
    "    }\n"
    "};\n"
    "commands[3] = function(brkResponse) {\n"
    "    detachAfterFirstBr = x0 != 0;\n"
    "    log(`JIT26SetDetachAfterFirstBr(${detachAfterFirstBr}) called`);\n"
    "};\n";

__attribute__((noinline,optnone,naked))
static void *JIT26CreateRegionLegacy(size_t len) {
    asm("brk #0x69 \n"
        "ret");
}
__attribute__((noinline,optnone,naked))
static void BreakSendJITScript(const char *script, size_t len) {
    asm("mov x16, #2 \n"
        "brk #0xf00d \n"
        "ret");
}
__attribute__((noinline,optnone,naked))
static void JIT26SetDetachAfterFirstBr(int value) {
    asm("mov x16, #3 \n"
        "brk #0xf00d \n"
        "ret");
}

// getppid() is launchd (1) unless a debugger is attached; CS_DEBUGGED alone survives StikDebug's
// plain attach/detach and is not enough on TXM devices.
static int debugger_attached(void) {
    uint32_t flags = 0;
    csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags));
    return (flags & CS_DEBUGGED) && getppid() != 1;
}

// Returns 0 when the JVM's brk #0x69 will be handled, nonzero (with a log line) otherwise.
// libjli's apple_main re-runs main() on a new thread; a second probe would be served as the
// "first" request and detach the debugger before the JVM asks, so this runs once per process.
static int jit26_handshake(void) {
    static int done;
    if (done) return 0;
    done = 1;
    for (int i = 0; i < 100 && !debugger_attached(); i++) usleep(100 * 1000);
    if (!debugger_attached()) {
        uint32_t flags = 0;
        csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags));
        printf("[S1A] no JIT debugger attached (CS_DEBUGGED=%d ppid=%d); in StikDebug, assign "
               "universal.js to S1AProbe and launch it with Enable JIT\n",
               (flags & CS_DEBUGGED) != 0, getppid());
        return 1;
    }
    // keep the JVM's SIGSEGV-based checks away from the debugger while it is still attached
    task_set_exception_ports(mach_task_self(), EXC_MASK_BAD_ACCESS, MACH_PORT_NULL,
                             EXCEPTION_DEFAULT, MACHINE_THREAD_STATE);
    void *probe = JIT26CreateRegionLegacy(getpagesize());
    if ((uint32_t)(uintptr_t)probe != JIT26_LEGACY_REFUSED) {
        // An allocation-style 0x69 script (e.g. our patched copies) is answering directly.
        printf("[S1A] debugger answered brk #0x69 directly (%p); skipping extension\n", probe);
        if (probe) munmap(probe, getpagesize());
        return 0;
    }
    printf("[S1A] universal JIT26 script detected; sending 0x69 extension\n");
    BreakSendJITScript(kJIT26Extension, strlen(kJIT26Extension));
    JIT26SetDetachAfterFirstBr(1);
    return 0;
}

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
    setvbuf(stdout, NULL, _IONBF, 0);
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

    if (jit26_handshake() != 0) return 3;

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
