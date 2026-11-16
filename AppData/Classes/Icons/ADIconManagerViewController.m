#import "ADIconOverrides.h"
#import <PhotosUI/PhotosUI.h>

@interface ADIconManagerViewController () <PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, copy) NSString *adIconBundleID;
@property (nonatomic, assign) BOOL adIconBusy;
@property (nonatomic, strong) UIActivityIndicatorView *adIconSpinner;
@property (nonatomic, copy) NSArray<NSDictionary *> *adIconThemes;
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
    [self adIconReloadThemes];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(adIconStoreChanged:) name:ADIconOverridesDidChangeNotification object:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)adIconStoreChanged:(NSNotification *)notification { dispatch_async(dispatch_get_main_queue(), ^{ [self adIconReloadThemes]; }); }
- (void)adIconReloadThemes { self.adIconThemes = [ADIconOverrideStore.sharedStore themes]; [self.tableView reloadData]; }
- (void)adIconDone { if (!self.adIconBusy) [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.adIconBundleID ? 3 : 1;
    return section == 1 ? 2 : MAX((NSUInteger)1, self.adIconThemes.count);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return self.adIconBundleID ?: @"图标覆盖";
    return section == 1 ? @"主题操作" : @"已保存的主题";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (!section) return @"关闭开关保留主题和选择。单张图片保存到当前主题；未选择主题时创建自定义主题。恢复此应用只移除当前主题中该应用的覆盖。时钟、日历不支持替换。";
    if (section == 1) return @"每个 ZIP 保存为独立主题并选中，以文件名命名。支持 BundleID.png、-large、@2x/@3x 和 IconBundles 子目录；非应用素材自动跳过。恢复全部原图只取消选择，不删除主题库。";
    return [NSString stringWithFormat:@"已保存 %lu/32 套主题，每套最多 256 张。点按切换整套图标，未包含的应用显示原图；左滑可重命名或删除。✓ 表示当前选择，覆盖开关关闭时不显示。更改后自动请求刷新；如仍有系统缓存，可重新进入桌面或手动注销。",(unsigned long)self.adIconThemes.count];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.textColor = UIColor.labelColor; cell.textLabel.numberOfLines = 0;
    if (path.section == 2) {
        if (!self.adIconThemes.count) {
            cell.textLabel.text = @"尚未保存主题"; cell.detailTextLabel.text = @"导入 ZIP 或为应用选择图片以创建主题";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            NSDictionary *theme = self.adIconThemes[path.row];
            BOOL active = [theme[@"active"] boolValue];
            cell.textLabel.text = theme[@"name"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 张图标%@",theme[@"count"],active ? (ADIconOverrideStore.sharedStore.enabled ? @" · 当前使用" : @" · 已选择，覆盖已关闭") : @""];
            cell.accessoryType = active ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
    } else if (!path.section && !path.row) {
        cell.textLabel.text = @"启用图标图片覆盖"; UISwitch *toggle = [UISwitch new];
        toggle.on = ADIconOverrideStore.sharedStore.enabled;
        [toggle addTarget:self action:@selector(adIconToggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.textLabel.text = path.section ? (path.row ? @"恢复全部原图（保留主题）" : @"导入新 ZIP 主题…") : (path.row == 1 ? @"从照片选择图片…" : @"恢复此应用原图");
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
            [self adIconSetBusy:NO]; [self adIconReloadThemes];
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
    if (path.section == 2) {
        if (path.row >= self.adIconThemes.count) return;
        NSString *identifier = self.adIconThemes[path.row][@"identifier"];
        [self adIconWork:^BOOL(NSError **error) { return [ADIconOverrideStore.sharedStore selectThemeWithIdentifier:identifier error:error]; }
                   success:@"已切换整套主题并请求刷新。新主题未包含的应用显示原图；关闭覆盖开关时不显示。"];
    } else if (!path.section && path.row == 1) {
        if ([self.adIconBundleID isEqual:@"com.apple.mobiletimer"] || [self.adIconBundleID isEqual:@"com.apple.mobilecal"]) { [self adIconMessage:@"此应用使用动态图标，当前不支持替换。原图将保持不变。"]; return; }
        PHPickerConfiguration *config = [PHPickerConfiguration new]; config.selectionLimit = 1; config.filter = PHPickerFilter.imagesFilter;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } else if (path.section == 1 && !path.row) {
        [self adIconConfirm:@"导入将以 ZIP 文件名新建独立主题并选中；已有主题全部保留。每套最多 256 张图标，最多保存 32 套主题。" action:^{
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.zip-archive"] inMode:UIDocumentPickerModeOpen];
            picker.delegate = self; picker.allowsMultipleSelection = NO;
            [self presentViewController:picker animated:YES completion:nil];
        }];
    } else if ((path.section == 1 && path.row == 1) || (!path.section && path.row == 2)) {
        NSString *identifier = path.section ? nil : self.adIconBundleID;
        [self adIconConfirm:identifier ? @"从当前主题移除此应用的覆盖并恢复原图？其他主题不变。" : @"取消当前主题选择并恢复全部原图？所有已保存主题和图片都会保留，可随时重新选择。" action:^{
            [self adIconWork:^BOOL(NSError **error) { return [ADIconOverrideStore.sharedStore restoreBundleIdentifier:identifier error:error]; }
                       success:identifier ? @"已移除当前主题中此应用的覆盖并请求刷新。" : @"已取消主题选择并请求恢复原图，主题库完整保留。"];
        }];
    }
}
- (void)adIconRenameTheme:(NSDictionary *)theme {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名主题" message:@"输入新名称，点按保存确认更改（1–80 个字符）。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = theme[@"name"]; field.clearButtonMode = UITextFieldViewModeWhileEditing; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = weakAlert.textFields.firstObject.text ?: @"";
        [weakAlert dismissViewControllerAnimated:YES completion:^{
            [self adIconWork:^BOOL(NSError **error) { return [ADIconOverrideStore.sharedStore renameThemeWithIdentifier:theme[@"identifier"] name:name error:error]; } success:@"主题名称已更新。"];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (self.adIconBusy || path.section != 2 || path.row >= self.adIconThemes.count) return nil;
    NSDictionary *theme = self.adIconThemes[path.row];
    UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"重命名" handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
        completion(YES); if (self.adIconBusy) return;
        dispatch_async(dispatch_get_main_queue(), ^{ if (!self.adIconBusy) [self adIconRenameTheme:theme]; });
    }];
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
        completion(YES); if (self.adIconBusy) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.adIconBusy) return;
            [self adIconConfirm:[NSString stringWithFormat:@"删除主题“%@”及其不再被其他主题引用的图片？若删除当前主题，将恢复原图。此操作不可撤销。",theme[@"name"]] action:^{
                [self adIconWork:^BOOL(NSError **error) { return [ADIconOverrideStore.sharedStore deleteThemeWithIdentifier:theme[@"identifier"] error:error]; } success:@"主题已删除，其他主题保持不变。"];
            }];
        });
    }];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[remove, rename]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
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
                [self adIconSetBusy:NO]; [self adIconReloadThemes];
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
            BOOL ok = images && [ADIconOverrideStore.sharedStore importPNGData:images themeName:url.lastPathComponent.stringByDeletingPathExtension error:&readError];
            if (scoped) [url stopAccessingSecurityScopedResource]; if (!ok && error) *error = readError;
            return ok;
        } success:@"已新建并选中 ZIP 主题，原有主题已保留。同名主题会自动编号；未安装应用的 Bundle ID 也会保存。覆盖开关关闭时不会显示。"];
    });
}
@end
