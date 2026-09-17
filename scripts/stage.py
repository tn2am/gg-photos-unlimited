#!/usr/bin/env python3
import pathlib, plistlib, sys
stage=pathlib.Path(sys.argv[1]);prefix=sys.argv[2].rstrip('/')
# Theos adds the rootless prefix to the entire stage during internal-package.
root=stage
def plist(path,data):
    path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(plistlib.dumps(data))
service={'Label':'dev.tqmane.gunshot','ProgramArguments':[prefix+'/usr/libexec/gotohpd'],'UserName':'mobile','GroupName':'mobile','RunAtLoad':True,'KeepAlive':True,'ThrottleInterval':10,'MachServices':{'dev.tqmane.gunshot.service':True,'dev.tqmane.gunshot.discovery':True},'ProcessType':'Background','Umask':63}
plist(root/'Library/LaunchDaemons/dev.tqmane.gunshot.plist',service)
# Installed by the package manager as root; never writable by mobile.
# No wildcard process IDs, filesystem grants or access to unrelated services.
profile=root/'Library/libSandy/dev.tqmane.gunshot.ipc.plist'
plist(profile,{'AllowedProcesses':['com.google.photos','com.apple.mobileslideshow'],
               # Mirror sandyd's own two-class grant. A process may accept only
               # the global-name class; a returned token alone is not access.
               'Extensions':[{'type':'mach','extension_class':extension_class,'mach_name':name}
                             for name in ('dev.tqmane.gunshot.service','dev.tqmane.gunshot.discovery')
                             for extension_class in ('com.apple.app-sandbox.mach',
                                                     'com.apple.security.exception.mach-lookup.global-name')]})
profile.chmod(0o644)
control=stage/'DEBIAN';control.mkdir(parents=True,exist_ok=True)
launch=prefix+'/Library/LaunchDaemons/dev.tqmane.gunshot.plist'
# Package root only; persistent user data always stays under /var/mobile.
post=f'''#!/bin/sh
set -eu
if [ "${{1:-}}" = configure ]; then
 install -d -m 700 -o mobile -g mobile '/var/mobile/Library/Application Support/GoToHP'
 launchctl bootout system '{launch}' 2>/dev/null || true
 launchctl bootstrap system '{launch}'
fi
'''
pre=f'''#!/bin/sh
set -eu
launchctl bootout system '{launch}' 2>/dev/null || true
'''
for name,body in [('postinst',post),('prerm',pre)]:
    p=control/name;p.write_text(body);p.chmod(0o755)

notice=root/'usr/share/doc/dev.tqmane.gunshot/ThirdPartyNotices.txt'
notice.parent.mkdir(parents=True,exist_ok=True)
notice.write_bytes(pathlib.Path('.build/ThirdPartyNotices.txt').read_bytes())
