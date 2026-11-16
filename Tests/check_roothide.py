from pathlib import Path
import subprocess
base=Path('/tmp/ad-roothide-test');base.mkdir(exist_ok=True)
s=Path('AppData/Classes/Helpers/ADRootHideBridge.m').read_text()
h=Path('AppData/Classes/Helpers/ADRootHideBridge.h').read_text()
s=s.replace('#import "ADRootHideBridge.h"',h).replace('#import <rootless.h>','#define THEOS_PACKAGE_SCHEME_ROOTHIDE 1\n#define ROOT_PATH_NS(p) [@"/tmp/ad-roothide-test/root" stringByAppendingString:(p)]')
s+='''
#define CHECK(x) do { if (!(x)) { NSLog(@"FAIL line %d",__LINE__); return 1; } n++; } while(0)
int main(void) { @autoreleasepool {
 int n=0; NSError *e=nil; NSFileManager *fm=NSFileManager.defaultManager;
 NSString *root=@"/tmp/ad-roothide-test/root";
 [fm removeItemAtPath:root error:nil];
 NSString *exe=ROOT_PATH_NS(@"/Applications/RootHide.app/RootHide");
 [fm createDirectoryAtPath:exe.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
 [@"test" writeToFile:exe atomically:YES encoding:NSUTF8StringEncoding error:nil];
 NSString *path=ADRootHidePath();
 [fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
 CHECK(![ADRootHideBridge setBlacklisted:YES forIdentifier:@"com.test.app" bundlePath:@"/tmp/App.app" error:&e]);
 CHECK(![fm fileExistsAtPath:path]);
 NSDictionary *original=@{@"appconfig":@{@"com.test.other":@YES},@"whitelistMode":@YES,@"custom":@"keep"};
 [original writeToFile:path atomically:YES]; e=nil;
 CHECK([ADRootHideBridge setBlacklisted:YES forIdentifier:@"com.test.app" bundlePath:@"/tmp/App.app" error:&e]);
 CHECK([ADRootHideBridge blacklistedForIdentifier:@"com.test.app" error:&e]);
 NSDictionary *saved=[NSDictionary dictionaryWithContentsOfFile:path];
 CHECK([saved[@"appconfig"][@"com.test.other"] isEqual:@YES]);
 CHECK([saved[@"whitelistMode"] isEqual:@YES] && [saved[@"custom"] isEqual:@"keep"]);
 CHECK([ADRootHideBridge setBlacklisted:NO forIdentifier:@"com.test.app" bundlePath:@"/tmp/App.app" error:&e]);
 CHECK(![ADRootHideBridge blacklistedForIdentifier:@"com.test.app" error:&e]);
 NSMutableDictionary *disabled=[saved mutableCopy]; disabled[@"blacklistDisabled"]=@YES; [disabled writeToFile:path atomically:YES];
 CHECK(![ADRootHideBridge blacklistedForIdentifier:@"com.test.app" error:&e]);
 CHECK(![ADRootHideBridge setBlacklisted:YES forIdentifier:@"com.test.app" bundlePath:@"/tmp/App.app" error:&e]);
 CHECK([[NSDictionary dictionaryWithContentsOfFile:path] isEqual:disabled]);
 [@{@"appconfig":@"invalid"} writeToFile:path atomically:YES];
 CHECK(![ADRootHideBridge setBlacklisted:YES forIdentifier:@"com.test.app" bundlePath:@"/tmp/App.app" error:&e]);
 CHECK([[[NSDictionary dictionaryWithContentsOfFile:path] objectForKey:@"appconfig"] isEqual:@"invalid"]);
 NSLog(@"PASS %d RootHide configuration checks (isolated filesystem, no device changes)",n);
 } return 0; }
'''
(base/'check.m').write_text(s)
subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-framework','Foundation',str(base/'check.m'),'-o',str(base/'check')],check=True)
subprocess.run([str(base/'check')],check=True)
