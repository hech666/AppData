//
//  ADHelper.m
//  AppData
//
//  Created by Fouad Raheb on 6/29/20.
//

#import "ADHelper.h"

@interface ADHelper ()
@property (nonatomic, strong) NSBundle *resoucesBundle;
@end

@implementation ADHelper

+ (instancetype)sharedInstance {
    static dispatch_once_t p = 0;
    __strong static ADHelper *_sharedInstance = nil;
    dispatch_once(&p, ^{
        _sharedInstance = [[self alloc] init];
        // Create resources bundle
        _sharedInstance.resoucesBundle = [NSBundle bundleWithPath:@"/Library/Application Support/AppData/Resources.bundle"];
    });
    return _sharedInstance;
}

#pragma mark - Resources

+ (UIImage *)imageNamed:(NSString *)imageName {
    return [UIImage imageNamed:imageName inBundle:ADHelper.sharedInstance.resoucesBundle];
}

#pragma mark - Helpers

+ (void)openDirectoryAtURL:(NSURL *)url fromController:(UIViewController *)controller {
    NSString *path = url.path;
    void (^showFailure)(NSString *) = ^(NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开目录" message:message preferredStyle:UIAlertControllerStyleAlert];
            if (path.length > 0) {
                [alert addAction:[UIAlertAction actionWithTitle:@"复制路径" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [UIPasteboard generalPasteboard].string = path;
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
            [controller presentViewController:alert animated:YES completion:nil];
        });
    };
    if (!url.isFileURL || !path.isAbsolutePath) {
        showFailure(@"未能获取有效的本地目录路径。");
        return;
    }

    // Encode a filesystem path, not a query. Escape literal %, # and ? as well.
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/"];
    NSString *encodedPath = [path stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    NSURL *filzaURL = encodedPath ? [NSURL URLWithString:[@"filza://view" stringByAppendingString:encodedPath]] : nil;
    if (!filzaURL) {
        showFailure(@"无法生成目录链接，请复制路径后在文件管理器中打开。");
        return;
    }
    // Try the actual URL: canOpenURL can be restricted independently of openURL.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] openURL:filzaURL options:@{} completionHandler:^(BOOL success) {
            if (success) return;
            NSURL *iFileURL = [NSURL URLWithString:[@"ifile://file://" stringByAppendingString:encodedPath]];
            if (!iFileURL) {
                showFailure(@"系统未能打开 Filza。请确认 Filza 已正确安装，或复制路径手动打开。");
                return;
            }
            [[UIApplication sharedApplication] openURL:iFileURL options:@{} completionHandler:^(BOOL fallbackSuccess) {
                if (!fallbackSuccess) {
                    showFailure(@"系统未能打开 Filza 或 iFile。请确认文件管理器已正确安装且支持 URL 跳转，或复制路径手动打开。");
                }
            }];
        }];
    });
}

+ (SBSApplicationShortcutItem *)applicationShortcutItem {
    SBSApplicationShortcutItem *shortcutItem = [[NSClassFromString(@"SBSApplicationShortcutItem") alloc] init];
    shortcutItem.localizedTitle = @"应用数据";
    shortcutItem.type = kSBApplicationShortcutItemType;
    
    NSData *imageData = nil;
    if (@available(iOS 13, *)) {
        if ([UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark) {
            imageData = UIImagePNGRepresentation([[self imageNamed:@"AppDataIconWhite"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]);
        } else {
            imageData = UIImagePNGRepresentation([[self imageNamed:@"AppDataIcon"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]);
        }
    } else {
        imageData = UIImagePNGRepresentation([[self imageNamed:@"AppDataIcon12"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]);
    }
    if (imageData) {
        SBSApplicationShortcutCustomImageIcon *iconImage = [[NSClassFromString(@"SBSApplicationShortcutCustomImageIcon") alloc] initWithImagePNGData:imageData];
        [shortcutItem setIcon:iconImage];
    }
    return shortcutItem;
}

@end
