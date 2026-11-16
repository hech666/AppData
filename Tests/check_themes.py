from pathlib import Path
import subprocess
base=Path('/tmp/appdata-theme-check');base.mkdir(exist_ok=True)
r=Path('AppData/Classes/Icons')
h=(r/'ADIconOverrides.h').read_text().split('// ZIP reader:')[0]
h=h.replace('#import <UIKit/UIKit.h>','#import <Foundation/Foundation.h>\n#define UIImage NSData')
h='\n'.join(l for l in h.splitlines() if 'ADIconOriginalPreview' not in l and 'imageForBundleIdentifier:' not in l)+'\nNS_ASSUME_NONNULL_END\n'
s=(r/'ADIconOverrideStore.m').read_text().replace('#import "ADIconOverrides.h"',h).replace('#import <ImageIO/ImageIO.h>','').replace('#import <rootless.h>','')
a=s.index('NSString *ADIconOverridesDirectory(void) {');b=s.index('static UIImage *ADIconDecode',a)
s=s[:a]+'NSString *ADIconOverridesDirectory(void) { return @"/tmp/appdata-theme-check/state"; }\n'+s[b:]
a=s.index('static UIImage *ADIconDecode');b=s.index('static BOOL ADIconValidFiles',a)
s=s[:a]+'static UIImage *ADIconDecode(NSData *data) { return data.length && ((const char *)data.bytes)[0] == 65 ? data : nil; }\nstatic NSData *UIImagePNGRepresentation(UIImage *image) { return image; }\n'+s[b:]
a=s.index('- (UIImage *)imageForBundleIdentifier:');s=s[:a]+'@end\n'
s+='''
#define CHECK(x) do { if (!(x)) { NSLog(@"FAIL line %d",__LINE__); return 1; } checks++; } while(0)
int main(void) { @autoreleasepool {
 int checks=0; NSError *e=nil; NSFileManager *fm=NSFileManager.defaultManager;
 NSString *root=ADIconOverridesDirectory(), *path=[root stringByAppendingPathComponent:@"ADIconState.plist"];
 [fm removeItemAtPath:root error:nil]; [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
 NSData *png=[@"A-image" dataUsingEncoding:NSUTF8StringEncoding];
 [png writeToFile:[root stringByAppendingPathComponent:@"legacy.png"] atomically:YES];
 [@{@"enabled":@YES,@"files":@{@"com.test.old":@"legacy.png"}} writeToFile:path atomically:YES];
 ADIconOverrideStore *store=[ADIconOverrideStore new];
 CHECK(store.themes.count==1 && [store.activeThemeIdentifier isEqual:@"legacy"]);
 CHECK([store importPNGData:@{@"com.test.one":png} themeName:@"One" error:&e]);
 NSString *one=store.activeThemeIdentifier;
 CHECK(store.themes.count==2 && [fm fileExistsAtPath:[root stringByAppendingPathComponent:@"legacy.png"]]);
 CHECK(![store hasOverrideForBundleIdentifier:@"com.test.old"]);
 CHECK([store importPNGData:@{@"com.test.two":png} themeName:@"Two" error:&e]);
 NSString *two=store.activeThemeIdentifier;
 CHECK(store.themes.count==3 && ![store hasOverrideForBundleIdentifier:@"com.test.one"]);
 CHECK([store selectThemeWithIdentifier:one error:&e]);
 CHECK([store hasOverrideForBundleIdentifier:@"com.test.one"] && ![store hasOverrideForBundleIdentifier:@"com.test.two"]);
 CHECK([store saveImageData:png forBundleIdentifier:@"com.test.custom" error:&e]);
 CHECK([store selectThemeWithIdentifier:two error:&e] && ![store hasOverrideForBundleIdentifier:@"com.test.custom"]);
 CHECK([store renameThemeWithIdentifier:one name:@"Renamed" error:&e]);
 CHECK([store restoreBundleIdentifier:nil error:&e] && !store.activeThemeIdentifier && store.themes.count==3);
 CHECK([store selectThemeWithIdentifier:one error:&e] && [store hasOverrideForBundleIdentifier:@"com.test.custom"]);
 CHECK([store restoreBundleIdentifier:@"com.test.custom" error:&e] && ![store hasOverrideForBundleIdentifier:@"com.test.custom"]);
 CHECK([store deleteThemeWithIdentifier:two error:&e] && [store.activeThemeIdentifier isEqual:one]);
 CHECK([store deleteThemeWithIdentifier:one error:&e] && !store.activeThemeIdentifier);
 CHECK([store selectThemeWithIdentifier:@"legacy" error:&e] && store.count==1);
 [fm removeItemAtPath:[root stringByAppendingPathComponent:@"legacy.png"] error:nil];
 e=nil; CHECK(![store selectThemeWithIdentifier:@"legacy" error:&e] && e.localizedDescription.length);
 e=nil; CHECK(![store importPNGData:@{@"com.test.bad":[@"bad" dataUsingEncoding:NSUTF8StringEncoding]} error:&e] && e.localizedDescription.length);
 CHECK(store.themes.count==1);
 [@{@"version":@99} writeToFile:path atomically:YES];
 store=[ADIconOverrideStore new]; e=nil;
 CHECK(![store setOverrideEnabled:NO error:&e] && e.localizedDescription.length);
 CHECK([[NSDictionary dictionaryWithContentsOfFile:path][@"version"] isEqual:@99]);
 NSLog(@"PASS %d theme state/file checks (image codec stubbed; actual store implementation)",checks);
 } return 0; }
'''
(base/'check.m').write_text(s)
subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-framework','Foundation',str(base/'check.m'),'-o',str(base/'check')],check=True)
subprocess.run([str(base/'check')],check=True)
