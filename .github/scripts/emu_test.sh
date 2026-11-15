#!/bin/bash
# Emulator smoke test: install the release APK, normal launch (intro -> home), then relaunch straight into a
# quick match vs the bot (Flutter initial route /nx-quickmatch, see lib/app/shell.dart). Collects screenshots
# and logcat; fails on a crash, an NX_ERR line, or when the match never reports ready.
# usage: emu_test.sh <apk> <outdir>
set -u
APK="$1"; OUT="$2"; PKG=com.nexora.nexora; ACT=$PKG/.MainActivity
mkdir -p "$OUT"
adb wait-for-device
{ adb shell getprop ro.build.version.sdk; adb shell getprop ro.product.cpu.abilist; adb shell wm size; } | tee "$OUT/device.txt"
adb logcat -c || true
adb install -r "$APK" 2>&1 | tee "$OUT/install.txt"
grep -q Success "$OUT/install.txt" || { echo "::error::adb install failed"; exit 1; }
shot() { adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null || true; }
alive() { adb shell pidof $PKG | tr -d '\r'; }
fail=0
check() {
  grep -q "FATAL EXCEPTION" "$1" && { echo "::error::[$2] FATAL EXCEPTION"; fail=1; }
  grep -E -q "Fatal signal|SIGSEGV|SIGABRT" "$1" && { echo "::error::[$2] native crash"; fail=1; }
  grep -q "NX_ERR" "$1" && { echo "::error::[$2] NX_ERR (Dart error) in logcat"; fail=1; }
  echo "======== [$2] logcat (flutter / errors)"
  grep -E -i " flutter|NX_|AndroidRuntime|FATAL|impeller|vulkan|Choreographer.*Skipped" "$1" | tail -n 300
}
SIZE=$(adb shell wm size | tr -d '\r' | grep -o '[0-9]*x[0-9]*' | tail -n 1); W=${SIZE%x*}; H=${SIZE#*x}

# The launch intro is an MP4; the emulator's host-side h264 decoder crashed the whole emulator in CI run 2, so
# the smoke test enters through the intro-skipping test route (the intro itself is not exercised here).
echo "== phase 1: launch to home"
adb shell am start -W -n $ACT --es route /nx-home
sleep 8; shot p1_08s_home
sleep 6; shot p1_14s_home
[ -z "$(alive)" ] && { echo "::error::[launch] process died"; fail=1; }
adb logcat -d -v threadtime > "$OUT/logcat_launch.txt"
check "$OUT/logcat_launch.txt" launch

echo "== phase 2: quick match vs bot"
adb shell am force-stop $PKG; sleep 2; adb logcat -c || true
adb shell am start -W -n $ACT --es route /nx-quickmatch
sleep 10; shot p2_10s_match
# a drag-shot from the bottom-centre disc upwards (the player's team is at the bottom)
adb shell input swipe $((W/2)) $((H*78/100)) $((W/2)) $((H*92/100)) 400 || true
sleep 6; shot p2_16s_after_shot
sleep 8; shot p2_24s
[ -z "$(alive)" ] && { echo "::error::[match] process died"; fail=1; }
adb logcat -d -v threadtime > "$OUT/logcat_match.txt"
grep -q "NX_TEST match ready" "$OUT/logcat_match.txt" && echo "match ready marker found" || { echo "::error::match never reported ready"; fail=1; }
adb shell dumpsys gfxinfo $PKG > "$OUT/gfxinfo.txt" 2>/dev/null || true
check "$OUT/logcat_match.txt" match
echo "== phase 3: my team + shop"
for R in team shop; do
  adb shell am force-stop $PKG; sleep 2; adb logcat -c || true
  adb shell am start -W -n $ACT --es route /nx-$R
  sleep 9; shot p3_$R
  adb logcat -d -v threadtime > "$OUT/logcat_$R.txt"
  check "$OUT/logcat_$R.txt" $R
done
echo "result: fail=$fail"
exit $fail
