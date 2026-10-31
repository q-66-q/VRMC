#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <unistd.h>

extern int vrmc_probe_main(int argc, char **argv);

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

@interface ProbeAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ProbeAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    gLogPath = [paths.firstObject stringByAppendingPathComponent:@"s2-probe.log"];
    freopen(gLogPath.UTF8String, "a", stdout);
    freopen(gLogPath.UTF8String, "a", stderr);
    setvbuf(stdout, NULL, _IONBF, 0);

    self.window = [[UIWindow alloc] initWithFrame:CGRectZero];
    self.window.rootViewController = [ProbeViewController new];
    [self.window makeKeyAndVisible];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *lib = [[NSBundle mainBundle] pathForResource:@"libMoltenVK" ofType:@"dylib" inDirectory:@"Frameworks"];
        int rc = -1;
        printf("=== VRMC S2 probe ===\nlib=%s\n", lib ? lib.UTF8String : "(missing)");
        if (lib != nil) {
            char *argv[] = { "probe", (char *)lib.UTF8String, NULL };
            rc = vrmc_probe_main(2, argv);
        }
        printf("probe rc=%d\n", rc);
        fflush(stdout);
        dispatch_async(dispatch_get_main_queue(), ^{
            ProbeViewController *vc = (ProbeViewController *)self.window.rootViewController;
            vc.label.text = [NSString stringWithFormat:@"VRMC S2 MoltenVK probe\nrc=%d\n%@", rc, gLogPath];
        });
    });
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeAppDelegate.class));
    }
}
