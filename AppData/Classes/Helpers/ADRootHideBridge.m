#import "ADRootHideBridge.h"
#import <rootless.h>

// RootHide Manager 1.4.1: AppDelegate getDefaultsForKey:/setDefaults:forKey:.
// The roothide toolchain maps ROOT_PATH_NS to jbroot. Never scan alternate roots.
static NSString *ADRootHidePath(void) {
    return ROOT_PATH_NS(@"/var/mobile/Library/RootHide/RootHideConfig.plist");
}
static BOOL ADRootHideFail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"ADRootHideBridge" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static NSDictionary *ADRootHideRead(NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:ADRootHidePath() options:0 error:error];
    if (!data) return nil; // Do not create defaults when the manager is uninitialized.
    id root = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
    if (![root isKindOfClass:NSDictionary.class] ||
        (root[@"appconfig"] && ![root[@"appconfig"] isKindOfClass:NSDictionary.class]) ||
        (root[@"blacklistDisabled"] && ![root[@"blacklistDisabled"] isKindOfClass:NSNumber.class]) ||
        (root[@"whitelistMode"] && ![root[@"whitelistMode"] isKindOfClass:NSNumber.class])) {
        ADRootHideFail(error, @"RootHide 配置格式不受支持，请在管理器中检查。"); return nil;
    }
    return root;
}
@implementation ADRootHideBridge
+ (BOOL)blacklistedForIdentifier:(NSString *)identifier error:(NSError **)error {
    if (!identifier.length) return ADRootHideFail(error, @"应用标识不可用。");
    NSDictionary *root = ADRootHideRead(error);
    if (!root) return NO;
    id value = root[@"appconfig"][identifier];
    if (value && ![value isKindOfClass:NSNumber.class]) return ADRootHideFail(error, @"此应用的 RootHide 配置格式异常。");
    // Matches the manager's displayed switch, including blacklistDisabled.
    return ![root[@"blacklistDisabled"] boolValue] && [value boolValue];
}
+ (BOOL)canEditIdentifier:(NSString *)identifier bundlePath:(NSString *)bundlePath error:(NSError **)error {
#ifndef THEOS_PACKAGE_SCHEME_ROOTHIDE
    return ADRootHideFail(error, @"此构建不支持 RootHide 配置写入。");
#endif
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:ROOT_PATH_NS(@"/Applications/RootHide.app/RootHide")])
        return ADRootHideFail(error, @"需安装 RootHide 管理器。");
    if (!identifier.length || !bundlePath.length || [identifier hasPrefix:@"com.apple."])
        return ADRootHideFail(error, @"此应用请在 RootHide 管理器中设置。");
    NSDictionary *root = ADRootHideRead(error);
    if (!root) return NO;
    if ([root[@"blacklistDisabled"] boolValue]) return ADRootHideFail(error, @"当前环境不支持黑名单开关。");
    id value = root[@"appconfig"][identifier];
    if (value && ![value isKindOfClass:NSNumber.class]) return ADRootHideFail(error, @"此应用的 RootHide 配置格式异常。");
    if ([fm fileExistsAtPath:ROOT_PATH_NS(@"/.thebootstrapped")] &&
        ([fm fileExistsAtPath:[bundlePath stringByAppendingString:@"/../.appbackup"]] ||
         [fm fileExistsAtPath:[bundlePath stringByAppendingPathExtension:@"appbackup"]] ||
         [fm fileExistsAtPath:[bundlePath stringByAppendingPathComponent:@".jbroot"]]))
        return ADRootHideFail(error, @"请先在 Bootstrap 中关闭此应用的插件注入。");
    if (![fm isWritableFileAtPath:ADRootHidePath()] || ![fm isWritableFileAtPath:ADRootHidePath().stringByDeletingLastPathComponent])
        return ADRootHideFail(error, @"无 RootHide 配置写入权限，请使用管理器。");
    return YES;
}
+ (BOOL)setBlacklisted:(BOOL)enabled forIdentifier:(NSString *)identifier bundlePath:(NSString *)bundlePath error:(NSError **)error {
    @synchronized(self) {
        if (![self canEditIdentifier:identifier bundlePath:bundlePath error:error]) return NO;
        NSDictionary *before = ADRootHideRead(error);
        if (!before) return NO;
        NSMutableDictionary *root = before.mutableCopy;
        NSMutableDictionary *apps = [root[@"appconfig"] mutableCopy] ?: [NSMutableDictionary new];
        apps[identifier] = @(enabled);
        root[@"appconfig"] = apps;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:root format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
        if (!data) return NO;
        NSDictionary *latest = ADRootHideRead(error);
        if (!latest) return NO;
        if (![latest isEqual:before]) return ADRootHideFail(error, @"RootHide 配置已被其他页面修改，请重试。");
        if (![data writeToFile:ADRootHidePath() options:NSDataWritingAtomic error:error]) return NO;
        NSDictionary *saved = ADRootHideRead(error);
        if (!saved) return NO;
        if (![saved[@"appconfig"][identifier] isEqual:@(enabled)]) return ADRootHideFail(error, @"RootHide 配置回读不一致，请重新检查。");
        // Manager has no reload notification. Do not invent one or kill apps here.
        return YES;
    }
}
@end
