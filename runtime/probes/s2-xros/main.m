#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <unistd.h>

extern int vrmc_probe_main(int argc, char **argv);
extern void vrmc_set_metal_layer(void *layer);

static NSString *gLogPath;

@interface ProbeViewController : UIViewController
@property (nonatomic, strong) UILabel *label;
@end

@implementation ProbeViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.label = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 24, 24)];
    self.label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.label.textColor = UIColor.whiteColor;
    self.label.numberOfLines = 0;
    self.label.text = @"VRMC S2 MoltenVK probe\nrunning…";
    [self.view addSubview:self.label];
}
@end

static UIWindow *gWindow;

static void s2probe_start(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    gLogPath = [paths.firstObject stringByAppendingPathComponent:@"s2-probe.log"];
    // Hand a CAMetalLayer to the Vulkan probe so it can create a real Metal surface.
    CAMetalLayer *metalLayer = [CAMetalLayer layer];
    metalLayer.frame = gWindow.rootViewController.view.bounds;
    metalLayer.drawableSize = CGSizeMake(512, 512);
    [gWindow.rootViewController.view.layer addSublayer:metalLayer];
    vrmc_set_metal_layer((__bridge void *)metalLayer);
    freopen(gLogPath.UTF8String, "a", stdout);
    freopen(gLogPath.UTF8String, "a", stderr);
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *lib = [[NSBundle mainBundle] pathForResource:@"libMoltenVK" ofType:@"dylib" inDirectory:@"Frameworks"];
        int rc = -1;
        printf("=== VRMC S2 probe ===\nlib=%s\n", lib ? lib.UTF8String : "(missing)");
        if (lib != nil) {
            NSString *fw = [lib stringByDeletingLastPathComponent];
            char *argv[] = { "probe", (char *)lib.UTF8String, (char *)fw.UTF8String, NULL };
            rc = vrmc_probe_main(3, argv);
        }
        printf("probe rc=%d\n", rc);
        fflush(stdout);
        fflush(stderr);
        dispatch_async(dispatch_get_main_queue(), ^{
            ProbeViewController *vc = (ProbeViewController *)gWindow.rootViewController;
            vc.label.text = [NSString stringWithFormat:@"VRMC S2 MoltenVK probe\nrc=%d\n%@", rc, gLogPath];
        });
    });
}

@interface ProbeAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation ProbeAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    return YES;
}
@end

@interface S2SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation S2SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)connectionOptions {
    gWindow = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    gWindow.rootViewController = [ProbeViewController new];
    [gWindow makeKeyAndVisible];
    self.window = gWindow;
    s2probe_start();
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeAppDelegate.class));
    }
}
