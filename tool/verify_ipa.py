#!/usr/bin/env python3
"""Validate an iPhone IPA's payload; never treats a simulator bundle as installable."""
import json
from pathlib import Path
import plistlib
import sys
import struct
import zipfile

def verify(path):
    with zipfile.ZipFile(path) as archive:
        names=archive.namelist()
        plists=[n for n in names if n.startswith('Payload/') and n.count('/')==2 and n.endswith('.app/Info.plist')]
        if len(plists)!=1:raise ValueError('IPA must contain one Payload/*.app/Info.plist')
        info=plistlib.loads(archive.read(plists[0]));prefix=plists[0].rsplit('/',1)[0]
        if info.get('DTPlatformName')!='iphoneos':raise ValueError('An iPhoneOS build is required, not an iPhone Simulator build')
        executable=prefix+'/'+info['CFBundleExecutable'];binary=archive.read(executable);magic=binary[:4]
        if len(binary)<32:raise ValueError('Truncated Mach-O')
        if magic not in (b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca'):raise ValueError('Main executable is not Mach-O')
        if magic==b'\xcf\xfa\xed\xfe' and struct.unpack_from('<I',binary,4)[0]!=0x0100000c:raise ValueError('ARM64 device executable required')
        if archive.testzip() is not None:raise ValueError('Corrupt IPA')
        return {'bundle_id':info['CFBundleIdentifier'],'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'platform':info['DTPlatformName'],'payload':prefix,'signing':'unsigned build; must be signed locally before installation'}
if __name__=='__main__':
    result=verify(sys.argv[1]);print(json.dumps(result,ensure_ascii=False,indent=2))
    if len(sys.argv)>2:Path(sys.argv[2]).write_text(json.dumps(result,ensure_ascii=False,indent=2))
