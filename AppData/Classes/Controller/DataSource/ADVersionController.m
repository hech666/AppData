#import "ADVersionController.h"
#import <objc/message.h>
#import <dlfcn.h>

// Private selectors recovered from 2.7.5; each is checked before invocation.
static id ADVGet(id target, NSString *name) {
    SEL s = NSSelectorFromString(name);
    return [target respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(target, s) : nil;
}
static BOOL ADVBool(id target, NSString *name) {
    SEL s = NSSelectorFromString(name);
    return [target respondsToSelector:s] && ((BOOL (*)(id, SEL))objc_msgSend)(target, s);
}
static long long ADVNumber(id value) {
    return ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) ? [value longLongValue] : 0;
}
static NSString *ADVText(id value) {
    return [value isKindOfClass:NSString.class] ? value : ([value isKindOfClass:NSNumber.class] ? [value stringValue] : @"");
}
static id ADVLookup(Class cls, NSDictionary *dictionary) {
    id object = [cls alloc];
    SEL selector = NSSelectorFromString(@"initWithLookupDictionary:");
    return [object respondsToSelector:selector] ? ((id (*)(id, SEL, id))objc_msgSend)(object, selector, dictionary) : nil;
}
@interface ADVersionController ()
@property(nonatomic, copy) NSString *adv_identifier;
@property(nonatomic, strong) NSURL *adv_bundleURL;
@property(nonatomic, copy) NSString *adv_currentVersion;
@property(nonatomic, strong) NSArray<NSDictionary *> *adv_versions;
@property(nonatomic, strong) NSURLSessionDataTask *adv_task;
@property(nonatomic) long long adv_trackID;
@property(nonatomic) BOOL adv_busy;
@property(nonatomic) BOOL adv_cancelled;
@end

@implementation ADVersionController
- (instancetype)initWithBundleIdentifier:(NSString *)identifier bundleURL:(NSURL *)bundleURL currentVersion:(NSString *)version {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        _adv_identifier = [identifier copy]; _adv_bundleURL = bundleURL;
        _adv_currentVersion = [version copy]; _adv_versions = @[];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"软件升降级";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(adv_close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(adv_load)];
    [self adv_load];
}
- (void)adv_close {
    if (self.adv_busy) return;
    self.adv_cancelled = YES;
    [self.adv_task cancel];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)adv_status:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 300, 85)];
    label.numberOfLines = 0; label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:14]; label.text = text;
    self.tableView.tableHeaderView = label;
}
- (void)adv_message:(NSString *)text {
    if (self.adv_cancelled || self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"软件升降级" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)adv_verifyOwnership {
    dlopen("/System/Library/PrivateFrameworks/StoreServices.framework/StoreServices", RTLD_LAZY);
    NSString *active = nil;
    @try {
        id accounts = ADVGet(ADVGet(NSClassFromString(@"SSAccountStore"), @"defaultStore"), @"accounts");
        if ([accounts isKindOfClass:NSArray.class]) {
            for (id account in accounts) {
                if (ADVBool(account, @"isActive") && !ADVBool(account, @"isLocalAccount")) {
                    active = ADVText(ADVGet(account, @"accountName")); break;
                }
            }
        }
    } @catch (NSException *exception) { active = nil; }
    NSString *metadataPath = [[self.adv_bundleURL.path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"iTunesMetadata.plist"];
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
    id info = metadata[@"com.apple.iTunesStore.downloadInfo"];
    id accountInfo = [info isKindOfClass:NSDictionary.class] ? info[@"accountInfo"] : nil;
    NSString *purchaser = [accountInfo isKindOfClass:NSDictionary.class] ? ADVText(accountInfo[@"AppleID"]) : nil;
    if (!active.length || !purchaser.length) {
        [self adv_message:@"无法核对购买账号。请登录 App Store，并确认此应用是通过 App Store 获取的应用。"];
        return NO;
    }
    if ([active caseInsensitiveCompare:purchaser] != NSOrderedSame) {
        [self adv_message:@"当前 App Store 账号与此应用的购买账号不一致。请切换至获取此应用的账号后重试。"];
        return NO;
    }
    return YES;
}
- (void)adv_request:(NSURL *)url completion:(void (^)(id, NSError *))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 25;
    __weak typeof(self) weakSelf = self;
    self.adv_task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSError *failure = error;
        id json = nil;
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (!failure && status != 200) failure = [NSError errorWithDomain:@"ADVersion" code:status userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"服务器返回 HTTP %ld", (long)status]}];
        if (!failure && data) json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&failure];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf && !weakSelf.adv_cancelled) completion(json, failure);
        });
    }];
    [self.adv_task resume];
}
- (void)adv_load {
    if (self.adv_busy) return;
    [self.adv_task cancel];
    self.adv_versions = @[]; [self.tableView reloadData];
    if (![self adv_verifyOwnership]) { [self adv_status:@"账号检查未通过，登录正确账号后点击刷新。"]; return; }
    [self adv_status:@"正在查询应用和历史版本…"];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    NSString *region = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode] ?: @"cn";
    NSMutableOrderedSet *countries = [NSMutableOrderedSet orderedSetWithArray:@[region.lowercaseString, @"cn", @"us", @"hk", @"tw", @"jp", @"gb"]];
    [self adv_lookup:countries.array index:0];
}
- (void)adv_lookup:(NSArray<NSString *> *)countries index:(NSUInteger)index {
    if (index >= countries.count) {
        self.navigationItem.rightBarButtonItem.enabled = YES;
        [self adv_status:@"未找到此应用的 App Store ID，请确认应用仍在商店上架后重试。"]; return;
    }
    NSURLComponents *url = [NSURLComponents componentsWithString:@"https://itunes.apple.com/lookup"];
    url.queryItems = @[[NSURLQueryItem queryItemWithName:@"bundleId" value:self.adv_identifier], [NSURLQueryItem queryItemWithName:@"limit" value:@"1"], [NSURLQueryItem queryItemWithName:@"media" value:@"software"], [NSURLQueryItem queryItemWithName:@"country" value:countries[index]]];
    [self adv_request:url.URL completion:^(id json, NSError *error) {
        if (error) { self.navigationItem.rightBarButtonItem.enabled = YES; [self adv_status:error.localizedDescription]; return; }
        id results = [json isKindOfClass:NSDictionary.class] ? json[@"results"] : nil;
        long long trackID = 0;
        if ([results isKindOfClass:NSArray.class]) for (id row in results) {
            if ([row isKindOfClass:NSDictionary.class] && [row[@"bundleId"] isEqual:self.adv_identifier]) { trackID = ADVNumber(row[@"trackId"]); break; }
        }
        if (trackID <= 0) { [self adv_lookup:countries index:index + 1]; return; }
        self.adv_trackID = trackID;
        [self adv_history];
    }];
}
- (void)adv_history {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://iosdump.apdoilaan.work/history/%lld", self.adv_trackID]];
    [self adv_request:url completion:^(id json, NSError *error) {
        self.navigationItem.rightBarButtonItem.enabled = YES;
        if (error) { [self adv_status:error.localizedDescription]; return; }
        id data = [json isKindOfClass:NSDictionary.class] ? json[@"data"] : nil;
        NSMutableArray *rows = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        if ([data isKindOfClass:NSArray.class]) for (id row in data) {
            if (![row isKindOfClass:NSDictionary.class]) continue;
            long long versionID = ADVNumber(row[@"external_identifier"]);
            if (versionID <= 0 || [seen containsObject:@(versionID)]) continue;
            [seen addObject:@(versionID)]; [rows addObject:row];
        }
        self.adv_versions = [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [ADVText(b[@"created_at"]) compare:ADVText(a[@"created_at"]) options:NSNumericSearch];
        }];
        [self.tableView reloadData];
        [self adv_status:rows.count ? [NSString stringWithFormat:@"当前版本：%@\n选择目标版本以升级、降级或重新安装。", self.adv_currentVersion ?: @"未知"] : @"未找到可用的历史版本，请稍后刷新重试。"];
    }];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.adv_versions.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ADVersionRow"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ADVersionRow"];
    NSDictionary *row = self.adv_versions[indexPath.row];
    NSString *version = ADVText(row[@"version"]);
    cell.textLabel.text = version.length ? version : @"未标注版本号";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  ·  ID：%lld", ADVText(row[@"created_at"]), ADVNumber(row[@"external_identifier"])];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.adv_busy) return;
    NSDictionary *row = self.adv_versions[indexPath.row];
    NSString *version = ADVText(row[@"version"]);
    long long versionID = ADVNumber(row[@"external_identifier"]);
    NSString *message = [NSString stringWithFormat:@"当前版本：%@\n目标版本：%@\n内部版本 ID：%lld\n\n将通过 App Store 请求安装。降级后旧版本可能无法读取新版数据，建议先备份。", self.adv_currentVersion ?: @"未知", version.length ? version : @"未标注", versionID];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认安装版本" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"安装此版本" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self adv_verifyOwnership]) [self adv_install:versionID];
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)adv_finish:(NSString *)message {
    self.adv_busy = NO;
    self.navigationItem.leftBarButtonItem.enabled = YES;
    self.navigationItem.rightBarButtonItem.enabled = YES;
    [self adv_status:message];
}
- (NSString *)adv_parameters:(long long)versionID {
    return [NSString stringWithFormat:@"productType=C&price=0&salableAdamId=%lld&pricingParameters=pricingParameter&appExtVrsId=%lld&clientBuyId=1&installed=0&trolled=1", self.adv_trackID, versionID];
}
- (void)adv_install:(long long)versionID {
    if (self.adv_busy || self.adv_trackID <= 0 || versionID <= 0) return;
    self.adv_busy = YES;
    self.navigationItem.leftBarButtonItem.enabled = NO;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self adv_status:@"正在提交安装请求…"];
    dlopen("/System/Library/PrivateFrameworks/AppStoreDaemon.framework/AppStoreDaemon", RTLD_LAZY);
    @try {
        id purchase = [[NSClassFromString(@"ASDPurchase") alloc] init];
        id manager = ADVGet(NSClassFromString(@"ASDPurchaseManager"), @"sharedManager");
        SEL start = NSSelectorFromString(@"startPurchase:withResultHandler:");
        NSArray *objectSelectors = @[@"setItemID:", @"setBundleID:", @"setBuyParameters:"];
        NSArray *boolSelectors = @[@"setIsUpdate:", @"setIsBackgroundUpdate:", @"setIsRedownload:", @"setCreatesJobs:"];
        BOOL supported = purchase && [manager respondsToSelector:start];
        for (NSString *name in [objectSelectors arrayByAddingObjectsFromArray:boolSelectors]) supported = supported && [purchase respondsToSelector:NSSelectorFromString(name)];
        if (!supported) { [self adv_fallback:versionID]; return; }
        NSArray *values = @[@(self.adv_trackID), self.adv_identifier, [self adv_parameters:versionID]];
        for (NSUInteger i = 0; i < objectSelectors.count; i++) ((void (*)(id, SEL, id))objc_msgSend)(purchase, NSSelectorFromString(objectSelectors[i]), values[i]);
        for (NSUInteger i = 0; i < boolSelectors.count; i++) ((void (*)(id, SEL, BOOL))objc_msgSend)(purchase, NSSelectorFromString(boolSelectors[i]), i != 1);
        SEL lock = NSSelectorFromString(@"setDisplaysOnLockScreen:");
        if ([purchase respondsToSelector:lock]) ((void (*)(id, SEL, BOOL))objc_msgSend)(purchase, lock, YES);
        ((void (*)(id, SEL, id, id))objc_msgSend)(manager, start, purchase, ^(id result, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                id failure = error;
                @try { if (!failure) failure = ADVGet(result, @"error"); }
                @catch (NSException *exception) { failure = exception; }
                if (failure) [self adv_fallback:versionID];
                else [self adv_finish:@"安装请求已提交，请查看桌面下载进度或 App Store 提示。此状态不代表安装已经完成。"];
            });
        });
    } @catch (NSException *exception) { [self adv_fallback:versionID]; }
}
- (void)adv_fallback:(long long)versionID {
    dlopen("/System/Library/PrivateFrameworks/StoreKitUI.framework/StoreKitUI", RTLD_LAZY);
    @try {
        id offer = ADVLookup(NSClassFromString(@"SKUIItemOffer"), @{@"buyParams":[self adv_parameters:versionID]});
        id item = ADVLookup(NSClassFromString(@"SKUIItem"), @{@"_itemOffer":[NSString stringWithFormat:@"%lld", self.adv_trackID]});
        id center = ADVGet(NSClassFromString(@"SKUIItemStateCenter"), @"defaultCenter");
        id context = ADVGet(NSClassFromString(@"SKUIClientContext"), @"defaultContext");
        SEL create = NSSelectorFromString(@"_newPurchasesWithItems:");
        SEL perform = NSSelectorFromString(@"_performPurchases:hasBundlePurchase:withClientContext:completionBlock:");
        if (!offer || !item || ![center respondsToSelector:create] || ![center respondsToSelector:perform]) {
            [self adv_finish:@"当前系统的安装接口不可用，无法提交指定版本安装请求。"]; return;
        }
        [item setValue:offer forKey:@"_itemOffer"];
        [item setValue:@"iosSoftware" forKey:@"_itemKindString"];
        [item setValue:@(versionID) forKey:@"_versionIdentifier"];
        id purchases = ((id (*)(id, SEL, id))objc_msgSend)(center, create, @[item]);
        if (![purchases isKindOfClass:NSArray.class] || ![purchases count]) {
            [self adv_finish:@"未能创建兼容安装请求，请确认 App Store 登录状态后重试。"]; return;
        }
        // The reference does not establish this completion block's arguments.
        // Accept no arguments and rely on App Store for final download status.
        ((void (*)(id, SEL, id, BOOL, id, id))objc_msgSend)(center, perform, purchases, NO, context, ^{});
        [self adv_finish:@"已通过兼容接口提交请求，请查看 App Store 或桌面下载进度。此状态不代表安装已经完成。"];
    } @catch (NSException *exception) {
        [self adv_finish:@"兼容安装接口执行失败，请检查系统版本及 App Store 登录状态。"];
    }
}
@end
