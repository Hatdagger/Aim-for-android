#!/usr/bin/env python3
"""Generate and patch the platform folders.

Run from the repo root (CI does this automatically):

    flutter create --project-name aim_for_android --org com.hatdagger \
        --platforms android,linux,windows .
    python3 tool/setup_platforms.py

It adds the Android foreground service, notification and network permissions,
and names the app "AIM" on every platform. Safe to run more than once.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OVERLAY = os.path.join(ROOT, 'android_overlay')


def read(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


def write(p, s):
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        f.write(s)


def patch_android():
    acts = glob.glob(os.path.join(ROOT, 'android', 'app', 'src', 'main', 'kotlin', '**', 'MainActivity.kt'), recursive=True)
    if not acts:
        sys.exit('MainActivity.kt not found - run flutter create first')
    act = acts[0]
    m = re.search(r'^package\s+([\w.]+)', read(act), re.M)
    pkg = m.group(1) if m else 'com.hatdagger.aim_for_android'
    folder = os.path.dirname(act)
    for name in ('MainActivity.kt', 'AimConnectionService.kt'):
        write(os.path.join(folder, name), read(os.path.join(OVERLAY, name)).replace('__PACKAGE__', pkg))

    man_p = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')
    man = read(man_p)
    perms = [
        'android.permission.INTERNET',
        'android.permission.ACCESS_NETWORK_STATE',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
        'android.permission.WAKE_LOCK',
        'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        'android.permission.VIBRATE',
        'android.permission.REQUEST_INSTALL_PACKAGES',  # in-app updates
        'android.permission.UPDATE_PACKAGES_WITHOUT_USER_ACTION',  # later updates without a prompt (Android 12+)
    ]
    add = ''.join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in man)
    if add:
        man = man.replace('<application', add + '    <application', 1)
    man = re.sub(r'android:label="[^"]*"', 'android:label="AIM"', man, count=1)
    if 'AimConnectionService' not in man:
        service = (
            f'        <service android:name="{pkg}.AimConnectionService"\n'
            '            android:exported="false"\n'
            '            android:foregroundServiceType="specialUse">\n'
            '            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"\n'
            '                android:value="Keeps an instant messaging connection signed on"/>\n'
            '        </service>\n'
        )
        man = man.replace('    </application>', service + '    </application>', 1)
    if 'android:scheme="aim"' not in man:
        link_filter = (
            '            <intent-filter>\n'
            '                <action android:name="android.intent.action.VIEW"/>\n'
            '                <category android:name="android.intent.category.DEFAULT"/>\n'
            '                <category android:name="android.intent.category.BROWSABLE"/>\n'
            '                <data android:scheme="aim" android:host="invite"/>\n'
            '            </intent-filter>\n'
        )
        man = man.replace('        </activity>', link_filter + '        </activity>', 1)
    write(man_p, man)
    patch_signing()
    print('android: patched', pkg)


def patch_signing():
    """Sign every build with the same private key, so updates install over the old app.

    CI writes the key from the ANDROID_KEYSTORE secret to a temp file and passes its
    path and password in AIM_KEYSTORE / AIM_KEY_PASSWORD. Without a key the build
    stops instead of quietly using a throwaway key (which breaks updating).
    """
    ks = os.environ.get('AIM_KEYSTORE', '')
    pw = os.environ.get('AIM_KEY_PASSWORD', '')
    if not ks or not os.path.exists(ks) or not pw:
        if os.environ.get('CI'):
            sys.exit('Signing key missing: add the ANDROID_KEYSTORE and ANDROID_KEY_PASSWORD '
                     'repository secrets (Settings > Secrets and variables > Actions).')
        print('android: no signing key given, local build uses the debug key')
        return
    ks = ks.replace('\\', '/')
    pw_esc = pw.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$')
    kts = os.path.join(ROOT, 'android', 'app', 'build.gradle.kts')
    groovy = os.path.join(ROOT, 'android', 'app', 'build.gradle')
    if os.path.exists(kts):
        p, s = kts, read(kts)
        block = (
            '    signingConfigs {\n'
            '        create("aim") {\n'
            f'            storeFile = file("{ks}")\n'
            f'            storePassword = "{pw_esc}"\n'
            '            keyAlias = "aim"\n'
            f'            keyPassword = "{pw_esc}"\n'
            '        }\n'
            '    }\n'
        )
        use = 'signingConfig = signingConfigs.getByName("aim")'
        s = re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', use, s)
    elif os.path.exists(groovy):
        p, s = groovy, read(groovy)
        block = (
            '    signingConfigs {\n'
            '        aim {\n'
            f'            storeFile file("{ks}")\n'
            f'            storePassword "{pw_esc}"\n'
            '            keyAlias "aim"\n'
            f'            keyPassword "{pw_esc}"\n'
            '        }\n'
            '    }\n'
        )
        use = 'signingConfig signingConfigs.aim'
        s = re.sub(r'signingConfig\s+signingConfigs\.debug', use, s)
    else:
        sys.exit('android/app/build.gradle(.kts) not found')
    if 'signingConfigs {' not in s:
        s = s.replace('    buildTypes {', block + '    buildTypes {', 1)
    if use not in s:
        sys.exit('could not set the release signing key in ' + p)
    write(p, s)
    print('android: release builds signed with the private AIM key')


def patch_desktop():
    lin = os.path.join(ROOT, 'linux', 'runner', 'my_application.cc')
    if not os.path.exists(lin):
        lin = os.path.join(ROOT, 'linux', 'my_application.cc')
    if os.path.exists(lin):
        s = read(lin).replace('"aim_for_android"', '"AIM"')
        write(lin, s)
        print('linux: patched')
    cm = os.path.join(ROOT, 'linux', 'CMakeLists.txt')
    if os.path.exists(cm):
        s = read(cm)
        # Newer clang rejects old headers bundled by some plugins under -Werror.
        if '-Wno-deprecated-literal-operator' not in s:
            s = s.replace('-Wall -Werror', '-Wall -Werror -Wno-deprecated-literal-operator')
            write(cm, s)
            print('linux: relaxed plugin warning')
    win = os.path.join(ROOT, 'windows', 'runner', 'main.cpp')
    if os.path.exists(win):
        s = read(win).replace('L"aim_for_android"', 'L"AIM"')
        write(win, s)
        print('windows: patched')


if __name__ == '__main__':
    if os.path.isdir(os.path.join(ROOT, 'android')):
        patch_android()
    patch_desktop()
