#import <UIKit/UIKit.h>

// App Store version selection, adapted from the AppData 2.7.5 workflow.
@interface ADVersionController : UITableViewController
- (instancetype)initWithBundleIdentifier:(NSString *)identifier
                               bundleURL:(NSURL *)bundleURL
                          currentVersion:(NSString *)version;
@end
