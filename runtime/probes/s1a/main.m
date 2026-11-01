//
// main.m — S1a probe: embed an iOS OpenJDK JRE, launch HelloJit, log to Documents.
//
// Spike S1a (docs/mvp/SPIKES.md): prove the JIT26 mechanism on the paired Vision Pro
// in iOS compatibility mode. This is a probe, not product code.
//
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include <unistd.h>

// JLI_Launch from OpenJDK's libjli. jboolean == unsigned char on Apple platforms.
typedef int (*JLI_LaunchFn)(int argc, char **argv,
                            int jargc, char **jargv,
                            int appclassc, char **appclassv,
                            const char *fullversion, const char *dotversion,
                            const char *pname, const char *lname,
                            unsigned char javaargs, unsigned char cpwildcard,
                            unsigned char javaw, int ergo);

static NSString *gLogPath;
static FILE *gLogFile;

static void vrmc_log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[S1A] %@", line);
    if (gLogFile != NULL) {
        fprintf(gLogFile, "[S1A] %s\n", line.UTF8String);
        fflush(gLogFile);
    }
}

static void open_log(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject ?: NSTemporaryDirectory();
    gLogPath = [documents stringByAppendingPathComponent:@"s1a-jit.log"];
    gLogFile = fopen(gLogPath.UTF8String, "a");
    if (gLogFile == NULL) {
        NSLog(@"[S1A] could not open log at %@", gLogPath);
    } else {
        setvbuf(gLogFile, NULL, _IONBF, 0);
        dup2(fileno(gLogFile), STDOUT_FILENO);
        dup2(fileno(gLogFile), STDERR_FILENO);
    }
}

static int run_java(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *jre = [bundle.bundlePath stringByAppendingPathComponent:@"Frameworks/jre"];
    if (jre == nil) {
        vrmc_log(@"JRE not found at Frameworks/jre");
        return 2;
    }
    NSString *libjli = [jre stringByAppendingPathComponent:@"lib/libjli.dylib"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:libjli]) {
        vrmc_log(@"libjli missing at %@", libjli);
        return 3;
    }
    void *handle = dlopen(libjli.UTF8String, RTLD_NOW | RTLD_GLOBAL);
    if (handle == NULL) {
        vrmc_log(@"dlopen failed: %s", dlerror());
        return 4;
    }
    JLI_LaunchFn launch = (JLI_LaunchFn)dlsym(handle, "JLI_Launch");
    if (launch == NULL) {
        vrmc_log(@"JLI_Launch not found: %s", dlerror());
        return 5;
    }

    setenv("XNU_HAS_TXM", "1", 1);           // make the JRE take the JIT26 branch
    setenv("JAVA_HOME", jre.UTF8String, 1);
    setenv("HACK_IGNORE_START_ON_FIRST_THREAD", "1", 1);

    NSString *classes = [bundle.bundlePath stringByAppendingPathComponent:@"s1a"];
    NSString *libPath = [jre stringByAppendingPathComponent:@"lib"];
    NSString *homeArg = [@"-Djava.home=" stringByAppendingString:jre];
    NSString *libArg = [@"-Djava.library.path=" stringByAppendingString:libPath];

    const char *argv[] = {
        "java",
        "-XX:+UnlockExperimentalVMOptions",
        "-XX:+MirrorMappedCodeCache",
        "-XX:+PrintCompilation",
        "-XX:ReservedCodeCacheSize=64m",
        "-Xmx512m",
        "-XX:-UseCompressedClassPointers",
        homeArg.UTF8String,
        libArg.UTF8String,
        "-cp", classes.UTF8String,
        "HelloJit",
        NULL
    };
    int argc = (int)(sizeof(argv) / sizeof(argv[0])) - 1;
    vrmc_log(@"JLI_Launch argc=%d classes=%@", argc, classes);

    int rc = launch(argc, (char **)argv, 0, NULL, 0, NULL,
                    "25.0.4", "25", "java", "java", 0, 0, 0, 0);
    vrmc_log(@"JLI_Launch returned %d", rc);
    return rc;
}

@interface S1AViewController : UIViewController
@property (nonatomic, strong) UILabel *label;
@end

@implementation S1AViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.label = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 24, 24)];
    self.label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.label.textColor = UIColor.whiteColor;
    self.label.numberOfLines = 0;
    self.label.text = @"VRMC S1a JIT probe\nrunning…\nlogs: Documents/s1a-jit.log";
    [self.view addSubview:self.label];
}
@end

static UIWindow *gWindow;

static void s1a_start(void) {
    open_log();
    vrmc_log(@"launch: iOS %@ on %@", UIDevice.currentDevice.systemVersion, UIDevice.currentDevice.model);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int rc = run_java();
        dispatch_async(dispatch_get_main_queue(), ^{
            S1AViewController *vc = (S1AViewController *)gWindow.rootViewController;
            vc.label.text = [NSString stringWithFormat:@"VRMC S1a JIT probe\nJLI_Launch rc=%d\n%@", rc, gLogPath];
        });
    });
}

@interface S1AAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation S1AAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    return YES;
}
@end

@interface S1ASceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation S1ASceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)connectionOptions {
    gWindow = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    gWindow.rootViewController = [S1AViewController new];
    [gWindow makeKeyAndVisible];
    self.window = gWindow;
    s1a_start();
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(S1AAppDelegate.class));
    }
}
