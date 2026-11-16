//
//  ADMainDataSource.m
//  AppData
//
//  Created by Fouad Raheb on 7/15/20.
//

#import "ADMainDataSource.h"
#import "ADAppData.h"
#import "ADDataViewController.h"
#import "ADActionsBarView.h"
#import "ADTitleSectionHeaderView.h"
#import "ADVersionController.h"
#import "ADChoicyBridge.h"
#import "ADRootHideBridge.h"

@implementation ADMainDataSource

- (instancetype)initWithAppData:(ADAppData *)data dataViewController:(ADDataViewController *)dataViewController {
    if (self = [super init]) {
        self.appData = data;
        self.dataViewController = dataViewController;
        // RootHide publishes no reload notification; refresh when returning to SpringBoard.
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(adChoicyChanged:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [ADChoicyBridge startObserving];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(adChoicyChanged:) name:ADChoicySettingsChangedNotification object:nil];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)adChoicyChanged:(NSNotification *)notification {
    [self.dataViewController.tableView reloadData];
}

- (void)adChoicyToggleChanged:(UISwitch *)sender {
    BOOL disabled = sender.on;
    sender.enabled = NO;
    NSString *identifier = self.appData.bundleIdentifier;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL ok = [ADChoicyBridge setInjectionDisabled:disabled forIdentifier:identifier error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.dataViewController.tableView reloadData];
            if (!ok) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Choicy 同步失败" message:error.localizedDescription ?: @"未能保存设置，请重试。" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
                [self.dataViewController presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}

- (void)adRootHideToggleChanged:(UISwitch *)sender {
    BOOL enabled = sender.on;
    sender.enabled = NO;
    NSString *identifier = self.appData.bundleIdentifier;
    NSString *bundlePath = self.appData.bundleURL.path;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL ok = [ADRootHideBridge setBlacklisted:enabled forIdentifier:identifier bundlePath:bundlePath error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.dataViewController.tableView reloadData];
            if (!ok) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"RootHide 同步失败" message:error.localizedDescription ?: @"未能保存设置。" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
                [self.dataViewController presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (!self.appData) {
        return 0;
    }
    return 3;
}

- (NSInteger)tableView:(nonnull UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isContainersSection:section]) {
        NSInteger rows = 0;
        if (self.appData.bundleURL) rows++;
        if (self.appData.dataContainerURL) rows++;
        return rows;
    } else if ([self isAppGroupsSection:section]) {
        return self.appData.appGroups.count;
    } else if ([self isManageSection:section]) {
        return 4;
    }
    return 0;
}

- (BOOL)isManageSection:(NSInteger)section {
    return section == 0;
}
- (BOOL)isContainersSection:(NSInteger)section {
    return section == 1;
}
- (BOOL)isAppGroupsSection:(NSInteger)section {
    return section == 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isContainersSection:indexPath.section] || [self isAppGroupsSection:indexPath.section]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"InfoCellIdentifier"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"InfoCellIdentifier"];
            cell.backgroundColor = [UIColor clearColor];
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
            cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        }
        cell.accessoryView = [ADAppearance.sharedInstance tableCellChevronImageView];
        [ADAppearance applyStylesToCell:cell];
        
        if ([self isContainersSection:indexPath.section]) {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"应用程序目录";
                cell.detailTextLabel.text = self.appData.bundleURL.path;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"应用数据目录";
                cell.detailTextLabel.text = self.appData.dataContainerURL.path;
            }
        } else if ([self isAppGroupsSection:indexPath.section]) {
            ADAppDataGroup *group = [self.appData.appGroups objectAtIndex:indexPath.row];
            cell.textLabel.text = group.identifier;
            cell.detailTextLabel.text = group.url.path;
        }
        return cell;
    } else if ([self isManageSection:indexPath.section]) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ManageCellIdentifier"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"ManageCellIdentifier"];
                cell.backgroundColor = [UIColor clearColor];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.accessoryType = UITableViewCellAccessoryNone;
                
                ADActionsBarView *actionsBar = [[ADActionsBarView alloc] init];
                actionsBar.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:actionsBar];
                [actionsBar.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor].active = YES;
                [actionsBar.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor].active = YES;
                [actionsBar.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor].active = YES;
                [actionsBar.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor].active = YES;

                __weak ADActionsBarView *weakActionsBar = actionsBar;
                
                // Clear Badge
                [actionsBar addItemWithTitle:@"修改角标"
                                      detail:[NSString stringWithFormat:@"%td",[self.appData appBadgeCount]]
                                       image:[ADHelper imageNamed:@"ClearBadge"]
                                     handler:^{
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"应用角标"
                                                                                             message:[NSString stringWithFormat:@"修改或清除应用图标上的角标数量"]
                                                                                      preferredStyle:UIAlertControllerStyleAlert];
                    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                        textField.text = [NSString stringWithFormat:@"%td",self.appData.appBadgeCount];
                        textField.placeholder = @"角标数量";
                        textField.textAlignment = NSTextAlignmentCenter;
                        textField.enabled = NO;
                    }];
                    [alertController addAction:[UIAlertAction actionWithTitle:@"更新" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        UITextField *field = alertController.textFields.firstObject;
                        NSInteger count = [field.text integerValue];
                        [self.appData setAppBadgeCount:count];
                        [weakActionsBar setDetail:@"已更新" forItemAtIndex:0];
                        DISPATCH_AFTER(0.5, { [weakActionsBar setDetail:[NSString stringWithFormat:@"%td",count] forItemAtIndex:0]; });
                        if (self.dataViewController.dockDismissed && IS_IPAD) [ADDataViewController presentFloatingDockIfNeeded];
                    }]];
                    [alertController addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [self.appData setAppBadgeCount:0];
                        [weakActionsBar setDetail:@"已清除" forItemAtIndex:0];
                        DISPATCH_AFTER(0.5, { [weakActionsBar setDetail:@"0" forItemAtIndex:0]; });
                        if (self.dataViewController.dockDismissed && IS_IPAD) [ADDataViewController presentFloatingDockIfNeeded];
                    }]];
                    [alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                        if (self.dataViewController.dockDismissed && IS_IPAD) [ADDataViewController presentFloatingDockIfNeeded];
                    }]];
                    
                    if (IS_IPAD) {
                        self.dataViewController.dockDismissed = [ADDataViewController dismissFloatingDockIfNeededWithCompletion:^{
                            [self.dataViewController presentViewController:alertController animated:YES completion:^{
                                alertController.textFields.firstObject.enabled = true;
                            }];
                        }];
                    } else {
                        [self.dataViewController presentViewController:alertController animated:YES completion:^{
                            alertController.textFields.firstObject.enabled = true;
                        }];
                    }
                }];
                
                // Clear Caches
                [actionsBar addItemWithTitle:@"清理缓存"
                                detail:@"正在加载…"
                                 image:[ADHelper imageNamed:@"ClearCache"]
                                     handler:^{
                    NSInteger itemIndex = 1;
                    [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                    [weakActionsBar setDetail:@"正在清理…" forItemAtIndex:itemIndex];
                    DISPATCH_AFTER(0.5, {
                        [self.appData clearAppCachesWithCompletion:^{
                            [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                            [weakActionsBar setDetail:@"已清除" forItemAtIndex:itemIndex];
                            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                            DISPATCH_AFTER(0.5, {
                                [self.appData getCachesDirectorySizeWithCompletion:^(NSString *formattedSize) {
                                    [weakActionsBar setDetail:formattedSize forItemAtIndex:itemIndex];
                                }];
                            });
                        }];
                    });
                }];
                
                // Clear App Data
                [actionsBar addItemWithTitle:@"清除数据"
                                      detail:@"正在加载…"
                                       image:[ADHelper imageNamed:@"ClearData"]
                                     handler:^{
                    if (self.appData.appStoreVendable) {
                        [self showDestructiveConfirmationAlertWithTitle:@"清除应用数据" message:@"这将清空数据容器内 Library、Documents 和 tmp 文件夹的内容，并重置应用权限。应用群组数据会保留。" confirmTitle:@"清除" confirmHandler:^{
                            NSInteger itemIndex = 2;
                            [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                            [weakActionsBar setDetail:@"正在清理…" forItemAtIndex:itemIndex];
                            DISPATCH_AFTER(0.5, {
                                [self.appData resetDiskContentWithCompletion:^{
                                    [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                    [weakActionsBar setDetail:@"已清除" forItemAtIndex:itemIndex];
                                    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                                    DISPATCH_AFTER(0.5, {
                                        [self.appData getAppUsageDirectorySizeWithCompletion:^(NSString *formattedSize) {
                                            [weakActionsBar setDetail:formattedSize forItemAtIndex:itemIndex];
                                        }];
                                    });
                                }];
                            });
                        }];
                    }
                }];
                
                // Version selection
                [actionsBar addItemWithTitle:@"软件升降级"
                                      detail:self.appData.version
                                       image:[ADHelper imageNamed:@"VersionControl"]
                                     handler:^{
                    ADVersionController *versions = [[ADVersionController alloc] initWithBundleIdentifier:self.appData.bundleIdentifier bundleURL:self.appData.bundleURL currentVersion:self.appData.version];
                    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:versions];
                    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
                    if (@available(iOS 15.0, *)) {
                        UISheetPresentationController *sheet = navigation.sheetPresentationController;
                        sheet.detents = @[[UISheetPresentationControllerDetent mediumDetent]];
                        sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
                        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
                        sheet.prefersGrabberVisible = YES;
                        sheet.preferredCornerRadius = 35;
                    }
                    // Keep dismissal on the Close button so in-flight requests retain
                    // the existing cancellation and installation-state handling.
                    navigation.modalInPresentation = YES;
                    [self.dataViewController presentViewController:navigation animated:YES completion:nil];
                }];

                // Offload App
                [actionsBar addItemWithTitle:@"卸载应用"
                                      detail:nil
                                       image:[ADHelper imageNamed:@"OffloadApp"]
                                     handler:^{
                    if (self.appData.appStoreVendable) {
                        [self showDestructiveConfirmationAlertWithTitle:@"卸载应用（保留数据）" message:@"这将移除应用程序以释放存储空间，但会保留文稿和数据。如果此应用仍在 App Store 上架，重新安装后即可恢复使用原有数据。" confirmTitle:@"卸载" confirmHandler:^{
                            NSInteger itemIndex = 4;
                            [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                            [self.appData offloadAppWithCompletion:^{
                                [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                            }];
                        }];
                    }
                }];
                
                if (!self.appData.appStoreVendable) {
                    [actionsBar setItemEnabled:NO atIndex:2];
                    [actionsBar setItemEnabled:NO atIndex:3];
                    [actionsBar setItemEnabled:NO atIndex:4];
                }
                
                // Set Cache Size
                [actionsBar showLoadingIndicatorForItemAtIndex:1];
                [self.appData getCachesDirectorySizeWithCompletion:^(NSString *formattedSize) {
                    [actionsBar setDetail:formattedSize forItemAtIndex:1];
                    [actionsBar hideLoadingIndicatorForItemAtIndex:1];
                }];
                
                // Set App Data Size
                [actionsBar showLoadingIndicatorForItemAtIndex:2];
                [self.appData getAppUsageDirectorySizeWithCompletion:^(NSString *formattedSize) {
                    [actionsBar setDetail:formattedSize forItemAtIndex:2];
                    [actionsBar hideLoadingIndicatorForItemAtIndex:2];
                }];
            }
            return cell;
        } else if (indexPath.row == 3) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ADRootHideMainCell"];
            if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ADRootHideMainCell"];
            cell.backgroundColor = UIColor.clearColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            [ADAppearance applyStylesToCell:cell];
            cell.textLabel.text = @"RootHide 黑名单";
            NSError *readError = nil, *editError = nil;
            UISwitch *toggle = [UISwitch new];
            toggle.on = [ADRootHideBridge blacklistedForIdentifier:self.appData.bundleIdentifier error:&readError];
            BOOL editable = [ADRootHideBridge canEditIdentifier:self.appData.bundleIdentifier bundlePath:self.appData.bundleURL.path error:&editError];
            toggle.enabled = self.appData.isApplication && editable && !readError;
            toggle.accessibilityLabel = @"RootHide 黑名单，与管理器配置同步";
            cell.detailTextLabel.text = editError.localizedDescription ?: readError.localizedDescription ?: @"与管理器同步；更改后重新启动目标应用";
            [toggle addTarget:self action:@selector(adRootHideToggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            return cell;
        } else if (indexPath.row == 2) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ADChoicyMainCell"];
            if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ADChoicyMainCell"];
            cell.backgroundColor = UIColor.clearColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            [ADAppearance applyStylesToCell:cell];

            cell.textLabel.text = @"禁止插件注入";
            NSError *error = nil;
            BOOL available = [ADChoicyBridge isAvailable];
            UISwitch *toggle = [UISwitch new];
            toggle.on = [ADChoicyBridge injectionDisabledForIdentifier:self.appData.bundleIdentifier error:&error];
            toggle.enabled = available && !error && self.appData.isApplication && ![self.appData.bundleIdentifier isEqual:@"com.apple.Preferences"] && ![self.appData.bundleIdentifier isEqual:@"com.apple.springboard"];
            toggle.accessibilityLabel = @"禁止当前应用插件注入，与 Choicy 同步";
            cell.detailTextLabel.text = !available ? @"需安装 Choicy" : (error ? @"请先检查 Choicy 配置" : @"与 Choicy 同步");
            [toggle addTarget:self action:@selector(adChoicyToggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            return cell;
        } else if (indexPath.row == 1) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MoreInfoCellIdentifier"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"MoreInfoCellIdentifier"];
                cell.backgroundColor = [UIColor clearColor];
            }
            cell.accessoryView = [ADAppearance.sharedInstance tableCellChevronImageView];
            cell.textLabel.text = @"更多设置";
            [ADAppearance applyStylesToCell:cell];
            return cell;
        }
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isManageSection:indexPath.section] && indexPath.row == 0) {
        if ([cell respondsToSelector:@selector(setSeparatorInset:)]) {
            [cell setSeparatorInset:UIEdgeInsetsZero];
        }
        if ([cell respondsToSelector:@selector(setLayoutMargins:)]) {
            [cell setLayoutMargins:UIEdgeInsetsZero];
        }
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self titleForHeaderInSection:section];
    if (title) {
        ADTitleSectionHeaderView *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:ADTitleSectionHeaderView.reuseIdentifier];
        [header configureHeaderWithTitle:[title uppercaseString]];
        return header;
    }
    return nil;
}

- (NSString *)titleForHeaderInSection:(NSInteger)section {
    if ([self isContainersSection:section]) {
        return nil;
    } else if ([self isAppGroupsSection:section]) {
        return !self.appData.appGroups || self.appData.appGroups.count == 0 ? nil : @"应用群组";
    } else if ([self isManageSection:section]) {
        return nil;
    }
    return nil;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isManageSection:indexPath.section]) {
        if (indexPath.row == 0) {
            return 90;
        }
        return 45;
    }
    return 50;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if ([self isManageSection:section] || [self isContainersSection:section]) return CGFLOAT_MIN;
    return 25;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self isManageSection:indexPath.section]) {
        if (indexPath.row == 1) {
            [self.dataViewController switchTableViews];
        }
    } else if ([self isContainersSection:indexPath.section] || [self isAppGroupsSection:indexPath.section]) {
        [self didSelectContainerOrAppGroupSectionAtIndexPath:indexPath];
    }
}

- (void)didSelectContainerOrAppGroupSectionAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isContainersSection:indexPath.section]) {
        if (indexPath.row == 0) {
            if (self.appData.bundleURL) {
                [ADHelper openDirectoryAtURL:self.appData.bundleURL fromController:self.dataViewController];
            }
        } else if (indexPath.row == 1) {
            if (self.appData.dataContainerURL) {
                [ADHelper openDirectoryAtURL:self.appData.dataContainerURL fromController:self.dataViewController];
            }
        }
    } else if ([self isAppGroupsSection:indexPath.section]) {
        ADAppDataGroup *group = [self.appData.appGroups objectAtIndex:indexPath.row];
        if (group.url) {
            [ADHelper openDirectoryAtURL:group.url fromController:self.dataViewController];
        }
    }
}

#pragma mark - UITableViewDelegate / Copy Action

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    return (action == @selector(copy:));
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    if (action == @selector(copy:)) {
        if ([self isContainersSection:indexPath.section] || [self isAppGroupsSection:indexPath.section]) {
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            if (cell.detailTextLabel.text) [[UIPasteboard generalPasteboard] setString:cell.detailTextLabel.text];
        }
    }
}

#pragma mark - UITableViewDelegate / Context Menu

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point  API_AVAILABLE(ios(13.0)) {
    if ([self isContainersSection:indexPath.section] || [self isAppGroupsSection:indexPath.section]) {
        UIContextMenuConfiguration *configuration = [UIContextMenuConfiguration configurationWithIdentifier:indexPath
                                                                                            previewProvider:nil
                                                                                             actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
            NSMutableArray *actions = [NSMutableArray new];
            [actions addObject:[UIAction actionWithTitle:@"在 Filza 中打开" image:nil identifier:@"open-action" handler:^(__kindof UIAction * _Nonnull action) {
                [self didSelectContainerOrAppGroupSectionAtIndexPath:indexPath];
            }]];
            [actions addObject:[UIAction actionWithTitle:@"复制路径" image:nil identifier:@"copy-action" handler:^(__kindof UIAction * _Nonnull action) {
                UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
                if (cell.detailTextLabel.text) [[UIPasteboard generalPasteboard] setString:cell.detailTextLabel.text];
            }]];
            if ([self isAppGroupsSection:indexPath.section]) {
                [actions addObject:[UIAction actionWithTitle:@"复制标识符" image:nil identifier:@"copy-action" handler:^(__kindof UIAction * _Nonnull action) {
                    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
                    if (cell.textLabel.text) [[UIPasteboard generalPasteboard] setString:cell.textLabel.text];
                }]];
            }
            NSString *title = @"";
            if ([self isContainersSection:indexPath.section]) {
                if (indexPath.row == 0) title = @"应用程序目录";
                else if (indexPath.row == 1) title = @"应用数据目录";
            } else if ([self isAppGroupsSection:indexPath.section]) {
                title = @"应用群组";
            }
            return [UIMenu menuWithTitle:title children:actions];
        }];
        return configuration;
    }
    return nil;
}

- (UITargetedPreview *)tableView:(UITableView *)tableView previewForHighlightingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration API_AVAILABLE(ios(13.0)) {
    NSIndexPath *indexPath = (NSIndexPath *)[configuration identifier];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    UIPreviewParameters *parameters = [UIPreviewParameters new];
    parameters.backgroundColor = [UIColor clearColor];
    if ([self isAppGroupsSection:indexPath.section]) {
        return [[UITargetedPreview alloc] initWithView:cell parameters:parameters];
    } else {
        return [[UITargetedPreview alloc] initWithView:cell.detailTextLabel parameters:parameters];
    }
}

- (nullable UITargetedPreview *)tableView:(UITableView *)tableView previewForDismissingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration API_AVAILABLE(ios(13.0)) {
    return [self tableView:tableView previewForHighlightingContextMenuWithConfiguration:configuration];
}

#pragma mark - Helpers

- (void)showDestructiveConfirmationAlertWithTitle:(NSString *)title message:(NSString *)message confirmTitle:(NSString *)confirmTitle confirmHandler:(void(^)())confirmHandler {
    return [self showConfirmationAlertWithTitle:title message:message confirmTitle:confirmTitle confirmStyle:UIAlertActionStyleDestructive confirmHandler:confirmHandler];
}

- (void)showConfirmationAlertWithTitle:(NSString *)title message:(NSString *)message confirmTitle:(NSString *)confirmTitle confirmStyle:(UIAlertActionStyle)style confirmHandler:(void(^)())confirmHandler {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:confirmTitle style:style handler:^(UIAlertAction * _Nonnull action) {
        if (confirmHandler) confirmHandler();
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self.dataViewController presentViewController:alertController animated:YES completion:nil];
}

@end
