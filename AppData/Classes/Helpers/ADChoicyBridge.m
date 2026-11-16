#import "ADChoicyBridge.h"
#import <rootless.h>
NSString * const ADChoicySettingsChangedNotification = @"com.fouadraheb.appdata.choicy.changed";
static NSString *ADChoicyPath(void) {
    return ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist");
}
static BOOL ADChoicyFail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"ADChoicyBridge" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static NSDictionary *ADChoicyRead(NSError **error) {
    NSString *path = ADChoicyPath();
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) return @{@"preferenceVersion":@1};
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
    if (![plist isKindOfClass:NSDictionary.class]) { ADChoicyFail(error,@"Choicy 配置无法读取，原配置保持不变。"); return nil; }
    id apps = plist[@"appSettings"], version = plist[@"preferenceVersion"];
    if ((apps && ![apps isKindOfClass:NSDictionary.class]) || ![version isKindOfClass:NSNumber.class] || [version integerValue] != 1) {
        ADChoicyFail(error,@"Choicy 配置格式不受支持，请先在 Choicy 中打开并保存设置。"); return nil;
    }
    return plist;
}
static void ADChoicyChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ADChoicySettingsChangedNotification object:nil];
    });
}
@implementation ADChoicyBridge
+ (void)startObserving {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, ADChoicyChanged, CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    });
}
+ (BOOL)isAvailable {
    return [NSFileManager.defaultManager fileExistsAtPath:ROOT_PATH_NS(@"/Library/MobileSubstrate/DynamicLibraries/   Choicy.dylib")];
}
+ (BOOL)injectionDisabledForIdentifier:(NSString *)identifier error:(NSError **)error {
    if (!identifier.length) return NO;
    NSDictionary *root = ADChoicyRead(error);
    id app = root[@"appSettings"][identifier];
    if (app && ![app isKindOfClass:NSDictionary.class]) return ADChoicyFail(error,@"此应用的 Choicy 配置格式异常。");
    id value = app[@"tweakInjectionDisabled"];
    if (value && ![value isKindOfClass:NSNumber.class]) return ADChoicyFail(error,@"此应用的 Choicy 开关格式异常。");
    return [value boolValue];
}
+ (BOOL)setInjectionDisabled:(BOOL)disabled forIdentifier:(NSString *)identifier error:(NSError **)error {
    if (![self isAvailable]) return ADChoicyFail(error,@"请先安装并启用此 Roothide 版本的 Choicy。");
    if (!identifier.length || [identifier isEqual:@"com.apple.springboard"] || [identifier isEqual:@"com.apple.Preferences"]) return ADChoicyFail(error,@"此系统进程请在 Choicy 中管理。");
    @synchronized(self) {
        // Read afresh on every edit; preserve all other apps and custom rules.
        NSDictionary *before = ADChoicyRead(error);
        if (!before) return NO;
        NSMutableDictionary *root = before.mutableCopy;
        NSMutableDictionary *apps = [root[@"appSettings"] mutableCopy] ?: [NSMutableDictionary new];
        id existing = apps[identifier];
        if (existing && ![existing isKindOfClass:NSDictionary.class]) return ADChoicyFail(error,@"此应用的 Choicy 配置格式异常，未写入。");
        NSMutableDictionary *app = [existing mutableCopy] ?: [NSMutableDictionary new];
        app[@"tweakInjectionDisabled"] = @(disabled);
        apps[identifier] = app.copy; root[@"appSettings"] = apps.copy;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:root format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
        if (!data) return NO;
        // Detect an edit made since our initial read instead of knowingly overwriting it.
        NSDictionary *latest = ADChoicyRead(error);
        if (!latest) return NO;
        if (![latest isEqual:before]) return ADChoicyFail(error,@"Choicy 配置刚被其他页面修改，请重试。");
        NSString *path = ADChoicyPath();
        if (![NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
        if (![data writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, NULL, YES);
        return YES;
    }
}
@end
