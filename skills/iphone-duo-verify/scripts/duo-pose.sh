#!/usr/bin/env bash
# Drive the iPhone Duo simulator through Device Hub (Xcode 27.1+) and capture per-display evidence.
#   bash duo-pose.sh <UDID> hub                                                  # open Device Hub on this simulator
#   bash duo-pose.sh <UDID> pose <Closed|"Partially Open"|Open|"Rotate Right">   # click a pose button, wait 4 s
#   bash duo-pose.sh <UDID> shot <out.png> [inner|outer]                        # screenshot one display, print "WxH pt"
#   bash duo-pose.sh <UDID> displays                                            # display UUIDs + framebuffer sizes
# Closed poses render on the OUTER display; simctl's default screenshot is the inner one, so say "outer" when closed.
# Needs DEVELOPER_DIR pointing at Xcode 27.1+ and Accessibility access for the terminal
# (System Settings > Privacy & Security > Accessibility). Pose buttons are found by their help text, not by index.
set -eu
UDID=$1; CMD=$2; ARG=${3:-}
: "${DEVELOPER_DIR:?export DEVELOPER_DIR=/Applications/<Xcode 27.1>.app/Contents/Developer}"
G='group 3 of splitter group 1 of group 1 of splitter group 1 of group 1 of window 1'

displays() { xcrun simctl io "$UDID" enumerate | awk '/UUID:/{u=$2} /size *=/{print u, $3}'; }
display_uuid() { displays | sort -k2 -n | { [ "$1" = outer ] && head -1 || tail -1; } | awk '{print $1}'; }   # smaller framebuffer = outer
shot() {
  xcrun simctl io "$UDID" screenshot --display="$(display_uuid "${2:-inner}")" "$1" >/dev/null 2>&1
  local w h; w=$(sips -g pixelWidth "$1" | awk 'END{print $2}'); h=$(sips -g pixelHeight "$1" | awk 'END{print $2}')
  echo "$((w/3))x$((h/3)) pt ($1)"
}
pose() {
  osascript -e 'tell application "DeviceHub" to activate' >/dev/null
  osascript -e "tell application \"System Events\" to tell process \"DeviceHub\" to click (first button of $G whose help is \"$1\")" >/dev/null
  sleep 4
}
case $CMD in
  hub) open -a "$DEVELOPER_DIR/../Applications/DeviceHub.app" --args -CurrentDeviceUDID "$UDID" ;;
  displays) displays ;;
  pose) pose "$ARG" ;;
  shot) shot "${ARG:-duo.png}" "${4:-inner}" ;;
  *) echo "unknown command $CMD (hub|pose|shot|displays)" >&2; exit 2 ;;
esac
