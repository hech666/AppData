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
static BOOL ADIconValidFiles(id files) {
    if (![files isKindOfClass:NSDictionary.class] || [files count] > 256) return NO;
    for (id key in files) {
        id file = files[key];
        if (!ADIconValidBundleIdentifier(key) || ![file isKindOfClass:NSString.class] ||
            ![file isEqual:[file lastPathComponent]] || ![[file pathExtension] isEqual:@"png"]) return NO;
    }
    return YES;
}
static NSString *ADIconThemeName(NSString *name) {
    if (![name isKindOfClass:NSString.class]) return nil;
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length && trimmed.length <= 80 ? trimmed : nil;
}
static NSSet *ADIconReferencedFiles(NSDictionary *state) {
    NSMutableSet *files = [NSMutableSet new];
    for (NSDictionary *theme in [state[@"themes"] allValues]) [files addObjectsFromArray:[theme[@"files"] allValues]];
    return files;
}
@interface ADIconOverrideStore ()
// All mutations, including disk writes and decoding, take this lock first.
// Renderers only take @synchronized(self); never wait for disk/image decoding.
@property (nonatomic, strong) NSObject *adIconMutationLock;
@property (nonatomic, copy) NSDictionary *adIconState;
@property (nonatomic, copy) NSDictionary<NSString *, UIImage *> *adIconImages;
@property (nonatomic, strong) NSCache *adIconCache;
@property (nonatomic, strong) NSError *adIconLoadError;
@end
@implementation ADIconOverrideStore
+ (instancetype)sharedStore {
    static ADIconOverrideStore *store; static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [self new]; }); return store;
}
- (instancetype)init {
    if ((self = [super init])) {
        _adIconCache = [NSCache new]; _adIconCache.totalCostLimit = 24 * 1024 * 1024;
        _adIconMutationLock = [NSObject new];
        NSString *path = [ADIconOverridesDirectory() stringByAppendingPathComponent:ADIconStateName];
        NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:path];
        BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path];
        NSMutableDictionary *themes = [NSMutableDictionary new];
        NSString *active = @"";
        BOOL valid = !exists || [disk isKindOfClass:NSDictionary.class];
        if (disk[@"version"]) {
            valid = valid && [disk[@"version"] isEqual:@2] && [disk[@"themes"] isKindOfClass:NSDictionary.class] && [disk[@"themes"] count] <= 32;
            if (valid) for (id identifier in disk[@"themes"]) {
                id theme = disk[@"themes"][identifier];
                if (![identifier isKindOfClass:NSString.class] || ![identifier length] ||
                    ![theme isKindOfClass:NSDictionary.class] || !ADIconThemeName(theme[@"name"]) || !ADIconValidFiles(theme[@"files"])) { valid = NO; break; }
                themes[identifier] = theme;
            }
            active = disk[@"activeTheme"];
            valid = valid && [active isKindOfClass:NSString.class] && (!active.length || themes[active]);
        } else if (disk) {
            // Normalize in memory only. The next successful atomic write migrates
            // metadata; legacy image filenames and bytes remain untouched.
            valid = valid && ADIconValidFiles(disk[@"files"]);
            if (valid && [disk[@"files"] count]) {
                active = @"legacy";
                themes[active] = @{@"name":@"原有图标", @"files":disk[@"files"]};
            }
        }
        if (!valid) {
            // Never silently overwrite an unreadable/unsupported library.
            _adIconLoadError = ADIconError(@"图标主题状态无效或版本不受支持，原文件已保留，无法写入。");
            [themes removeAllObjects]; active = @"";
        }
        _adIconState = @{@"version":@2, @"enabled":[disk[@"enabled"] isKindOfClass:NSNumber.class] ? disk[@"enabled"] : @YES,
                         @"themes":themes.copy, @"activeTheme":active};
        // A missing/corrupt active image is skipped at startup, but its file map
        // is retained. Explicit theme switches fail atomically on decode errors.
        _adIconImages = [self adIconDecodeFiles:themes[active][@"files"] strict:NO error:nil] ?: @{};
    } return self;
}
- (BOOL)enabled { @synchronized(self) { return [self.adIconState[@"enabled"] boolValue]; } }
- (NSUInteger)count { @synchronized(self) { return self.adIconImages.count; } }
- (BOOL)hasOverrideForBundleIdentifier:(NSString *)identifier { @synchronized(self) { return self.adIconImages[identifier] != nil; } }
- (NSString *)activeThemeIdentifier { @synchronized(self) { NSString *identifier = self.adIconState[@"activeTheme"]; return identifier.length ? identifier : nil; } }
- (NSArray<NSDictionary *> *)themes {
    @synchronized(self) {
        NSMutableArray *items = [NSMutableArray new];
        NSDictionary *themes = self.adIconState[@"themes"];
        for (NSString *identifier in themes) {
            NSDictionary *theme = themes[identifier];
            [items addObject:@{@"identifier":identifier, @"name":theme[@"name"], @"count":@([theme[@"files"] count]),
                               @"active":@([identifier isEqual:self.adIconState[@"activeTheme"]])}];
        }
        [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSComparisonResult result = [a[@"name"] localizedStandardCompare:b[@"name"]];
            return result == NSOrderedSame ? [a[@"identifier"] compare:b[@"identifier"]] : result;
        }];
        return items.copy;
    }
}
- (BOOL)adIconCanWrite:(NSError **)error {
    if (!self.adIconLoadError) return YES;
    if (error) *error = self.adIconLoadError;
    return NO;
}
- (NSDictionary *)adIconDecodeFiles:(NSDictionary *)files strict:(BOOL)strict error:(NSError **)error {
    NSMutableDictionary *images = [NSMutableDictionary new];
    for (NSString *identifier in files) {
            NSString *path = [ADIconOverridesDirectory() stringByAppendingPathComponent:files[identifier]];
            NSNumber *size = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileSize];
            UIImage *image = size.unsignedLongLongValue <= 16 * 1024 * 1024 ? ADIconDecode([NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil]) : nil;
            if (image) images[identifier] = image;
            else if (strict) { if (error) *error = ADIconError([NSString stringWithFormat:@"主题图标缺失或损坏：%@。原主题保持不变。",identifier]); return nil; }
    }
    return images.copy;
}
- (BOOL)adIconCommit:(NSDictionary *)state images:(NSDictionary *)images error:(NSError **)error {
    NSString *root = ADIconOverridesDirectory(); NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!plist || ![plist writeToFile:[root stringByAppendingPathComponent:ADIconStateName] options:NSDataWritingAtomic error:error]) return NO;
    NSSet *old = ADIconReferencedFiles(self.adIconState);
    @synchronized(self) {
        self.adIconState = state.copy; self.adIconImages = images.copy; [self.adIconCache removeAllObjects];
    }
    // Only reclaim formerly referenced files after the state is durable. Never
    // sweep unknown files (including interrupted writes or legacy assets).
    NSSet *used = ADIconReferencedFiles(state);
    for (NSString *file in old) if (![used containsObject:file]) [fm removeItemAtPath:[root stringByAppendingPathComponent:file] error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ADIconOverridesDidChangeNotification object:self];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)ADIconOverridesDidChangeNotification, NULL, NULL, YES);
    });
    return YES;
}
- (BOOL)setOverrideEnabled:(BOOL)enabled error:(NSError **)error {
    @synchronized(self.adIconMutationLock) {
        if (![self adIconCanWrite:error]) return NO;
        NSMutableDictionary *state = self.adIconState.mutableCopy; state[@"enabled"] = @(enabled);
        return [self adIconCommit:state images:self.adIconImages error:error];
    }
}
- (NSString *)adIconUniqueName:(NSString *)name themes:(NSDictionary *)themes {
    NSMutableSet *names = [NSMutableSet new];
    for (NSDictionary *theme in themes.allValues) [names addObject:[theme[@"name"] lowercaseString]];
    NSUInteger end = MIN(name.length, (NSUInteger)80);
    if (end < name.length) end = [name rangeOfComposedCharacterSequenceAtIndex:end].location;
    NSString *base = [name substringToIndex:end];
    NSString *candidate = base; NSUInteger suffix = 2;
    while ([names containsObject:candidate.lowercaseString]) {
        NSString *tail = [NSString stringWithFormat:@" (%lu)",(unsigned long)suffix++];
        NSUInteger limit = MIN(base.length, 80 - tail.length);
        if (limit < base.length) limit = [base rangeOfComposedCharacterSequenceAtIndex:limit].location;
        candidate = [[base substringToIndex:limit] stringByAppendingString:tail];
    }
    return candidate;
}
// Called with the mutation lock. All new filenames are immutable and unique;
// a failed write/commit removes only this transaction's newly created files.
- (BOOL)adIconSaveInput:(NSDictionary *)input name:(NSString *)name newTheme:(BOOL)newTheme error:(NSError **)error {
    if (![self adIconCanWrite:error]) return NO;
    if (![input isKindOfClass:NSDictionary.class] || !input.count || input.count > 256) { if (error) *error = ADIconError(@"主题必须包含 1–256 张图标。"); return NO; }
    NSMutableDictionary *state = self.adIconState.mutableCopy;
    NSMutableDictionary *themes = [state[@"themes"] mutableCopy];
    NSString *identifier = state[@"activeTheme"];
    BOOL creating = newTheme || !identifier.length;
    if (creating && themes.count >= 32) { if (error) *error = ADIconError(@"最多保存 32 套主题，请先删除不需要的主题。"); return NO; }
    if (creating) identifier = NSUUID.UUID.UUIDString;
    NSMutableDictionary *theme = creating ? [@{@"name":[self adIconUniqueName:name themes:themes], @"files":@{}} mutableCopy] : [themes[identifier] mutableCopy];
    NSMutableDictionary *map = [theme[@"files"] mutableCopy];
    NSMutableSet *keys = [NSMutableSet setWithArray:map.allKeys]; [keys addObjectsFromArray:input.allKeys];
    if (keys.count > 256) { if (error) *error = ADIconError(@"每套主题最多 256 张图标，请先恢复部分应用原图。"); return NO; }
    NSMutableDictionary *images = creating ? [NSMutableDictionary new] : self.adIconImages.mutableCopy;
    NSMutableDictionary *decoded = [NSMutableDictionary new];
    for (NSString *key in input) {
            id data = input[key];
            UIImage *image = ADIconValidBundleIdentifier(key) && [data isKindOfClass:NSData.class] ? ADIconDecode(data) : nil;
            if (!image) { if (error) *error = ADIconError([NSString stringWithFormat:@"图标无效、过大或无法解码：%@",key]); return NO; }
            decoded[key] = image;
    }
    [images addEntriesFromDictionary:decoded];
    NSFileManager *fm = NSFileManager.defaultManager; NSString *root = ADIconOverridesDirectory();
    if (![fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSMutableArray *created = [NSMutableArray new]; BOOL ok = YES;
    for (NSString *key in decoded) {
            NSString *file;
            do { file = [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"]; }
            while ([fm fileExistsAtPath:[root stringByAppendingPathComponent:file]]);
            NSString *path = [root stringByAppendingPathComponent:file]; [created addObject:path];
            NSData *png = UIImagePNGRepresentation(decoded[key]);
            if (!png) { if (error) *error = ADIconError(@"无法编码图标，原配置保持不变。"); ok = NO; break; }
            if (![png writeToFile:path options:NSDataWritingAtomic error:error]) { ok = NO; break; }
            map[key] = file;
    }
    if (ok) {
        theme[@"files"] = map.copy; themes[identifier] = theme.copy;
        state[@"themes"] = themes.copy; state[@"activeTheme"] = identifier;
        ok = [self adIconCommit:state images:images error:error];
    }
    if (!ok) for (NSString *path in created) [fm removeItemAtPath:path error:nil];
    return ok;
}
- (BOOL)saveImageData:(NSData *)data forBundleIdentifier:(NSString *)identifier error:(NSError **)error {
    if (!ADIconValidBundleIdentifier(identifier) || !data) { if (error) *error = ADIconError(@"无效的 Bundle ID 或图像。"); return NO; }
    @synchronized(self.adIconMutationLock) { return [self adIconSaveInput:@{identifier:data} name:@"自定义主题" newTheme:NO error:error]; }
}
- (BOOL)importPNGData:(NSDictionary<NSString *,NSData *> *)input error:(NSError **)error {
    return [self importPNGData:input themeName:@"导入主题" error:error];
}
- (BOOL)importPNGData:(NSDictionary<NSString *,NSData *> *)input themeName:(NSString *)themeName error:(NSError **)error {
    NSString *name = [themeName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length) name = @"导入主题";
    @synchronized(self.adIconMutationLock) { return [self adIconSaveInput:input name:name newTheme:YES error:error]; }
}
- (BOOL)selectThemeWithIdentifier:(NSString *)identifier error:(NSError **)error {
    @synchronized(self.adIconMutationLock) {
        if (![self adIconCanWrite:error]) return NO;
        NSDictionary *theme = identifier ? self.adIconState[@"themes"][identifier] : nil;
        if (!theme) { if (error) *error = ADIconError(@"主题不存在，请刷新列表。"); return NO; }
        NSDictionary *images = [self adIconDecodeFiles:theme[@"files"] strict:YES error:error];
        if (!images) return NO;
        NSMutableDictionary *state = self.adIconState.mutableCopy; state[@"activeTheme"] = identifier;
        return [self adIconCommit:state images:images error:error];
    }
}
- (BOOL)renameThemeWithIdentifier:(NSString *)identifier name:(NSString *)name error:(NSError **)error {
    NSString *cleanName = ADIconThemeName(name);
    if (!cleanName) { if (error) *error = ADIconError(@"主题名称须为 1–80 个字符，不能全为空白。"); return NO; }
    @synchronized(self.adIconMutationLock) {
        if (![self adIconCanWrite:error]) return NO;
        NSMutableDictionary *state = self.adIconState.mutableCopy, *themes = [state[@"themes"] mutableCopy];
        NSMutableDictionary *theme = identifier ? [themes[identifier] mutableCopy] : nil;
        if (!theme) { if (error) *error = ADIconError(@"主题不存在，请刷新列表。"); return NO; }
        for (NSString *otherID in themes) if (![otherID isEqual:identifier] && [themes[otherID][@"name"] caseInsensitiveCompare:cleanName] == NSOrderedSame) {
            if (error) *error = ADIconError(@"已有同名主题，请使用其他名称。"); return NO;
        }
        theme[@"name"] = cleanName; themes[identifier] = theme.copy; state[@"themes"] = themes.copy;
        return [self adIconCommit:state images:self.adIconImages error:error];
    }
}
- (BOOL)deleteThemeWithIdentifier:(NSString *)identifier error:(NSError **)error {
    @synchronized(self.adIconMutationLock) {
        if (![self adIconCanWrite:error]) return NO;
        NSMutableDictionary *state = self.adIconState.mutableCopy, *themes = [state[@"themes"] mutableCopy];
        if (!identifier || !themes[identifier]) { if (error) *error = ADIconError(@"主题不存在，请刷新列表。"); return NO; }
        [themes removeObjectForKey:identifier]; state[@"themes"] = themes.copy;
        BOOL wasActive = [state[@"activeTheme"] isEqual:identifier];
        if (wasActive) state[@"activeTheme"] = @"";
        return [self adIconCommit:state images:wasActive ? @{} : self.adIconImages error:error];
    }
}
- (BOOL)restoreBundleIdentifier:(NSString *)identifier error:(NSError **)error {
    @synchronized(self.adIconMutationLock) {
        if (![self adIconCanWrite:error]) return NO;
        NSMutableDictionary *state = self.adIconState.mutableCopy;
        NSMutableDictionary *images = self.adIconImages.mutableCopy;
        NSString *active = state[@"activeTheme"];
        if (identifier && active.length) {
            NSMutableDictionary *themes = [state[@"themes"] mutableCopy], *theme = [themes[active] mutableCopy];
            NSMutableDictionary *map = [theme[@"files"] mutableCopy];
            [map removeObjectForKey:identifier]; [images removeObjectForKey:identifier];
            theme[@"files"] = map.copy; themes[active] = theme.copy; state[@"themes"] = themes.copy;
        } else if (!identifier) {
            state[@"activeTheme"] = @""; [images removeAllObjects];
        }
        return [self adIconCommit:state images:images error:error];
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
