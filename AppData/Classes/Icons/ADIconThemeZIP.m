#import "ADIconOverrides.h"
#import <zlib.h>
#import <sys/stat.h>
#import <string.h>

static uint16_t ADIconU16(const uint8_t *p) { return p[0] | (uint16_t)p[1] << 8; }
static uint32_t ADIconU32(const uint8_t *p) { return ADIconU16(p) | (uint32_t)ADIconU16(p+2) << 16; }
static NSDictionary *ADIconZIPError(NSError **error, NSString *text) {
    if (error) *error = [NSError errorWithDomain:@"ADIconThemeZIP" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];
    return nil;
}
NSDictionary<NSString *, NSData *> *ADIconReadThemeZIP(NSData *data, NSError **error) {
    const uint8_t *p = data.bytes; NSUInteger n = data.length;
    if (n < 22 || n > 128 * 1024 * 1024) return ADIconZIPError(error,@"ZIP 为空、损坏或超过 128 MB。");
    NSUInteger end = NSNotFound, lower = n > 65557 ? n-65557 : 0;
    for (NSUInteger i = n-22;; i--) {
        if (ADIconU32(p+i) == 0x06054b50 && i+22+ADIconU16(p+i+20) == n) { end = i; break; }
        if (i == lower) break;
    }
    if (end == NSNotFound) return ADIconZIPError(error,@"找不到 ZIP 中央目录。");
    uint16_t count = ADIconU16(p+end+10);
    uint32_t cdSize = ADIconU32(p+end+12), cdOffset = ADIconU32(p+end+16);
    if (ADIconU16(p+end+4) || ADIconU16(p+end+6) || ADIconU16(p+end+8) != count || count == 65535 || count > 4096 || cdOffset > end || cdSize > end-cdOffset)
        return ADIconZIPError(error,@"不支持分卷、ZIP64 或超过 4096 项的主题。");
    NSUInteger cursor = cdOffset, limit = cdOffset + cdSize, total = 0;
    NSMutableDictionary *result = [NSMutableDictionary new];
    NSMutableSet *foldedIDs = [NSMutableSet new];
    for (NSUInteger index = 0; index < count; index++) {
        if (cursor > limit || limit-cursor < 46 || ADIconU32(p+cursor) != 0x02014b50) return ADIconZIPError(error,@"ZIP 中央目录损坏。");
        const uint8_t *entry = p+cursor;
        uint16_t flags = ADIconU16(entry+8), method = ADIconU16(entry+10), nameLen = ADIconU16(entry+28), extraLen = ADIconU16(entry+30), commentLen = ADIconU16(entry+32);
        uint32_t crc = ADIconU32(entry+16), compressed = ADIconU32(entry+20), expanded = ADIconU32(entry+24), offset = ADIconU32(entry+42);
        NSUInteger record = 46+(NSUInteger)nameLen+extraLen+commentLen;
        if (record > limit-cursor || ADIconU16(entry+34)) return ADIconZIPError(error,@"ZIP 条目不完整或为分卷文件。");
        NSString *name = [[NSString alloc] initWithBytes:entry+46 length:nameLen encoding:NSUTF8StringEncoding];
        if (!name) name = [[NSString alloc] initWithBytes:entry+46 length:nameLen encoding:NSISOLatin1StringEncoding];
        cursor += record;
        NSArray *parts = [name componentsSeparatedByString:@"/"];
        mode_t type = (ADIconU32(entry+38) >> 16) & S_IFMT;
        if (!name.length || memchr(entry+46,0,nameLen) || [name hasPrefix:@"/"] || [name containsString:@"\\"] || [name containsString:@":"] || [parts containsObject:@".."] || [parts containsObject:@"."] || (type && type != S_IFREG && type != S_IFDIR))
            return ADIconZIPError(error,@"ZIP 包含不安全路径或符号链接。");
        if ([name hasSuffix:@"/"] || [parts containsObject:@"__MACOSX"] || [name.lastPathComponent hasPrefix:@"."] || ![name.pathExtension.lowercaseString isEqual:@"png"]) continue;
        NSString *identifier = name.lastPathComponent.stringByDeletingPathExtension;
        if (!ADIconValidBundleIdentifier(identifier)) return ADIconZIPError(error,[NSString stringWithFormat:@"PNG 文件名必须是 Bundle ID：%@",name]);
        if ([foldedIDs containsObject:identifier.lowercaseString]) return ADIconZIPError(error,[NSString stringWithFormat:@"主题存在重复 Bundle ID：%@",identifier]);
        if (flags & (1 | 64) || (method != 0 && method != 8) || !expanded || expanded > 16*1024*1024 || total+expanded > 128*1024*1024 || result.count >= 256)
            return ADIconZIPError(error,@"图标加密、压缩方式不支持或超过限制（256 张、每张 16 MB、合计 128 MB）。");
        if (offset > cdOffset || cdOffset-offset < 30 || ADIconU32(p+offset) != 0x04034b50) return ADIconZIPError(error,@"ZIP 本地文件头损坏。");
        const uint8_t *local = p+offset;
        NSUInteger localName = ADIconU16(local+26), localExtra = ADIconU16(local+28), header = 30+localName+localExtra;
        if (header > cdOffset-offset || compressed > cdOffset-offset-header || localName != nameLen || ADIconU16(local+6) != flags || ADIconU16(local+8) != method || memcmp(local+30, entry+46, nameLen)) return ADIconZIPError(error,@"ZIP 文件头与中央目录不一致。");
        const uint8_t *payload = local+header;
        NSMutableData *output = [NSMutableData dataWithLength:expanded];
        if (method == 0) {
            if (compressed != expanded) return ADIconZIPError(error,@"ZIP 未压缩条目长度不一致。");
            memcpy(output.mutableBytes,payload,expanded);
        } else {
            z_stream stream = {0}; stream.next_in = (Bytef *)payload; stream.avail_in = compressed; stream.next_out = output.mutableBytes; stream.avail_out = expanded;
            if (inflateInit2(&stream,-MAX_WBITS) != Z_OK) return ADIconZIPError(error,@"无法初始化 ZIP 解压缩。");
            int status = inflate(&stream,Z_FINISH);
            BOOL valid = status == Z_STREAM_END && stream.total_out == expanded && stream.total_in == compressed;
            inflateEnd(&stream);
            if (!valid) return ADIconZIPError(error,@"ZIP 图标数据损坏或长度不一致。");
        }
        static const uint8_t magic[] = {137,80,78,71,13,10,26,10};
        if (crc32(0,output.bytes,(uInt)output.length) != crc || output.length < 8 || memcmp(output.bytes,magic,8)) return ADIconZIPError(error,[NSString stringWithFormat:@"PNG 签名或 CRC 校验失败：%@",name]);
        result[identifier] = output; [foldedIDs addObject:identifier.lowercaseString]; total += expanded;
    }
    if (cursor != limit) return ADIconZIPError(error,@"ZIP 中央目录长度不一致。");
    if (!result.count) return ADIconZIPError(error,@"未找到图标。请将 PNG 命名为 com.example.app.png，可放在主题子目录中。");
    return result.copy;
}
