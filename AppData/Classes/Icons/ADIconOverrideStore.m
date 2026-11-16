#import "ADIconOverrides.h"
#import <ImageIO/ImageIO.h>
#import <rootless.h>
#import <math.h>

NSString * const ADIconOverridesDidChangeNotification = @"com.fouadraheb.appdata.icon-overrides.changed";
static NSString * const ADIconStateName = @"ADIconState.plist";
static NSError *ADIconError(NSString *message) {
    return [NSError errorWithDomain:@"ADIconOverrides" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
BOOL ADIconValidBundleIdentifier(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length < 3 || s.length > 240 || ![s containsString:@"."] || [s containsString:@".."] || [s hasPrefix:@"."] || [s hasSuffix:@"."]) return NO;
    return [s rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_"] invertedSet]].location == NSNotFound;
}
NSString *ADIconOverridesDirectory(void) {
#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
    return ROOT_PATH_NS(@"/var/mobile/Library/Preferences/AppDataIcons/ADIconOverrides");
#else
    // Mobile preferences are not installed package resources; do not prepend /var/jb.
    return @"/var/mobile/Library/Preferences/AppDataIcons/ADIconOverrides";
#endif
}
static UIImage *ADIconDecode(NSData *data) {
    if (!data.length || data.length > 16 * 1024 * 1024) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;
    NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    double w = [props[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
    double h = [props[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
    if (w < 1 || h < 1 || w * h > 100000000) { CFRelease(source); return nil; }
    NSDictionary *options = @{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@320,
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately:@YES};
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!cg) return nil;
    UIImage *image = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); return image;
}
@interface ADIconOverrideStore ()
@property (nonatomic, copy) NSDictionary *adIconState;
@property (nonatomic, copy) NSDictionary<NSString *, UIImage *> *adIconImages;
@property (nonatomic, strong) NSCache *adIconCache;
@end
@implementation ADIconOverrideStore
+ (instancetype)sharedStore {
    static ADIconOverrideStore *store; static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [self new]; }); return store;
}
- (instancetype)init {
    if ((self = [super init])) {
        _adIconCache = [NSCache new]; _adIconCache.totalCostLimit = 24 * 1024 * 1024;
        NSString *root = ADIconOverridesDirectory();
        NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:[root stringByAppendingPathComponent:ADIconStateName]];
        NSMutableDictionary *map = [NSMutableDictionary new], *images = [NSMutableDictionary new];
        NSDictionary *files = [disk[@"files"] isKindOfClass:NSDictionary.class] ? disk[@"files"] : @{};
        for (NSString *key in files) {
            NSString *file = files[key];
            if (!ADIconValidBundleIdentifier(key) || ![file isKindOfClass:NSString.class] || ![file isEqual:file.lastPathComponent] || ![file.pathExtension isEqual:@"png"]) continue;
            UIImage *image = ADIconDecode([NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:file]]);
            if (image && images.count < 256) { map[key] = file; images[key] = image; }
        }
        _adIconImages = images.copy;
        _adIconState = @{@"enabled": [disk[@"enabled"] isKindOfClass:NSNumber.class] ? disk[@"enabled"] : @YES, @"files":map.copy};
    } return self;
}
- (BOOL)enabled { @synchronized(self) { return [self.adIconState[@"enabled"] boolValue]; } }
- (NSUInteger)count { @synchronized(self) { return self.adIconImages.count; } }
- (BOOL)hasOverrideForBundleIdentifier:(NSString *)identifier { @synchronized(self) { return self.adIconImages[identifier] != nil; } }
- (BOOL)adIconCommit:(NSDictionary *)state images:(NSDictionary *)images error:(NSError **)error {
    NSString *root = ADIconOverridesDirectory(); NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!plist || ![plist writeToFile:[root stringByAppendingPathComponent:ADIconStateName] options:NSDataWritingAtomic error:error]) return NO;
    NSDictionary *old = self.adIconState[@"files"];
    self.adIconState = state.copy; self.adIconImages = images.copy; [self.adIconCache removeAllObjects];
    NSSet *used = [NSSet setWithArray:[state[@"files"] allValues]];
    for (NSString *file in old.allValues) if (![used containsObject:file]) [fm removeItemAtPath:[root stringByAppendingPathComponent:file] error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ADIconOverridesDidChangeNotification object:self];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)ADIconOverridesDidChangeNotification, NULL, NULL, YES);
    });
    return YES;
}
- (BOOL)setOverrideEnabled:(BOOL)enabled error:(NSError **)error {
    @synchronized(self) { NSMutableDictionary *state = self.adIconState.mutableCopy; state[@"enabled"] = @(enabled); return [self adIconCommit:state images:self.adIconImages error:error]; }
}
- (BOOL)saveImageData:(NSData *)data forBundleIdentifier:(NSString *)identifier error:(NSError **)error {
    if (!ADIconValidBundleIdentifier(identifier) || !data) { if (error) *error = ADIconError(@"无效的 Bundle ID 或图像。"); return NO; }
    return [self importPNGData:@{identifier:data} error:error];
}
- (BOOL)importPNGData:(NSDictionary<NSString *,NSData *> *)input error:(NSError **)error {
    // Decode before acquiring the renderer lock. A failed image aborts the whole import.
    NSMutableDictionary *decoded = [NSMutableDictionary new];
    if (!input.count || input.count > 256) { if (error) *error = ADIconError(@"主题必须包含 1–256 张图标。"); return NO; }
    for (NSString *key in input) {
        UIImage *image = ADIconValidBundleIdentifier(key) ? ADIconDecode(input[key]) : nil;
        if (!image) { if (error) *error = ADIconError([NSString stringWithFormat:@"图标无效、过大或无法解码：%@",key]); return NO; }
        decoded[key] = image;
    }
    @synchronized(self) {
        NSMutableDictionary *map = [self.adIconState[@"files"] mutableCopy], *images = self.adIconImages.mutableCopy;
        [images addEntriesFromDictionary:decoded];
        if (images.count > 256) { if (error) *error = ADIconError(@"最多保留 256 个覆盖，请先恢复部分图标。"); return NO; }
        NSFileManager *fm = NSFileManager.defaultManager; NSString *root = ADIconOverridesDirectory();
        if (![fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error]) return NO;
        NSMutableArray *created = [NSMutableArray new]; BOOL ok = YES;
        for (NSString *key in decoded) {
            NSString *file = [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"];
            NSString *path = [root stringByAppendingPathComponent:file]; [created addObject:path];
            NSData *png = UIImagePNGRepresentation(decoded[key]);
            if (!png || ![png writeToFile:path options:NSDataWritingAtomic error:error]) { ok = NO; break; }
            map[key] = file;
        }
        if (ok) ok = [self adIconCommit:@{@"enabled":self.adIconState[@"enabled"], @"files":map} images:images error:error];
        if (!ok) for (NSString *path in created) [fm removeItemAtPath:path error:nil];
        return ok;
    }
}
- (BOOL)restoreBundleIdentifier:(NSString *)identifier error:(NSError **)error {
    @synchronized(self) {
        NSMutableDictionary *map = [self.adIconState[@"files"] mutableCopy], *images = self.adIconImages.mutableCopy;
        if (identifier) { [map removeObjectForKey:identifier]; [images removeObjectForKey:identifier]; }
        else { [map removeAllObjects]; [images removeAllObjects]; }
        return [self adIconCommit:@{@"enabled":self.adIconState[@"enabled"], @"files":map} images:images error:error];
    }
}
- (UIImage *)imageForBundleIdentifier:(NSString *)identifier size:(CGSize)size scale:(CGFloat)scale radius:(CGFloat)radius {
    if (!identifier || !isfinite(size.width) || !isfinite(size.height) || !isfinite(scale) || !isfinite(radius) || size.width <= 0 || size.height <= 0 || scale <= 0 || size.width * scale > 1024 || size.height * scale > 1024) return nil;
    @synchronized(self) {
        UIImage *image = self.adIconImages[identifier];
        if (![self.adIconState[@"enabled"] boolValue] || !image) return nil;
        NSString *key = [NSString stringWithFormat:@"%@|%.4f|%.4f|%.4f|%.4f",identifier,size.width,size.height,scale,radius];
        UIImage *cached = [self.adIconCache objectForKey:key]; if (cached) return cached;
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat]; format.scale = scale; format.opaque = NO;
        UIImage *rendered = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero,size} cornerRadius:MAX(0, radius)] addClip];
            CGFloat factor = MAX(size.width / image.size.width, size.height / image.size.height);
            CGSize fitted = CGSizeMake(image.size.width * factor, image.size.height * factor);
            [image drawInRect:CGRectMake((size.width-fitted.width)/2, (size.height-fitted.height)/2, fitted.width, fitted.height)];
        }];
        if (rendered) [self.adIconCache setObject:rendered forKey:key cost:(NSUInteger)(size.width*size.height*scale*scale*4)];
        return rendered;
    }
}
@end
