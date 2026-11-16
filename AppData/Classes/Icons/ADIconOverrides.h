#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * const ADIconOverridesDidChangeNotification;
FOUNDATION_EXPORT BOOL ADIconValidBundleIdentifier(NSString *identifier);
FOUNDATION_EXPORT NSString *ADIconOverridesDirectory(void);
FOUNDATION_EXPORT UIImage * _Nullable ADIconOriginalPreview(id icon, CGSize size, CGFloat scale);

@interface ADIconOverrideStore : NSObject
+ (instancetype)sharedStore;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly, nullable, copy) NSString *activeThemeIdentifier;
// Each item contains identifier, name, count and active. The array is name-sorted.
- (NSArray<NSDictionary *> *)themes;
// Mutating methods perform disk/image work: call on a background queue.
- (BOOL)setOverrideEnabled:(BOOL)enabled error:(NSError **)error;
- (BOOL)saveImageData:(NSData *)data forBundleIdentifier:(NSString *)identifier error:(NSError **)error;
// Imports a complete, independent theme and activates it.
- (BOOL)importPNGData:(NSDictionary<NSString *, NSData *> *)images error:(NSError **)error;
- (BOOL)importPNGData:(NSDictionary<NSString *, NSData *> *)images themeName:(NSString *)themeName error:(NSError **)error;
- (BOOL)selectThemeWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (BOOL)renameThemeWithIdentifier:(NSString *)identifier name:(NSString *)name error:(NSError **)error;
- (BOOL)deleteThemeWithIdentifier:(NSString *)identifier error:(NSError **)error;
// A non-nil ID removes that app from the active theme. nil deactivates the
// active theme while retaining every saved theme and its files.
- (BOOL)restoreBundleIdentifier:(nullable NSString *)identifier error:(NSError **)error;
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
