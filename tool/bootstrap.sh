#!/usr/bin/env bash
# 在已安装 Flutter 的电脑上运行，生成 Android / iOS 工程并补上网页权限。
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create . --project-name source_box --org com.sourcebox --platforms=android,ios

python3 - <<'PY'
from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
if manifest.exists():
    text = manifest.read_text(encoding="utf-8")
    if "android.permission.INTERNET" not in text:
        text = text.replace(
            "<manifest",
            '<manifest',
            1,
        )
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
    manifest.write_text(text, encoding="utf-8")
    print("patched", manifest)

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
        plist.write_text(text, encoding="utf-8")
        print("patched", plist)
PY

flutter pub get
echo
echo "准备完成。可以执行：flutter run"
