#import "ADIconOverrides.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <string.h>

// Reference arm64.txt: fc30 / ffb8 / 1036c. d0,d1=size; d2=scale; d3=corner radius.
// Do not install unless the actual runtime encoding matches this four-double ABI.
typedef struct { CGSize size; CGFloat scale; CGFloat continuousCornerRadius; } ADIconImageInfo;
typedef UIImage *(*ADIconImageIMP)(id, SEL, ADIconImageInfo);
static ADIconImageIMP ADIconOriginalGenerate, ADIconOriginalUnmasked, ADIconOriginalImage;
static NSHashTable *ADIconObservedModels;
static NSObject *ADIconObservedLock;

static BOOL ADIconHasObjectReturn(id target, SEL sel, NSUInteger count) {
    NSMethodSignature *signature = [target methodSignatureForSelector:sel];
    return signature && signature.numberOfArguments == count && signature.methodReturnType[0] == '@';
}
static id ADIconObject(id target, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    return ADIconHasObjectReturn(target,sel,2) ? ((id (*)(id,SEL))objc_msgSend)(target,sel) : nil;
}
static NSString *ADIconIdentifier(id icon) {
    id value = ADIconObject(icon,@"applicationBundleIdentifier");
    if (![value isKindOfClass:NSString.class]) value = ADIconObject(icon,@"applicationBundleID");
    return [value isKindOfClass:NSString.class] ? value : nil;
}
static void ADIconObserve(id icon) {
    if (icon) @synchronized(ADIconObservedLock) { [ADIconObservedModels addObject:icon]; }
}
static UIImage *ADIconReplacement(id icon, ADIconImageInfo info) {
    ADIconObserve(icon);
    NSString *identifier = ADIconIdentifier(icon);
    if ([identifier isEqual:@"com.apple.mobiletimer"] || [identifier isEqual:@"com.apple.mobilecal"]) return nil;
    return [[ADIconOverrideStore sharedStore] imageForBundleIdentifier:identifier size:info.size scale:info.scale radius:info.continuousCornerRadius];
}
static UIImage *ADIconGenerate(id self, SEL cmd, ADIconImageInfo info) {
    return ADIconReplacement(self,info) ?: ADIconOriginalGenerate(self,cmd,info);
}
static UIImage *ADIconUnmasked(id self, SEL cmd, ADIconImageInfo info) {
    // The unmasked entry must not add a mask; SpringBoard applies its own downstream.
    ADIconImageInfo renderInfo = info; renderInfo.continuousCornerRadius = 0;
    return ADIconReplacement(self,renderInfo) ?: ADIconOriginalUnmasked(self,cmd,info);
}
static UIImage *ADIconImage(id self, SEL cmd, ADIconImageInfo info) {
    return ADIconReplacement(self,info) ?: ADIconOriginalImage(self,cmd,info);
}
static BOOL ADIconInfoMethodMatches(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls,selector);
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char *ret = method_copyReturnType(method), *arg = method_copyArgumentType(method,2);
    BOOL valid = ret && ret[0] == '@';
    // Runtime encodings may include quoted structure field names.
    NSMutableString *clean = [NSMutableString new]; BOOL quoted = NO;
    if (arg) for (const char *c = arg; *c; c++) {
        if (*c == '"') quoted = !quoted;
        else if (!quoted) [clean appendFormat:@"%c",*c];
    }
    valid = valid && [clean isEqual:@"{SBIconImageInfo={CGSize=dd}dd}"] && sizeof(ADIconImageInfo) == 32;
    free(ret); free(arg); return valid;
}
static BOOL ADIconSendVoid(id target, NSString *name) {
    SEL sel = NSSelectorFromString(name); NSMethodSignature *sig = [target methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments != 2 || strcmp(sig.methodReturnType,"v")) return NO;
    ((void (*)(id,SEL))objc_msgSend)(target,sel); return YES;
}
static void ADIconCollectViews(UIView *view, NSMutableArray *iconViews) {
    Class cls = NSClassFromString(@"SBIconView");
    if (cls && [view isKindOfClass:cls]) {
        id model = ADIconObject(view,@"icon"); ADIconObserve(model); [iconViews addObject:view];
    }
    for (UIView *child in view.subviews) ADIconCollectViews(child,iconViews);
}
static void ADIconRefreshVisible(void) {
    NSCAssert(NSThread.isMainThread,@"Icon refresh must run on main thread");
    NSMutableArray *views = [NSMutableArray new];
    for (UIWindow *window in UIApplication.sharedApplication.windows) ADIconCollectViews(window,views);
    NSArray *models; @synchronized(ADIconObservedLock) { models = ADIconObservedModels.allObjects; }
    for (id model in models) {
        // These guarded selectors are present in reference refreshSBIcon (348fc..34948).
        if (!ADIconSendVoid(model,@"reloadIconImage")) {
            if (!ADIconSendVoid(model,@"purgeCachedImages")) ADIconSendVoid(model,@"clearCachedImages");
        }
    }
    for (UIView *view in views) { [view setNeedsLayout]; [view setNeedsDisplay];
        UIView *imageView = ADIconObject(view,@"_iconImageView");
        if ([imageView isKindOfClass:UIView.class]) { [imageView setNeedsLayout]; [imageView setNeedsDisplay]; }
    }
}
__attribute__((constructor)) static void ADIconInstallRenderHooks(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
    ADIconObservedLock = [NSObject new]; ADIconObservedModels = [NSHashTable weakObjectsHashTable];
    // Predecode once away from the rendering thread, then install. Rendering does no file I/O.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        [ADIconOverrideStore sharedStore];
        dispatch_async(dispatch_get_main_queue(), ^{
            Class cls = NSClassFromString(@"SBLeafIcon");
            SEL generate = NSSelectorFromString(@"generateIconImageWithInfo:");
            SEL unmasked = NSSelectorFromString(@"unmaskedIconImageWithInfo:");
            SEL image = NSSelectorFromString(@"iconImageWithInfo:");
            if (ADIconInfoMethodMatches(cls,generate)) MSHookMessageEx(cls,generate,(IMP)ADIconGenerate,(IMP *)&ADIconOriginalGenerate);
            else NSLog(@"[ADIcon] generateIconImageWithInfo: absent or ABI mismatch; skipped");
            if (ADIconInfoMethodMatches(cls,unmasked)) MSHookMessageEx(cls,unmasked,(IMP)ADIconUnmasked,(IMP *)&ADIconOriginalUnmasked);
            else NSLog(@"[ADIcon] unmaskedIconImageWithInfo: absent or ABI mismatch; skipped");
            if (ADIconInfoMethodMatches(cls,image)) MSHookMessageEx(cls,image,(IMP)ADIconImage,(IMP *)&ADIconOriginalImage);
            else NSLog(@"[ADIcon] iconImageWithInfo: absent or ABI mismatch; skipped");
            [[NSNotificationCenter defaultCenter] addObserverForName:ADIconOverridesDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { ADIconRefreshVisible(); }];
            ADIconRefreshVisible();
        });
    });
}
