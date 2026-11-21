import pathlib,struct,hashlib,plistlib,json,subprocess
root=pathlib.Path('/tmp/appdata-package')
results=[]
for relative in ['Library/MobileSubstrate/DynamicLibraries/AppData.dylib']:
 p=root/relative
 assert p.is_file(),relative
 b=p.read_bytes(); assert struct.unpack_from('<I',b)[0]==0xfeedfacf, 'expected thin Mach-O'
 cpu,sub=struct.unpack_from('<II',b,4)
 assert (cpu,sub)==(0x0100000c,0x80000002), 'expected modern arm64e only'
 slices=[]
 for d in [b]:
  assert struct.unpack_from('<I',d)[0]==0xfeedfacf
  assert struct.unpack_from('<II',d,4)==(cpu,sub)
  pos=32;sig=None
  for _ in range(struct.unpack_from('<I',d,16)[0]):
   cmd,sz=struct.unpack_from('<II',d,pos)
   if cmd==0x1d:sig=struct.unpack_from('<II',d,pos+8)
   pos+=sz
  assert sig,'missing signature'
  so,ss=sig;magic,length,count=struct.unpack_from('>III',d,so);assert magic==0xfade0cc0
  checked=0
  for j in range(count):
   slot,delta=struct.unpack_from('>II',d,so+12+j*8);cd=so+delta
   if struct.unpack_from('>I',d,cd)[0]!=0xfade0c02:continue
   ho,ident,special,pages,limit=struct.unpack_from('>IIIII',d,cd+16)
   hs,ht,platform,ps=struct.unpack_from('BBBB',d,cd+36)
   assert ht in [1,2,3],ht
   for page in range(pages):
    raw=d[page*(1<<ps):min(limit,(page+1)*(1<<ps))]
    digest=(hashlib.sha1(raw) if ht==1 else hashlib.sha256(raw)).digest()[:hs]
    assert digest==d[cd+ho+page*hs:cd+ho+(page+1)*hs],(relative,sub,page)
   checked+=pages
  assert checked
  slices.append({'subtype':hex(sub),'verified_page_hashes':checked})
 assert len(slices)==1 and slices[0]['subtype']=='0x80000002'
 results.append({'file':relative,'sha256':hashlib.sha256(b).hexdigest(),'slices':slices})
assert not (root/'Library/PreferenceBundles').exists()
assert not (root/'Library/PreferenceLoader').exists()
assert (root/'Library/Application Support/AppData/Resources.bundle/VersionControl.png').is_file()
assert (root/'Library/Application Support/AppData/Resources.bundle/AppDataIcon@2x.png').is_file()
pathlib.Path('packages/verification.json').write_text(json.dumps(results,indent=2))
print(json.dumps(results,indent=2))
