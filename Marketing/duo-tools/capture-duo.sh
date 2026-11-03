#!/bin/zsh
# capture-duo.sh <out.png> — captures the running Transcriber on the "iPhone Duo (Transcriber)"
# simulator at the unfolded inner display's size (951x669 pt → 2853x2007 px). The fold itself
# can't be scripted, so the app is moved to a hidden "Resizable" display with devicectl and
# captured there (no status bar). Env: SIM=<udid>. Open the document first (launch the Debug
# build with SIMCTL_CHILD_TRANSCRIBER_SEEK=<s> and SIMCTL_CHILD_TRANSCRIBER_HINGE=book-v|book-h
# to park the player and force a posture), then run this.
set -e
U=${SIM:-E1B59060-5CA8-4791-BA26-400022F2FFFD}; OUT=$1
xcrun devicectl device appResize start --device $U --preferred-size 951x669 >/dev/null 2>&1 &
RP=$!; sleep 6
RID=$(xcrun devicectl device info displays --device $U 2>/dev/null | awk '/Resizable/{f=1} f&&/uniqueId/{print $NF; exit}')
xcrun devicectl device capture screenshot --device $U --display-unique-id $RID --destination "$OUT" -q
kill $RP 2>/dev/null; wait $RP 2>/dev/null || true
echo "captured $OUT"
