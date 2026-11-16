#import "ADIconOverrides.h"
#import <PhotosUI/PhotosUI.h>

@interface ADIconManagerViewController () <PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, copy) NSString *adIconBundleID;
@property (nonatomic, assign) BOOL adIconBusy;
@property (nonatomic, strong) UIActivityIndicatorView *adIconSpinner;
@end
@implementation ADIconManagerViewController
- (instancetype)initWithBundleIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _adIconBundleID = identifier.copy;
    return self;
}
+ (void)presentFromController:(UIViewController *)presenter bundleIdentifier:(NSString *)identifier {
    ADIconManagerViewController *controller = [[self alloc] initWithBundleIdentifier:identifier];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [presenter presentViewController:navigation animated:YES completion:nil];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"图标图片";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(adIconDone)];
    self.adIconSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.adIconSpinner];
}
- (void)adIconDone { if (!self.adIconBusy) [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? (self.adIconBundleID ? 3 : 1) : 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? (self.adIconBundleID ?: @"图标覆盖") : @"批量主题"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (!section) return @"覆盖保存在插件配置中，不修改应用包。关闭开关保留图片；恢复会移除覆盖。时钟、日历的动态图标不支持替换。";
    return [NSString stringWithFormat:@"已保存 %lu 个覆盖。ZIP 支持 BundleID.png、BundleID-large.png 以及 @2x/@3x 后缀，支持 IconBundles 子目录。非应用素材和时钟、日历会跳过。导入合并并覆盖同名项目，最多 256 张。更改后自动刷新；若系统仍显示缓存，请重新进入桌面或手动注销。",(unsigned long)ADIconOverrideStore.sharedStore.count];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.textColor = UIColor.labelColor;
    if (!path.section && !path.row) {
        cell.textLabel.text = @"启用图标图片覆盖"; UISwitch *toggle = [UISwitch new];
        toggle.on = ADIconOverrideStore.sharedStore.enabled;
        [toggle addTarget:self action:@selector(adIconToggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.textLabel.text = path.section ? (path.row ? @"恢复全部原图" : @"导入 ZIP 主题…") : (path.row == 1 ? @"从照片选择图片…" : @"恢复此应用原图");
        if ((path.section && path.row == 1) || (!path.section && path.row == 2)) cell.textLabel.textColor = UIColor.systemRedColor;
        else cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)adIconMessage:(NSString *)text {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"图标图片" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)adIconSetBusy:(BOOL)busy {
    self.adIconBusy = busy; self.tableView.userInteractionEnabled = !busy;
    self.navigationItem.rightBarButtonItem.enabled = !busy; self.navigationController.modalInPresentation = busy;
    if (busy) [self.adIconSpinner startAnimating]; else [self.adIconSpinner stopAnimating];
}
- (void)adIconWork:(BOOL (^)(NSError **))operation success:(NSString *)success {
    [self adIconSetBusy:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError *error = nil; BOOL ok = operation(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self adIconSetBusy:NO]; [self.tableView reloadData];
            [self adIconMessage:ok ? success : (error.localizedDescription ?: @"操作未完成，原有配置保持不变。")];
        });
    });
}
- (void)adIconToggle:(UISwitch *)sender {
    BOOL enabled = sender.on;
    [self adIconWork:^BOOL(NSError **error) { return [ADIconOverrideStore.sharedStore setOverrideEnabled:enabled error:error]; } success:enabled ? @"已启用覆盖并请求刷新。" : @"已停用覆盖，保存的图片仍保留。"];
}
- (void)adIconConfirm:(NSString *)message action:(void (^)(void))action {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认图标更改" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *item) {
        [weakAlert dismissViewControllerAnimated:YES completion:action];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if (self.adIconBusy) return;
    if (!path.section && path.row == 1) {
        if ([self.adIconBundleID isEqual:@"com.apple.mobiletimer"] || [self.adIconBundleID isEqual:@"com.apple.mobilecal"]) { [self adIconMessage:@"此应用使用动态图标，当前不支持替换。原图将保持不变。"]; return; }
        PHPickerConfiguration *config = [PHPickerConfiguration new]; config.selectionLimit = 1; config.filter = PHPickerFilter.imagesFilter;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } else if (path.section && !path.row) {
        [self adIconConfirm:@"导入会替换同一 Bundle ID 已保存的覆盖，其他项目保留。支持 BundleID.png、-large 和 @2x/@3x 后缀；非应用素材自动跳过。" action:^{
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.zip-archive"] inMode:UIDocumentPickerModeOpen];
            picker.delegate = self; picker.allowsMultipleSelection = NO;
            [self presentViewController:picker animated:YES completion:nil];
        }];
    } else if ((path.section && path.row) || (!path.section && path.row == 2)) {
        NSString *identifier = path.section ? nil : self.adIconBundleID;
        [self adIconConfirm:identifier ? @"删除此应用的覆盖图片并恢复系统原图？" : @"删除全部覆盖图片并恢复所有系统原图？" action:^{
            [self adIconWork:^BOOL(NSError **error) { return [ADIconOverrideStore.sharedStore restoreBundleIdentifier:identifier error:error]; } success:@"覆盖已移除，已请求刷新原图。"];
        }];
    }
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:^{
        NSItemProvider *provider = results.firstObject.itemProvider; if (!provider) return;
        [self adIconSetBusy:YES];
        [provider loadFileRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSURL *url, NSError *providerError) {
            NSError *error = providerError; BOOL ok = NO;
            if (url) {
                NSNumber *size; [url getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
                if (size.unsignedLongLongValue <= 16*1024*1024) {
                    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
                    if (data) ok = [ADIconOverrideStore.sharedStore saveImageData:data forBundleIdentifier:self.adIconBundleID error:&error];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self adIconSetBusy:NO]; [self.tableView reloadData];
                [self adIconMessage:ok ? @"已保存图片并请求刷新。若开关关闭，请先启用图标覆盖。" : (error.localizedDescription ?: @"无法读取所选照片，或照片超过 16 MB。")];
            });
        }];
    }];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;
    // Dispatch to the next main-loop turn so the system can finish dismissing its picker.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self adIconWork:^BOOL(NSError **error) {
            BOOL scoped = [url startAccessingSecurityScopedResource];
            __block NSData *data; __block NSError *readError;
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            [coordinator coordinateReadingItemAtURL:url options:0 error:&readError byAccessor:^(NSURL *readURL) {
                NSNumber *size; [readURL getResourceValue:&size forKey:NSURLFileSizeKey error:&readError];
                if (size.unsignedLongLongValue > 128*1024*1024) {
                    readError = [NSError errorWithDomain:@"ADIconThemeZIP" code:2 userInfo:@{NSLocalizedDescriptionKey:@"ZIP 超过 128 MB。"}]; return;
                }
                data = [NSData dataWithContentsOfURL:readURL options:NSDataReadingMappedIfSafe error:&readError];
            }];
            NSDictionary *images = data ? ADIconReadThemeZIP(data,&readError) : nil;
            BOOL ok = images && [ADIconOverrideStore.sharedStore importPNGData:images error:&readError];
            if (scoped) [url stopAccessingSecurityScopedResource]; if (!ok && error) *error = readError;
            return ok;
        } success:@"ZIP 主题已合并并请求刷新。未安装应用的 Bundle ID 也会保存；关闭覆盖开关时不会显示。"];
    });
}
@end
