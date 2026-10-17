#!/usr/bin/env bash
set -euo pipefail
PACKAGE=io.github.abiedadam0077.novacraft
APK=$(find delivery -name '*.apk')
# Test the exact file that will be published, not just the instrumentation build.
adb uninstall "$PACKAGE" || true
adb install "$APK" | tee delivery/install-result.txt
grep -q Success delivery/install-result.txt
adb logcat -c
adb shell am start -W -n "$PACKAGE/.MainActivity" | tee delivery/launch-result.txt
grep -q 'Status: ok' delivery/launch-result.txt
sleep 8
adb shell pidof "$PACKAGE" | tee delivery/process-id.txt
adb shell uiautomator dump /sdcard/nova-ui.xml
adb pull /sdcard/nova-ui.xml delivery/launch-ui.xml
# Confirm the real first screen rendered, rather than a system error dialog.
grep -q 'NOVA CRAFT' delivery/launch-ui.xml
adb logcat -b crash -d > delivery/crash-buffer.txt
if grep -q "Process: $PACKAGE" delivery/crash-buffer.txt; then
  echo 'The delivered APK crashed during launch.' >&2
  exit 1
fi
adb shell screencap -p /sdcard/nova-launch.png
adb pull /sdcard/nova-launch.png delivery/launch-screen.png
