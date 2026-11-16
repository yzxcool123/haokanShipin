#!/usr/bin/env bash
# 在已安装 Flutter 的电脑上运行，生成 Android / iOS 工程并补上网络权限。
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create . --project-name aikan_yingshi --org com.aikan --platforms=android,ios

python3 - <<'PY'
from pathlib import Path
import re

display = "爱看影视"

manifest = Path("android/app/src/main/AndroidManifest.xml")
if manifest.exists():
    text = manifest.read_text(encoding="utf-8")
    if "android.permission.INTERNET" not in text:
        text = text.replace(
            ">",
            '>\n    <uses-permission android:name="android.permission.INTERNET"/>',
            1,
        )
    if "usesCleartextTraffic" not in text:
        text = text.replace(
            "<application",
            '<application android:usesCleartextTraffic="true"',
            1,
        )
    text = re.sub(r'android:label="[^"]*"', f'android:label="{display}"', text, count=1)
    manifest.write_text(text, encoding="utf-8")
    print("patched", manifest)

for strings in Path("android").rglob("strings.xml"):
    original = strings.read_text(encoding="utf-8")
    updated = re.sub(r'(<string name="app_name">)[^<]*', rf"\g<1>{display}", original)
    if updated != original:
        strings.write_text(updated, encoding="utf-8")
        print("patched", strings)

plist = Path("ios/Runner/Info.plist")
if plist.exists():
    text = plist.read_text(encoding="utf-8")
    if "NSAppTransportSecurity" not in text:
        text = text.replace(
            "</dict>\n</plist>",
            """    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>""",
            1,
        )

    def set_or_add(text, key, value):
        pattern = rf"(<key>{key}</key>\s*<string>)[^<]*"
        if re.search(pattern, text):
            return re.sub(pattern, rf"\g<1>{value}", text, count=1)
        return text.replace(
            "</dict>\n</plist>",
            f"    <key>{key}</key>\n    <string>{value}</string>\n</dict>\n</plist>",
            1,
        )

    text = set_or_add(text, "CFBundleDisplayName", display)
    text = set_or_add(text, "CFBundleName", display)
    plist.write_text(text, encoding="utf-8")
    print("patched", plist)
PY

flutter pub get
echo
echo "准备完成。可以执行：flutter run"
