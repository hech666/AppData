//
//  ADMoreDataSource.m
//  AppData
//
//  Created by Fouad Raheb on 7/15/20.
//

#import "ADMoreDataSource.h"
#import "ADMainDataSource.h"
#import "ADAppData.h"
#import "ADDataViewController.h"
#import "ADIconOverrides.h"
#import "ADSettings.h"

@interface ADMoreDataSource ()
@property (nonatomic, assign) NSInteger expandedSection;
@end

@implementation ADMoreDataSource

- (instancetype)initWithAppData:(ADAppData *)data dataViewController:(ADDataViewController *)dataViewController {
    if (self = [super init]) {
        self.appData = data;
        self.dataViewController = dataViewController;
        self.expandedSection = -1;
    }
    return self;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 6;
}

- (NSInteger)numberOfRowsInSection:(NSInteger)section {
    if (section == 1) {
        return self.appData.urlSchemes.count;
    } else if (section == 2) {
        return self.appData.queriesSchemes.count;
    } else if (section == 3) {
        return self.appData.activityTypes.count;
    } else if (section == 4) {
        return self.appData.backgroundModes.count;
    } else if (section == 5) {
        return self.appData.entitlementsIdentifiers.count;
    }
    return 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 7;
    } else {
        return self.expandedSection == section ? [self numberOfRowsInSection:section] : 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TextCellIdentifier"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"TextCellIdentifier"];
            cell.backgroundColor = [UIColor clearColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = nil;
        [ADAppearance applyStylesToCell:cell];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"内部版本号";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@",self.appData.internalVersion];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"最低 iOS 版本";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@",self.appData.minimumOSVersion];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"构建平台版本";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@",self.appData.platformVersion];
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"图标管理";
            cell.detailTextLabel.text = @"批量导入或恢复图标";
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"重置权限";
            cell.detailTextLabel.text = self.appData.appStoreVendable ? @"重新请求应用授权" : @"此应用不支持";
            cell.selectionStyle = self.appData.appStoreVendable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
            cell.accessoryType = self.appData.appStoreVendable ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        } else if (indexPath.row == 5) {
            cell.textLabel.text = @"上滑图标";
            cell.detailTextLabel.text = @"向上滑动应用图标打开面板";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = [ADSettings swipeUpEnabled];
            [toggle addTarget:self action:@selector(adSwipeToggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        } else if (indexPath.row == 6) {
            cell.textLabel.text = @"外观";
            cell.detailTextLabel.text = [ADSettings titleForAppearanceStyle:[ADSettings appearanceStyle]];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.accessoryView = nil;
        }
        return cell;
    } else {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ExpandableTextCellIdentifier"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"ExpandableTextCellIdentifier"];
            cell.backgroundColor = [UIColor clearColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.textLabel.font = [UIFont systemFontOfSize:15];
        }
        [ADAppearance applyStylesToCell:cell];
        if (indexPath.section == 1) {
            cell.textLabel.text = [NSString stringWithFormat:@"%@",[self.appData.urlSchemes objectAtIndex:indexPath.row]];
        } else if (indexPath.section == 2) {
            cell.textLabel.text = [NSString stringWithFormat:@"%@",[self.appData.queriesSchemes objectAtIndex:indexPath.row]];
        } else if (indexPath.section == 3) {
            cell.textLabel.text = [NSString stringWithFormat:@"%@",[self.appData.activityTypes objectAtIndex:indexPath.row]];
        } else if (indexPath.section == 4) {
            cell.textLabel.text = [NSString stringWithFormat:@"%@",[self.appData.backgroundModes objectAtIndex:indexPath.row]];
        } else if (indexPath.section == 5) {
            cell.textLabel.text = [NSString stringWithFormat:@"%@",[self.appData.entitlementsIdentifiers objectAtIndex:indexPath.row]];
        }
        return cell;
    }
    return nil;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)adSwipeToggleChanged:(UISwitch *)sender {
    [ADSettings setObject:@(sender.on) forKey:kSwipeUpEnabled];
    [[NSNotificationCenter defaultCenter] postNotificationName:kAppDataSwipeUpPreferencesChangedNotification object:nil];
}

- (UIImage *)makeThumbnailOfSize:(CGSize)size ofImage:(UIImage *)image {
    UIGraphicsBeginImageContextWithOptions(size, NO, UIScreen.mainScreen.scale);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *newThumbnail = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newThumbnail;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? 35 : 25;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 3) {
        [ADIconManagerViewController presentFromController:self.dataViewController bundleIdentifier:nil];
        return;
    }
    if (indexPath.section == 0 && indexPath.row == 6) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"外观" message:@"选择面板显示风格" preferredStyle:UIAlertControllerStyleAlert];
        NSArray<NSString *> *values = [ADSettings appearanceValues];
        NSArray<NSString *> *titles = [ADSettings appearanceTitles];
        for (NSUInteger i = 0; i < values.count; i++) {
            NSString *value = values[i];
            [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [ADSettings setInteger:value.integerValue forKey:kAppearance];
                [self.dataViewController.tableView reloadData];
                [tableView reloadData];
                [self.dataViewController.view setNeedsLayout];
            }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self.dataViewController presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (indexPath.section == 0 && indexPath.row == 4) {
        if (!self.appData.appStoreVendable) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置权限" message:@"这将重置此应用访问通讯录、照片、相机等内容的权限。下次使用相关功能时，应用会重新请求授权。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self.appData resetAllAppPermissions];
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
            [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        }]];
        [self.dataViewController presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (indexPath.section == 5) {
        NSString *entitlementIdentifier = [self.appData.entitlementsIdentifiers objectAtIndex:indexPath.row];
        NSString *detailText = [NSString stringWithFormat:@"%@",[self.appData.entitlements objectForKey:entitlementIdentifier]];
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:entitlementIdentifier message:detailText preferredStyle:IS_IPAD ? UIAlertControllerStyleAlert : UIAlertControllerStyleActionSheet];
        [alertController addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        [alertController addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            if (detailText) [[UIPasteboard generalPasteboard] setString:detailText];
        }]];
        [self.dataViewController presentViewController:alertController animated:YES completion:nil];
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        ADTitleSectionHeaderView *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:ADTitleSectionHeaderView.reuseIdentifier];
        [header configureBackHeaderWithTitle:@"更多信息"];
        header.delegate = self;
        return header;
    } else {
        ADExpandableSectionHeaderView *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:ADExpandableSectionHeaderView.reuseIdentifier];
        header.section = section;
        header.delegate = self;
        if (section == 1) {
            header.titleLabel.text = [NSString stringWithFormat:@"URL 协议（%td）",self.appData.urlSchemes.count];
        } else if (section == 2) {
            header.titleLabel.text = [NSString stringWithFormat:@"可查询的 URL 协议（%td）",self.appData.queriesSchemes.count];
        } else if (section == 3) {
            header.titleLabel.text = [NSString stringWithFormat:@"活动类型（%td）",self.appData.activityTypes.count];
        } else if (section == 4) {
            header.titleLabel.text = [NSString stringWithFormat:@"后台运行模式（%td）",self.appData.backgroundModes.count];
        } else if (section == 5) {
            header.titleLabel.text = [NSString stringWithFormat:@"签名权限（%td）",self.appData.entitlementsIdentifiers.count];
        }
        return header;
    }
}

#pragma mark - ADTitleSectionHeaderViewDelegate

- (void)titleSectionHeaderViewDidTapBackButton {
    [self.dataViewController switchTableViews];
}

#pragma mark - ADExpandableSectionHeaderViewDelegate

- (void)expandableSectionHeaderViewDidChange:(ADExpandableSectionHeaderView *)headerView {
    UITableView *tableView = self.dataViewController.moreTableView;
    
    NSInteger currentSection = self.expandedSection;
    
    [tableView beginUpdates];
    if (self.expandedSection == -1) {
        self.expandedSection = headerView.section;
        [self showRowsOfSection:headerView.section inTableView:tableView];
    } else if (self.expandedSection == headerView.section) {
        self.expandedSection = -1;
        [self hideRowsOfSection:currentSection inTableView:tableView];
    } else {
        self.expandedSection = headerView.section;
        
        ADExpandableSectionHeaderView *currentHeaderView = (ADExpandableSectionHeaderView *)([tableView headerViewForSection:currentSection]);
        currentHeaderView.isExpanded = NO;
        
        [self hideRowsOfSection:currentSection inTableView:tableView];
        [self showRowsOfSection:headerView.section inTableView:tableView];
    }
    [tableView endUpdates];
}

- (void)hideRowsOfSection:(NSInteger)section inTableView:(UITableView *)tableView {
    NSArray *indexPaths = [self indexPathsForRowsinSection:section tableView:tableView];
    [tableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationFade];
}

- (void)showRowsOfSection:(NSInteger)section inTableView:(UITableView *)tableView {
    NSArray *indexPaths = [self indexPathsForRowsinSection:section tableView:tableView];
    [tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (NSArray *)indexPathsForRowsinSection:(NSInteger)section tableView:(UITableView *)tableView {
    NSInteger numberOfRowsInSection = [self numberOfRowsInSection:section];
    NSMutableArray *indexPaths = [NSMutableArray new];
    for (NSInteger i = 0; i < numberOfRowsInSection; i++) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:i inSection:section]];
    }
    return indexPaths;
}

#pragma mark - UITableViewDelegate / Context Menu

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point  API_AVAILABLE(ios(13.0)) {
    UIContextMenuConfiguration *configuration = [UIContextMenuConfiguration configurationWithIdentifier:indexPath
                                                                                        previewProvider:nil
                                                                                         actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        NSMutableArray *actions = [NSMutableArray new];
        [actions addObject:[UIAction actionWithTitle:@"复制" image:nil identifier:@"copy-action" handler:^(__kindof UIAction * _Nonnull action) {
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            if (indexPath.section == 1) {
                if (cell.detailTextLabel.text) [[UIPasteboard generalPasteboard] setString:cell.detailTextLabel.text];
            } else {
                if (cell.textLabel.text) [[UIPasteboard generalPasteboard] setString:cell.textLabel.text];
            }
        }]];
        return [UIMenu menuWithTitle:@"" children:actions];
    }];
    return configuration;

}

- (UITargetedPreview *)tableView:(UITableView *)tableView previewForHighlightingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration API_AVAILABLE(ios(13.0)) {
    NSIndexPath *indexPath = (NSIndexPath *)[configuration identifier];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    UIPreviewParameters *parameters = [UIPreviewParameters new];
    parameters.backgroundColor = [UIColor clearColor];
    return [[UITargetedPreview alloc] initWithView:cell parameters:parameters];
}

- (nullable UITargetedPreview *)tableView:(UITableView *)tableView previewForDismissingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration API_AVAILABLE(ios(13.0)) {
    return [self tableView:tableView previewForHighlightingContextMenuWithConfiguration:configuration];
}

@end
