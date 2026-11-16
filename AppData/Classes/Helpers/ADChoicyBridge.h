#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString * const ADChoicySettingsChangedNotification;
@interface ADChoicyBridge : NSObject
+ (BOOL)isAvailable;
+ (BOOL)injectionDisabledForIdentifier:(NSString *)identifier error:(NSError **)error;
+ (BOOL)setInjectionDisabled:(BOOL)disabled forIdentifier:(NSString *)identifier error:(NSError **)error;
+ (void)startObserving;
@end
