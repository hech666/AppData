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
archive('suffix.zip',[('IconBundles/ClockIconBackgroundSquare-large.png',png),('IconBundles/com.example.app-large.png',png)])
archive('scale.zip',[('com.example.app@2x.png',png)])
archive('order1.zip',[('com.example.app-large@3x.png',png)])
archive('order2.zip',[('com.example.app@3x-large.png',png)])
archive('variants.zip',[('com.example.app.png',png+b'plain'),('com.example.app-large.png',png+b'large'),('com.example.app-large@3x.png',png+b'best')])
archive('variants-reverse.zip',[('com.example.app-large@3x.png',png+b'best'),('com.example.app-large.png',png+b'large'),('com.example.app.png',png+b'plain')])
archive('decoration.zip',[('ClockIconBackgroundSquare-large.png',png)])
source=Path('AppData/Classes/Icons/ADIconThemeZIP.m').read_text().replace('#import "ADIconOverrides.h"','#import <Foundation/Foundation.h>\nBOOL ADIconValidBundleIdentifier(NSString *s) { return [s containsString:@"."]; }')
source+='''
int main(void) { @autoreleasepool {
 NSArray *names = @[@"valid.zip", @"stored.zip", @"traversal.zip", @"duplicate.zip", @"invalid.zip", @"crc.zip", @"large.zip", @"suffix.zip", @"scale.zip", @"order1.zip", @"order2.zip", @"variants.zip", @"variants-reverse.zip", @"decoration.zip"];
 for (NSUInteger i=0; i<names.count; i++) {
  NSError *error=nil;
  NSData *data=[NSData dataWithContentsOfFile:[@"/tmp/appdata-zip-check" stringByAppendingPathComponent:names[i]]];
  NSDictionary *result=ADIconReadThemeZIP(data,&error);
  BOOL expected=i<2 || (i>=7 && i<=12);
  if ((result!=nil)!=expected || (!expected && !error)) { NSLog(@"FAIL %@",names[i]); return 1; }
  if (expected && (result.count != 1 || !result[@"com.example.app"])) return 2;
  if (i==11 || i==12) {
   NSData *value=result[@"com.example.app"];
   if (value.length<4 || memcmp((const char *)value.bytes+value.length-4,"best",4)) return 3;
  }
  NSLog(@"PASS %@",names[i]);
 }
} return 0; }
'''
(base/'check.m').write_text(source)
subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Foundation','-lz',str(base/'check.m'),'-o',str(base/'check')],check=True)
subprocess.run([str(base/'check')],check=True)
