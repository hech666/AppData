#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * const ADIconOverridesDidChangeNotification;
FOUNDATION_EXPORT BOOL ADIconValidBundleIdentifier(NSString *identifier);
FOUNDATION_EXPORT NSString *ADIconOverridesDirectory(void);

@interface ADIconOverrideStore : NSObject
+ (instancetype)sharedStore;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) NSUInteger count;
// Mutating methods perform disk/image work: call on a background queue.
- (BOOL)setOverrideEnabled:(BOOL)enabled error:(NSError **)error;
- (BOOL)saveImageData:(NSData *)data forBundleIdentifier:(NSString *)identifier error:(NSError **)error;
- (BOOL)importPNGData:(NSDictionary<NSString *, NSData *> *)images error:(NSError **)error;
- (BOOL)restoreBundleIdentifier:(nullable NSString *)identifier error:(NSError **)error;
// nil means restore ALL. Originals remain in their app bundles, never overwritten.
- (BOOL)hasOverrideForBundleIdentifier:(NSString *)identifier;
- (nullable UIImage *)imageForBundleIdentifier:(NSString *)identifier size:(CGSize)size scale:(CGFloat)scale radius:(CGFloat)radius;
@end

// ZIP reader: stored/deflate, CRC verified, bounded, no archive paths are extracted.
FOUNDATION_EXPORT NSDictionary<NSString *, NSData *> * _Nullable ADIconReadThemeZIP(NSData *data, NSError **error);

@interface ADIconManagerViewController : UITableViewController
// nil bundle ID opens batch-only management. preview is not used as an original backup.
- (instancetype)initWithBundleIdentifier:(nullable NSString *)identifier;
+ (void)presentFromController:(UIViewController *)presenter bundleIdentifier:(nullable NSString *)identifier;
@end
NS_ASSUME_NONNULL_END
