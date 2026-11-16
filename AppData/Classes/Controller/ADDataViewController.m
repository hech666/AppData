//
//  ADDataViewController.m
//  AppData
//
//  Created by Fouad Raheb on 6/29/20.
//

#import "ADDataViewController.h"
#import "ADDataPresentationManager.h"
#import "ADExpandableSectionHeaderView.h"
#import "ADTitleSectionHeaderView.h"
#import "ADMainDataSource.h"
#import "ADMoreDataSource.h"
#import "ADIconOverrides.h"
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

@interface ADDataViewController () <UIGestureRecognizerDelegate, PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate>

@property (nonatomic, strong) ADDataPresentationManager *presentationManager;

@property (nonatomic, strong) UIVisualEffectView *contentView;

@property (nonatomic, strong) ADAppData *appData;

@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UIButton *nameLabel;
@property (nonatomic, strong) UIButton *nameEditButton;
@property (nonatomic, strong) UIButton *identifierLabel;
@property (nonatomic, strong) UIButton *identifierCopyButton;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UIButton *appStoreButton;

@property (nonatomic, strong) ADMainDataSource *mainDataSource;
@property (nonatomic, strong) ADMoreDataSource *moreDataSource;

@property (nonatomic, assign) BOOL isCopyingIdentifier;

@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *screenEdgeGesture;
@property (nonatomic, assign) BOOL adIconPickerBusy;
@property (nonatomic, assign) BOOL adIconSaving;
@property (nonatomic, weak) PHPickerViewController *adActiveIconPicker;
@property (nonatomic, strong) UIView *adIconTouchTarget;
@property (nonatomic, strong) UITapGestureRecognizer *adIconDoubleTap;

@end

@implementation ADDataViewController

- (instancetype)initWithAppData:(ADAppData *)data {
    if (self = [super init]) {
        ADDataPresentationConfiguration *config = [[ADDataPresentationConfiguration alloc] init];
        
        self.presentationManager = [[ADDataPresentationManager alloc] initWithConfiguration:config];
        
        self.transitioningDelegate = self.presentationManager;
        self.modalPresentationStyle = UIModalPresentationCustom;
        
        self.appData = data;

        self.mainDataSource = [[ADMainDataSource alloc] initWithAppData:self.appData dataViewController:self];
        self.moreDataSource = [[ADMoreDataSource alloc] initWithAppData:self.appData dataViewController:self];
        
        [self initializeViews];
        
        [self configureViewWithAppData];
    }
    return self;
}

#pragma mark - Used from Force Touch Menu

+ (void)presentControllerFromSBIconView:(SBIconView *)iconView fromContextMenu:(BOOL)contextMenu {
    if (!iconView) {
        [self showAlertWithTitle:@"AppData" message:[NSString stringWithFormat:@"无法获取应用数据。\n\n错误：图标视图为空。"]];
        return;
    }
    
    // Find Icon Image View
    SBIconImageView *_iconImageView = nil;
    if ([iconView respondsToSelector:@selector(_iconImageView)]) {
        _iconImageView = [iconView _iconImageView];
    } else {
        _iconImageView = object_getIvar(iconView, class_getInstanceVariable(object_getClass(iconView), [@"_iconImageView" UTF8String]));
    }
    if (!_iconImageView) {
        for (UIView *subview in iconView.subviews) {
            if ([subview isKindOfClass:NSClassFromString(@"SBIconImageView")]) {
                _iconImageView = (SBIconImageView *)subview;
                break;
            }
        }
    }
    
    if (!_iconImageView) {
        [self showAlertWithTitle:@"AppData" message:[NSString stringWithFormat:@"无法获取应用数据。\n\n错误：找不到图标图像视图。"]];
        return;
    }
    [self presentControllerFromSBIconImageView:_iconImageView iconView:iconView fromContextMenu:contextMenu];
}

#pragma mark - Used from Swipe Up

+ (void)presentControllerFromSBIconImageView:(SBIconImageView *)iconImageView fromContextMenu:(BOOL)contextMenu {
    SBIconView *iconView = (SBIconView *)[iconImageView superview];
    if (![iconView respondsToSelector:@selector(icon)]) {
        NSLog(@"iconView: %@",iconView);
        iconView = (SBIconView *)[iconView superview];
    }
    [self presentControllerFromSBIconImageView:iconImageView iconView:iconView fromContextMenu:contextMenu];
}

#pragma mark - Internal

+ (void)presentControllerFromSBIconImageView:(SBIconImageView *)iconImageView iconView:(SBIconView *)iconView fromContextMenu:(BOOL)contextMenu {
    NSLog(@"iconImageView: %@",iconImageView);
    
    UIViewController *rootController = [iconImageView _viewControllerForAncestor];
    NSLog(@"rootController: %@",rootController);
    
    if ([iconView respondsToSelector:@selector(icon)] && [iconView.icon respondsToSelector:@selector(applicationBundleID)] && [iconImageView respondsToSelector:@selector(contentsImage)]) {
        SBIcon *icon = iconView.icon;
        NSString *bundleID = icon.applicationBundleID;
        ADAppData *appData = [ADAppData appDataForBundleIdentifier:bundleID iconImage:iconImageView.contentsImage];
        if (appData) {
            appData.iconView = iconView;
            
            [[UISelectionFeedbackGenerator new] selectionChanged];
            
            ADDataViewController *dataViewController = [[ADDataViewController alloc] initWithAppData:appData];
            if (IS_IPAD) {
                dataViewController.contentView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
                dataViewController.presentationManager.configuration.fadeAnimationAlpha = 0;
                dataViewController.presentationManager.configuration.fadeAnimation = YES;
                dataViewController.presentationManager.configuration.customFrameHandler = ^CGRect(UIView *containerView) {
                    CGSize size = CGSizeMake(containerView.frame.size.width * 0.5, containerView.frame.size.height * 0.5);
                    return CGRectMake(containerView.frame.size.width/2 - size.width/2,
                                      containerView.frame.size.height/2 - size.height/2,
                                      size.width, size.height);
                };
                if (contextMenu) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        [rootController presentViewController:dataViewController animated:YES completion:nil];
                    });
                } else {
                    [rootController presentViewController:dataViewController animated:YES completion:nil];
                }
            } else {
                dataViewController.dockDismissed = [self.class dismissFloatingDockIfNeededWithCompletion:nil];
                [rootController presentViewController:dataViewController animated:YES completion:nil];
            }
        }
    } else {
        [self showAlertFromViewController:rootController
                                    title:@"AppData"
                                  message:[NSString stringWithFormat:@"无法获取应用数据。\n\n%@ 不是有效的图标类。",[iconView class]]
                              cancelTitle:@"好"];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    tapGesture.delegate = self;
    [self.view addGestureRecognizer:tapGesture];
    
    UISwipeGestureRecognizer *swipeUpDownGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    swipeUpDownGesture.delegate = self;
    [swipeUpDownGesture setDirection:UISwipeGestureRecognizerDirectionDown | UISwipeGestureRecognizerDirectionUp];
    [self.view addGestureRecognizer:swipeUpDownGesture];
    
    self.screenEdgeGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(screenEdgeSwiped:)];
    if (self.view.semanticContentAttribute == UISemanticContentAttributeForceRightToLeft) {
        self.screenEdgeGesture.edges = UIRectEdgeRight;
    } else {
        self.screenEdgeGesture.edges = UIRectEdgeLeft;
    }
}

- (void)adReconcileIconPicker {
    if (self.adIconSaving) return;
    PHPickerViewController *picker = self.adActiveIconPicker;
    if (!picker || (!picker.presentingViewController && !picker.isBeingPresented)) {
        self.adActiveIconPicker = nil;
        self.adIconPickerBusy = NO;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self adReconcileIconPicker];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    if ([presentationController.presentedViewController isKindOfClass:PHPickerViewController.class]) {
        self.adActiveIconPicker = nil;
        if (!self.adIconSaving) self.adIconPickerBusy = NO;
        self.adIconDoubleTap.enabled = NO;
        self.adIconDoubleTap.enabled = YES;
    }
}

- (void)adPresentIconOptions {
    if (self.adIconPickerBusy || self.presentedViewController || !self.appData.bundleIdentifier) return;
    UIAlertController *options = [UIAlertController alertControllerWithTitle:@"图标图片" message:@"选择要执行的操作" preferredStyle:UIAlertControllerStyleActionSheet];
    __weak UIAlertController *weakOptions = options;
    [options addAction:[UIAlertAction actionWithTitle:@"从相册选择图片" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakOptions dismissViewControllerAnimated:YES completion:^{
            [self adOpenIconPicker];
        }];
    }]];
    [options addAction:[UIAlertAction actionWithTitle:@"恢复原本图标" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [weakOptions dismissViewControllerAnimated:YES completion:^{
            self.adIconSaving = YES;
            self.adIconPickerBusy = YES;
            NSString *identifier = self.appData.bundleIdentifier;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSError *error = nil;
                BOOL restored = [[ADIconOverrideStore sharedStore] restoreBundleIdentifier:identifier error:&error];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.adIconSaving = NO;
                    self.adIconPickerBusy = NO;
                    if (restored) {
                        UIImage *original = ADIconOriginalPreview(self.appData.iconView.icon, CGSizeMake(58,58), UIScreen.mainScreen.scale);
                        self.iconImageView.image = original;
                        if (original) self.appData.iconImage = original;
                    }
                    [self.class showAlertFromViewController:self title:@"图标图片" message:restored ? @"已移除此应用的覆盖，并请求刷新桌面。" : (error.localizedDescription ?: @"恢复图标失败。") cancelTitle:@"好"];
                });
            });
        }];
    }]];
    [options addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = options.popoverPresentationController;
    popover.sourceView = self.adIconTouchTarget ?: self.iconImageView;
    popover.sourceRect = (self.adIconTouchTarget ?: self.iconImageView).bounds;
    popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    [self presentViewController:options animated:YES completion:nil];
}

- (void)adIconLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self adReconcileIconPicker];
    [self adPresentIconOptions];
}

- (void)adOpenIconPicker {
    if (self.adIconPickerBusy || self.presentedViewController || !self.appData.bundleIdentifier) return;
    if ([self.appData.bundleIdentifier isEqual:@"com.apple.mobiletimer"] || [self.appData.bundleIdentifier isEqual:@"com.apple.mobilecal"]) {
        [self.class showAlertFromViewController:self title:@"图标图片" message:@"时钟和日历使用动态图标，当前不支持替换。" cancelTitle:@"好"];
        return;
    }
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.selectionLimit = 1;
    configuration.filter = [PHPickerFilter imagesFilter];
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationPageSheet;
    self.adActiveIconPicker = picker;
    self.adIconPickerBusy = YES;
    picker.presentationController.delegate = self;
    [self presentViewController:picker animated:YES completion:^{
        picker.presentationController.delegate = self;
        [self adReconcileIconPicker];
    }];
}

- (void)adIconDoubleTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    [self adReconcileIconPicker];
    if (self.presentedViewController || self.isBeingDismissed || !self.view.window) return;
    [self adOpenIconPicker];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    if (picker != self.adActiveIconPicker || self.adIconSaving) return;
    NSItemProvider *provider = results.firstObject.itemProvider;
    self.adIconSaving = provider != nil;
    [picker dismissViewControllerAnimated:YES completion:^{
        self.adActiveIconPicker = nil;
        self.adIconDoubleTap.enabled = NO;
        self.adIconDoubleTap.enabled = YES;
        if (!provider) { self.adIconPickerBusy = NO; return; }
        NSString *identifier = self.appData.bundleIdentifier;
        [provider loadFileRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSURL *url, NSError *providerError) {
            NSError *error = providerError; BOOL saved = NO;
            NSNumber *size = nil;
            if (url && [url getResourceValue:&size forKey:NSURLFileSizeKey error:&error] && size.unsignedLongLongValue <= 16*1024*1024) {
                NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
                if (data) saved = [[ADIconOverrideStore sharedStore] saveImageData:data forBundleIdentifier:identifier error:&error];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.adIconSaving = NO;
                self.adIconPickerBusy = NO;
                if (saved) {
                    UIImage *image = [[ADIconOverrideStore sharedStore] imageForBundleIdentifier:identifier size:CGSizeMake(58,58) scale:UIScreen.mainScreen.scale radius:12];
                    if (image) self.iconImageView.image = image;
                }
                NSString *message = saved ? ([[ADIconOverrideStore sharedStore] enabled] ? @"已更换图标并请求刷新桌面。" : @"图片已保存，请在更多信息的图标管理中开启图标覆盖。") : (error.localizedDescription ?: @"无法读取所选图片，或图片超过 16 MB。");
                [self.class showAlertFromViewController:self title:@"图标图片" message:message cancelTitle:@"好"];
            });
        }];
    }];
}

- (void)screenEdgeSwiped:(UIScreenEdgePanGestureRecognizer *)screenGesture {
    [self switchTableViews];
}

- (void)dismiss {
    [self dismissAppDataControllerAnimated:YES completion:nil];
}

- (void)dismissAppDataControllerAnimated:(BOOL)animated completion:(void(^)())completion {
    if (self.dockDismissed) {
        self.dockDismissed = NO;
        [self.class presentFloatingDockIfNeeded];
    }
    [self dismissViewControllerAnimated:animated completion:completion];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (self.adIconPickerBusy || [touch.view isDescendantOfView:self.iconImageView] || [touch.view isDescendantOfView:self.adIconTouchTarget]) return NO;
    for (UIView *view = touch.view; view && view != self.view; view = view.superview) {
        if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UITableView.class]) return NO;
    }
    return YES;
}

- (void)configureViewWithAppData {
    self.iconImageView.image = self.appData.iconImage;
    self.appStoreButton.hidden = ![self.appData hasAppStoreApp];
    
    if ([self.appData isApplication]) {
        NSString *customIconName = self.appData.customIconName;
        [self.nameLabel setTitle:customIconName?:self.appData.name forState:UIControlStateNormal];
        [self.identifierLabel setTitle:self.appData.bundleIdentifier forState:UIControlStateNormal];
        if (self.appData.diskUsage > 0 && self.appData.diskUsageString) {
            self.versionLabel.text = [self.appData.version stringByAppendingFormat:@"  —  %@",self.appData.diskUsageString];
        } else {
            self.versionLabel.text = self.appData.version;
        }
    } else {
        [self.nameLabel setTitle:@"此项目不是应用" forState:UIControlStateNormal];
        [self.nameLabel setEnabled:NO];
        
        [self.identifierLabel setTitle:@"无应用标识符" forState:UIControlStateNormal];
        [self.identifierLabel setEnabled:NO];
        
        [self.versionLabel setText:@"—"];
        
        self.identifierCopyButton.hidden = YES;
        self.nameEditButton.hidden = YES;
    }
}

- (void)initializeViews {
    self.contentView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentView.clipsToBounds = YES;
    self.contentView.layer.cornerRadius = 35;
    self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
    self.contentView.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMinXMinYCorner;
    [self.view addSubview:self.contentView];
    [self.contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [self.contentView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [self.contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [self.contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    
    UIView *containerView = [UIView new];
    containerView.backgroundColor = [UIColor clearColor];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView.contentView addSubview:containerView];
    [containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor].active = YES;
    [containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor].active = YES;
    [containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor].active = YES;
    [containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor].active = YES;

    [self addSubviewsToContainer:containerView];
}

- (void)addSubviewsToContainer:(UIView *)containerView {
    self.appStoreButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.appStoreButton setImage:[[ADHelper imageNamed:@"AppStoreButton"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    [self.appStoreButton addTarget:self action:@selector(didTapAppStoreButton:) forControlEvents:UIControlEventTouchUpInside];
    self.appStoreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:self.appStoreButton];
    [self.appStoreButton.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:9].active = YES;
    [self.appStoreButton.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-9].active = YES;
    [self.appStoreButton setContentEdgeInsets:UIEdgeInsetsMake(6, 6, 6, 6)];
    [self.appStoreButton.heightAnchor constraintEqualToConstant:30].active = YES;
    [self.appStoreButton.widthAnchor constraintEqualToConstant:30].active = YES;
    
    self.iconImageView = [[UIImageView alloc] init];
    [self.iconImageView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [containerView addSubview:self.iconImageView];
    self.adIconTouchTarget = [UIView new];
    self.adIconTouchTarget.backgroundColor = UIColor.clearColor;
    self.adIconTouchTarget.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:self.adIconTouchTarget];
    [NSLayoutConstraint activateConstraints:@[
        [self.adIconTouchTarget.centerXAnchor constraintEqualToAnchor:self.iconImageView.centerXAnchor],
        [self.adIconTouchTarget.centerYAnchor constraintEqualToAnchor:self.iconImageView.centerYAnchor],
        [self.adIconTouchTarget.widthAnchor constraintEqualToConstant:74],
        [self.adIconTouchTarget.heightAnchor constraintEqualToConstant:74]
    ]];
    self.adIconTouchTarget.isAccessibilityElement = YES;
    self.adIconTouchTarget.accessibilityLabel = @"应用图标";
    self.adIconTouchTarget.accessibilityHint = @"双击选择照片，长按管理或恢复此应用图标";
    self.adIconDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(adIconDoubleTapped:)];
    self.adIconDoubleTap.numberOfTapsRequired = 2;
    [self.adIconTouchTarget addGestureRecognizer:self.adIconDoubleTap];
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(adIconLongPressed:)];
    hold.minimumPressDuration = 0.5;
    [hold requireGestureRecognizerToFail:self.adIconDoubleTap];
    [self.adIconTouchTarget addGestureRecognizer:hold];
    self.screenEdgeGesture.delegate = self;


    [self.iconImageView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:15].active = YES;
    [self.iconImageView.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:15].active = YES;
    [self.iconImageView.widthAnchor constraintEqualToConstant:58].active = YES;
    [self.iconImageView.heightAnchor constraintEqualToConstant:58].active = YES;
    self.nameLabel = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.nameLabel addTarget:self action:@selector(didTapNameButton:) forControlEvents:UIControlEventTouchUpInside];
    self.nameLabel.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.nameLabel.titleLabel.font = [UIFont systemFontOfSize:17];
    
    [self.nameLabel setTitle:@"-" forState:UIControlStateNormal];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:self.nameLabel];
    [self.nameLabel.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:15].active = YES;
    [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.iconImageView.trailingAnchor constant:11].active = YES;
    [self.nameLabel.heightAnchor constraintEqualToConstant:22].active = YES;
    [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.appStoreButton.leadingAnchor constant:- (22 + 11)].active = YES;
    
    UIImage *nameEditImage = nil;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightBold];
        nameEditImage = [[UIImage systemImageNamed:@"square.and.pencil" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else {
        nameEditImage = [[ADHelper imageNamed:@"EditIconButton"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    self.nameEditButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.nameEditButton setImage:nameEditImage forState:UIControlStateNormal];
    [self.nameEditButton addTarget:self action:@selector(didTapNameButton:) forControlEvents:UIControlEventTouchUpInside];
    [self.nameEditButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [containerView addSubview:self.nameEditButton];
    [self.nameEditButton setContentEdgeInsets:UIEdgeInsetsMake(4.75, 4.75, 4.75, 4.75)];
    [self.nameEditButton.heightAnchor constraintEqualToConstant:22].active = YES;
    [self.nameEditButton.widthAnchor constraintEqualToConstant:22].active = YES;
    [self.nameEditButton.centerYAnchor constraintEqualToAnchor:self.nameLabel.centerYAnchor].active = YES;
    [self.nameEditButton.leadingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor constant:2].active = YES;
    
    self.identifierLabel = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.identifierLabel addTarget:self action:@selector(didTapIdentifierButton:) forControlEvents:UIControlEventTouchUpInside];
    self.identifierLabel.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.identifierLabel setTitle:@"-" forState:UIControlStateNormal];
    self.identifierLabel.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.identifierLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:self.identifierLabel];
    [self.identifierLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2].active = YES;
    [self.identifierLabel.leadingAnchor constraintEqualToAnchor:self.iconImageView.trailingAnchor constant:11].active = YES;
    [self.identifierLabel.heightAnchor constraintEqualToConstant:20.16].active = YES;
    [self.identifierLabel.trailingAnchor constraintLessThanOrEqualToAnchor:containerView.trailingAnchor constant:- (22 + 11)].active = YES;

    UIImage *clipboardImage = nil;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightBold];
        clipboardImage = [[UIImage systemImageNamed:@"doc.on.clipboard" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else {
        clipboardImage = [[ADHelper imageNamed:@"ClipboardButton"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    self.identifierCopyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.identifierCopyButton setImage:clipboardImage forState:UIControlStateNormal];
    [self.identifierCopyButton addTarget:self action:@selector(didTapIdentifierButton:) forControlEvents:UIControlEventTouchUpInside];
    [self.identifierCopyButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [containerView addSubview:self.identifierCopyButton];
    [self.identifierCopyButton setContentEdgeInsets:UIEdgeInsetsMake(5, 5, 5, 5)];
    [self.identifierCopyButton.heightAnchor constraintEqualToConstant:22].active = YES;
    [self.identifierCopyButton.widthAnchor constraintEqualToConstant:22].active = YES;
    [self.identifierCopyButton.centerYAnchor constraintEqualToAnchor:self.identifierLabel.centerYAnchor].active = YES;
    [self.identifierCopyButton.leadingAnchor constraintEqualToAnchor:self.identifierLabel.trailingAnchor constant:1].active = YES;
    
    self.versionLabel = [[UILabel alloc] init];
    self.versionLabel.font = [UIFont systemFontOfSize:13];
    self.versionLabel.text = @"-";
    self.versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:self.versionLabel];
    [self.versionLabel.topAnchor constraintEqualToAnchor:self.identifierLabel.bottomAnchor].active = YES;
    [self.versionLabel.leadingAnchor constraintEqualToAnchor:self.iconImageView.trailingAnchor constant:11].active = YES;
    [self.versionLabel.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-11].active = YES;
    [self.versionLabel.heightAnchor constraintEqualToConstant:20.16].active = YES;
    
    // Create Table View
    self.tableView = [self createTableViewWithDataSource:self.mainDataSource];
    [self.tableView registerClass:ADTitleSectionHeaderView.class forHeaderFooterViewReuseIdentifier:ADTitleSectionHeaderView.reuseIdentifier];
    [containerView addSubview:self.tableView];
    
    self.moreTableView = [self createTableViewWithDataSource:self.moreDataSource];
    [self.moreTableView registerClass:ADExpandableSectionHeaderView.class forHeaderFooterViewReuseIdentifier:ADExpandableSectionHeaderView.reuseIdentifier];
    [self.moreTableView registerClass:ADTitleSectionHeaderView.class forHeaderFooterViewReuseIdentifier:ADTitleSectionHeaderView.reuseIdentifier];
    self.moreTableView.hidden = YES;
    [containerView addSubview:self.moreTableView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutTableViews];
    
    // Apply blur effect to contentView
    self.contentView.effect = [UIBlurEffect effectWithStyle:[ADAppearance.sharedInstance blurEffectStyle]];

    // Apply text colors
    UIColor *primaryLabelColor = [ADAppearance.sharedInstance primaryTextColor];
    UIColor *secondaryLabelsColor = [ADAppearance.sharedInstance secondaryTextColor];
    // secondaryLabelsColor = [UIColor colorWithRed:0.922 green:0.922 blue:0.961 alpha:0.6];
    // secondaryLabelsColor = [UIColor colorWithRed:0.235294 green:0.235294 blue:0.262745 alpha:0.65]; Light

    [self.nameLabel setTitleColor:primaryLabelColor forState:UIControlStateNormal];
    [self.identifierLabel setTitleColor:secondaryLabelsColor forState:UIControlStateNormal];
    self.versionLabel.textColor = secondaryLabelsColor;
    [self.identifierCopyButton setTintColor:secondaryLabelsColor];
    [self.nameEditButton setTintColor:secondaryLabelsColor];
    [self.appStoreButton setTintColor:secondaryLabelsColor];
    
    self.tableView.separatorColor = [ADAppearance.sharedInstance tableSeparatorColor];
    self.moreTableView.separatorColor = [ADAppearance.sharedInstance tableSeparatorColor];
}

- (void)traitCollectionDidChange:(UITraitCollection *)collection {
    [self.tableView reloadData];
    [self.moreTableView reloadData];
}

- (UITableView *)createTableViewWithDataSource:(id)dataSource {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    tableView.showsVerticalScrollIndicator = NO;
    tableView.backgroundColor = [UIColor clearColor];
    tableView.delegate = dataSource;
    tableView.dataSource = dataSource;
    return tableView;
}

- (void)layoutTableViews {
    CGFloat y = self.iconImageView.frame.origin.y + self.iconImageView.frame.size.height + 15;
    CGRect frame = CGRectMake(0, y, self.tableView.superview.frame.size.width, self.tableView.superview.frame.size.height - y);
    self.tableView.frame = frame;
    self.moreTableView.frame = frame;
}

#pragma mark - Actions

- (void)didTapNameButton:(UIButton *)button {
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self showCustomIconNameInterface];
}

- (void)didTapIdentifierButton:(UIButton *)button {
    if (!self.isCopyingIdentifier) {
        self.isCopyingIdentifier = YES;
        
        NSString *currentTitle = self.identifierLabel.titleLabel.text;
        [[UIPasteboard generalPasteboard] setString:currentTitle?:@""];
        
        [self.identifierLabel setTitle:@"已复制到剪贴板" forState:UIControlStateNormal];
        
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.7 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self.identifierLabel setTitle:currentTitle forState:UIControlStateNormal];
            self.isCopyingIdentifier = NO;
        });
    }
}

- (void)didTapAppStoreButton:(UIButton *)button {
    if (IS_IPAD) {
        [self dismissAppDataControllerAnimated:YES completion:^{
            [self.appData openInAppStore];
        }];
    } else {
        [self.appData openInAppStore];
    }
}

- (void)showCustomIconNameInterface {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"重命名" message:@"请输入应用图标名称" preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        if (self.dockDismissed && IS_IPAD) [self.class presentFloatingDockIfNeeded];
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"修改" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self.appData setCustomIconName:alertController.textFields.firstObject.text];
        [self.nameLabel setTitle:self.appData.name forState:UIControlStateNormal];
        if (self.dockDismissed && IS_IPAD) [self.class presentFloatingDockIfNeeded];
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self.appData setCustomIconName:nil];
        [self.nameLabel setTitle:self.appData.name forState:UIControlStateNormal];
        if (self.dockDismissed && IS_IPAD) [self.class presentFloatingDockIfNeeded];
    }]];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.clearButtonMode = UITextFieldViewModeAlways;
        textField.placeholder = @"图标名称";
        textField.text = self.nameLabel.titleLabel.text;
    }];
    if (IS_IPAD) {
        self.dockDismissed = [self.class dismissFloatingDockIfNeededWithCompletion:^{
            [self presentViewController:alertController animated:YES completion:nil];
        }];
    } else {
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

- (void)switchTableViews {
    UITableView *activeTableView = self.tableView.hidden ? self.moreTableView : self.tableView;
    UITableView *inactiveTableView = self.tableView.hidden ? self.tableView : self.moreTableView;
    
    BOOL isPresenting = [activeTableView isEqual:self.tableView];
    
    CGRect activeInitialFrame = activeTableView.frame;
    CGRect activeEndFrame = CGRectMake(0 - activeTableView.frame.size.width, activeTableView.frame.origin.y, activeTableView.frame.size.width, activeTableView.frame.size.height);
    
    CGRect inactiveInitialFrame = CGRectMake(activeTableView.frame.size.width, activeTableView.frame.origin.y, activeTableView.frame.size.width, activeTableView.frame.size.height);
    CGRect inactiveEndFrame = activeTableView.frame;
    
    if (isPresenting) {
        [self.view addGestureRecognizer:self.screenEdgeGesture];
    } else {
        [self.view removeGestureRecognizer:self.screenEdgeGesture];
        CGRect tmp = activeEndFrame;
        activeEndFrame = inactiveInitialFrame;
        inactiveInitialFrame = tmp;
    }
    
    activeTableView.frame = activeInitialFrame;
    inactiveTableView.frame = inactiveInitialFrame;

    activeTableView.hidden = NO;
    inactiveTableView.hidden = NO;
    
    activeTableView.alpha = 1.0;
    inactiveTableView.alpha = 0.0;
    
    [UIView animateWithDuration:0.25 animations:^{
        activeTableView.frame = activeEndFrame;
        inactiveTableView.frame = inactiveEndFrame;
        
        activeTableView.alpha = 0.0;
        inactiveTableView.alpha = 1.0;
    } completion:^(BOOL finished) {
        activeTableView.hidden = YES;
    }];
}

#pragma mark - Dock Controller

+ (SBFloatingDockController *)floatingDockController {
    if (NSClassFromString(@"SBIconController") && [NSClassFromString(@"SBIconController") respondsToSelector:@selector(sharedInstance)]) {
        SBIconController *iconController = [NSClassFromString(@"SBIconController") sharedInstance];
        if ([iconController respondsToSelector:@selector(floatingDockController)]) {
            return [iconController floatingDockController];
        }
    }
    return nil;
}

+ (BOOL)dismissFloatingDockIfNeededWithCompletion:(void(^)())completion {
    SBFloatingDockController *dockController = [self floatingDockController];
    if ([dockController respondsToSelector:@selector(_dismissFloatingDockIfPresentedAnimated:completionHandler:)] && [dockController respondsToSelector:@selector(isFloatingDockPresented)]) {
        if ([dockController isFloatingDockPresented]) {
            [dockController _dismissFloatingDockIfPresentedAnimated:YES completionHandler:completion];
            return YES;
        }
    }
    return NO;
}

+ (void)presentFloatingDockIfNeeded {
    SBFloatingDockController *dockController = [self floatingDockController];
    if ([dockController respondsToSelector:@selector(_dismissFloatingDockIfPresentedAnimated:completionHandler:)]
        && [dockController respondsToSelector:@selector(isFloatingDockPresented)]) {
        if (![dockController isFloatingDockPresented]) {
            [dockController _presentFloatingDockIfDismissedAnimated:YES completionHandler:^{ }];
        }
    }
}

#pragma mark - Alert Helpers

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    [self showAlertFromViewController:nil title:title message:message cancelTitle:@"好"];
}

+ (void)showAlertFromViewController:(UIViewController *)viewController title:(NSString *)title message:(NSString *)message cancelTitle:(NSString *)cancelTitle {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:nil]];
    [viewController?:[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alertController animated:YES completion:nil];
}

@end
