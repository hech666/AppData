#import "ADDataViewController.h"

// 安全检查宏：避免重复 respondsToSelector 判断
#define AD_SAFE_CALL(obj, sel, ...) \
    ([obj respondsToSelector:@selector(sel)] ? [obj sel __VA_ARGS__] : nil)

#pragma mark - Swipe Up Gesture

%hook SBIconImageView

%property (nonatomic, retain) UISwipeGestureRecognizer *adSwipeGestureRecognizer;

- (instancetype)initWithFrame:(CGRect)frame {
    %log;
    SBIconImageView *result = %orig;
    
    // 卫语句：排除文件夹图标视图
    if ([result isKindOfClass:NSClassFromString(@"SBFolderIconImageView")]) {
        return result;
    }
    
    if ([result respondsToSelector:@selector(setAdSwipeGestureRecognizer:)]) {
        [[NSNotificationCenter defaultCenter] addObserver:result
                                                 selector:@selector(appDataPreferencesChanged)
                                                     name:kAppDataSwipeUpPreferencesChangedNotification
                                                   object:nil];
        
        self.adSwipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:result
                                                                                  action:@selector(appDataDidSwipeUp:)];
        self.adSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
        result.userInteractionEnabled = YES;
        
        [self appDataPreferencesChanged];
    }
    return result;
}

%new
- (void)appDataPreferencesChanged {
    BOOL shouldEnable = [ADSettings swipeUpEnabled];
    BOOL isAdded = [self.gestureRecognizers containsObject:self.adSwipeGestureRecognizer];
    
    if (shouldEnable && !isAdded) {
        [self addGestureRecognizer:self.adSwipeGestureRecognizer];
    } else if (!shouldEnable && isAdded) {
        [self removeGestureRecognizer:self.adSwipeGestureRecognizer];
    }
}

%new
- (void)appDataDidSwipeUp:(UIGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [ADDataViewController presentControllerFromSBIconImageView:self fromContextMenu:NO];
    }
}

%end

#pragma mark - Custom App Name

%hook SBApplication

- (NSString *)displayName {
    NSString *bundleID = AD_SAFE_CALL(self, bundleIdentifier);
    if (!bundleID) return %orig;
    
    NSString *customAppName = [ADSettings customAppNameForBundleIdentifier:bundleID];
    return customAppName ?: %orig;
}

%end

#pragma mark - 3D Touch Menu

%hook SBIconView

- (void)setApplicationShortcutItems:(NSArray *)items {
    if ([ADSettings forceTouchMenuEnabled] && [self ad_isSupportedIcon]) {
        NSMutableArray *newItems = [NSMutableArray arrayWithArray:items ?: @[]];
        SBSApplicationShortcutItem *shortcutItem = [ADHelper applicationShortcutItem];
        if (shortcutItem) {
            [newItems insertObject:shortcutItem atIndex:0];
        }
        %orig(newItems);
    } else {
        %orig;
    }
}

+ (void)activateShortcut:(SBSApplicationShortcutItem *)item
     withBundleIdentifier:(NSString *)bundleID
              forIconView:(SBIconView *)iconView {
    if ([item.type isEqualToString:kSBApplicationShortcutItemType]) {
        [ADDataViewController presentControllerFromSBIconView:iconView fromContextMenu:YES];
    } else {
        %orig;
    }
}

%new
- (BOOL)ad_isSupportedIcon {
    if (![self respondsToSelector:@selector(icon)]) {
        return YES;
    }
    return ![self.icon isKindOfClass:%c(SBFolderIcon)]
        && ![self.icon isKindOfClass:%c(SBWidgetIcon)];
}

%end

%hook SBSApplicationShortcutItem

- (BOOL)sbh_isSystemShortcut {
    if ([self.type isEqualToString:kSBApplicationShortcutItemType]) {
        return YES;
    }
    return %orig;
}

- (NSUInteger)sbh_shortcutSection {
    if ([self.type isEqualToString:kSBApplicationShortcutItemType]) {
        return 2; // System shortcuts section
    }
    return %orig;
}

%end

%ctor {
    %init;
}
