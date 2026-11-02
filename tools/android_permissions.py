#!/usr/bin/env python3
"""Add the permissions Lumen needs to a generated AndroidManifest.xml.

The repo does not commit an android/ folder - it is produced by `flutter create`
on each build, which means every build starts from a bare manifest with no
storage permission. That is why an installed APK asked for nothing and found no
photos.

    python3 tools/android_permissions.py [repo-root]

Run it after `flutter create --platforms=android .` and before `flutter build`.
Idempotent: running it twice changes nothing.
"""
import os
import re
import sys

PERMISSIONS = [
    ('android.permission.READ_MEDIA_IMAGES', None,
     'Android 13+: read photos without the blanket storage grant'),
    ('android.permission.READ_MEDIA_VISUAL_USER_SELECTED', None,
     'Android 14+: honour a partial photo selection'),
    ('android.permission.READ_EXTERNAL_STORAGE', '32',
     'Android 12 and below'),
    ('android.permission.ACCESS_MEDIA_LOCATION', None,
     'read GPS from EXIF, which is gated separately since Android 10'),
    ('android.permission.INTERNET', None,
     'bind the LAN gallery server. Nothing in the app dials out'),
    ('android.permission.ACCESS_NETWORK_STATE', None,
     'report whether a local network exists'),
]


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    path = os.path.join(root, "android", "app", "src", "main", "AndroidManifest.xml")
    if not os.path.isfile(path):
        print(f"no manifest at {path} - run flutter create first")
        return 1

    src = open(path, encoding="utf-8").read()
    original = src

    block = []
    for name, max_sdk, comment in PERMISSIONS:
        attr = f'\n        android:maxSdkVersion="{max_sdk}"' if max_sdk else ""
        block.append(
            f"    <!-- {comment} -->\n"
            f'    <uses-permission android:name="{name}"{attr}/>'
        )

    missing = [b for b in block if b.split('android:name="')[1].split('"')[0]
               not in src]
    if missing:
        if "</manifest>" not in src:
            print("manifest has no </manifest> - refusing to guess")
            return 1
        src = src.replace(
            "</manifest>",
            "\n" + "\n".join(missing) + "\n\n</manifest>",
            1,
        )

    # The LAN gallery is plain HTTP on the user's own network.
    if "usesCleartextTraffic" not in src:
        src = re.sub(
            r"<application(\s)",
            '<application android:usesCleartextTraffic="true"\\1',
            src,
            count=1,
        )

    if src == original:
        print("manifest already correct")
        return 0

    open(path, "w", encoding="utf-8").write(src)
    added = len(missing)
    print(f"manifest updated: {added} permission(s) added, cleartext enabled")
    return 0


if __name__ == "__main__":
    sys.exit(main())
