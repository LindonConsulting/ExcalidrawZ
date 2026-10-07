#!/bin/sh
# Opens the ExcalidrawZ shared Viewer full-screen on a kiosk PC.
#
# VIEWER_URL is the link shown in ExcalidrawZ › Viewer › Share Viewer on
# Network… It is always http://<mac>:8488/viewer, so set the host once here.
# Prefer the <name>.local form (needs avahi-daemon on the kiosk); fall back
# to the IP if the kiosk has no mDNS, and give the Mac a DHCP reservation.
#
# The loop waits until the Mac is actually serving before opening the browser,
# so the kiosk can boot before ExcalidrawZ is running. Once the page is open
# it reconnects on its own whenever sharing stops and starts again.

VIEWER_URL="${VIEWER_URL:-http://Johnnys-MacBook-Air.local:8488/viewer}"

until curl -fsS -o /dev/null --max-time 3 "$VIEWER_URL"; do
    sleep 2
done

if command -v chromium >/dev/null 2>&1; then
    BROWSER=chromium
elif command -v chromium-browser >/dev/null 2>&1; then
    BROWSER=chromium-browser
elif command -v google-chrome >/dev/null 2>&1; then
    BROWSER=google-chrome
else
    exec firefox --kiosk "$VIEWER_URL"
fi

exec "$BROWSER" \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --no-first-run \
    --autoplay-policy=no-user-gesture-required \
    "$VIEWER_URL"
