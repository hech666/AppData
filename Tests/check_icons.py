from pathlib import Path
import zipfile,struct,subprocess
base=Path('/tmp/appdata-zip-check');base.mkdir(exist_ok=True)
png=b'\x89PNG\r\n\x1a\n'+b'test fixture'
def archive(name,entries,compress=zipfile.ZIP_DEFLATED):
 with zipfile.ZipFile(base/name,'w',compression=compress) as z:
  for filename,data in entries:z.writestr(filename,data)
archive('valid.zip',[('Theme/IconBundles/com.example.app.png',png)])
archive('stored.zip',[('com.example.app.png',png)],zipfile.ZIP_STORED)
archive('traversal.zip',[('../com.example.app.png',png)])
archive('duplicate.zip',[('a/com.example.app.png',png),('b/com.example.app.png',png)])
archive('invalid.zip',[('com.example.app.png',b'not png')])
archive('crc.zip',[('com.example.app.png',png)],zipfile.ZIP_STORED)
b=bytearray((base/'crc.zip').read_bytes());b[30+len('com.example.app.png')+8]^=1;(base/'crc.zip').write_bytes(b)
archive('large.zip',[('com.example.app.png',png)],zipfile.ZIP_STORED)
b=bytearray((base/'large.zip').read_bytes());p=b.index(b'PK\x01\x02');struct.pack_into('<I',b,p+24,17*1024*1024);(base/'large.zip').write_bytes(b)
source=Path('AppData/Classes/Icons/ADIconThemeZIP.m').read_text().replace('#import "ADIconOverrides.h"','#import <Foundation/Foundation.h>\nBOOL ADIconValidBundleIdentifier(NSString *s) { return [s containsString:@"."]; }')
source+='''
int main(void) { @autoreleasepool {
 NSArray *names = @[@"valid.zip", @"stored.zip", @"traversal.zip", @"duplicate.zip", @"invalid.zip", @"crc.zip", @"large.zip"];
 for (NSUInteger i=0; i<names.count; i++) {
  NSError *error=nil;
  NSData *data=[NSData dataWithContentsOfFile:[@"/tmp/appdata-zip-check" stringByAppendingPathComponent:names[i]]];
  NSDictionary *result=ADIconReadThemeZIP(data,&error);
  BOOL expected=i<2;
  if ((result!=nil)!=expected || (!expected && !error)) { NSLog(@"FAIL %@",names[i]); return 1; }
  NSLog(@"PASS %@",names[i]);
 }
} return 0; }
'''
(base/'check.m').write_text(source)
subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Foundation','-lz',str(base/'check.m'),'-o',str(base/'check')],check=True)
subprocess.run([str(base/'check')],check=True)
