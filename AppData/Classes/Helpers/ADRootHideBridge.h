#import <Foundation/Foundation.h>
@interface ADRootHideBridge : NSObject
+ (BOOL)blacklistedForIdentifier:(NSString *)identifier error:(NSError **)error;
+ (BOOL)canEditIdentifier:(NSString *)identifier bundlePath:(NSString *)bundlePath error:(NSError **)error;
+ (BOOL)setBlacklisted:(BOOL)enabled forIdentifier:(NSString *)identifier bundlePath:(NSString *)bundlePath error:(NSError **)error;
@end
