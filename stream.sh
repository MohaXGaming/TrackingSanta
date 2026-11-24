#!/usr/bin/env bash
# Headless NORAD Santa tracker -> YouTube Live, for GitHub Codespaces.
# Usage: YT_KEY=xxxx-xxxx-xxxx-xxxx ./stream.sh
set -uo pipefail

: "${YT_KEY:?Set YT_KEY (Codespaces secret, or: export YT_KEY=...)}"
URL="${URL:-https://www.noradsanta.org/}"
W="${W:-1280}"; H="${H:-720}"; FPS="${FPS:-30}"; BITRATE="${BITRATE:-2500k}"
DISP=":99"

# --- One-time installs ---
if ! command -v ffmpeg >/dev/null || ! command -v Xvfb >/dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq ffmpeg xvfb wget fonts-liberation
fi
if ! command -v google-chrome >/dev/null; then
  wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  sudo apt-get install -y -qq /tmp/chrome.deb
fi

cleanup() { kill "${XVFB_PID:-}" "${CHROME_PID:-}" 2>/dev/null; }
trap cleanup EXIT INT TERM

# --- Virtual display ---
Xvfb "$DISP" -screen 0 "${W}x${H}x24" -nolisten tcp &
XVFB_PID=$!
sleep 2
export DISPLAY="$DISP"

# --- Chrome (software GL, since Codespaces has no GPU) ---
google-chrome \
  --no-sandbox --disable-dev-shm-usage \
  --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader \
  --kiosk --window-position=0,0 --window-size="${W},${H}" \
  --user-data-dir=/tmp/chrome-profile \
  --autoplay-policy=no-user-gesture-required \
  --no-first-run --disable-infobars --hide-scrollbars \
  "$URL" >/dev/null 2>&1 &
CHROME_PID=$!
echo "Waiting for page to load..."
sleep 20

# --- Stream, auto-restart on drop ---
while true; do
  ffmpeg -hide_banner -loglevel warning \
    -f x11grab -framerate "$FPS" -video_size "${W}x${H}" -i "$DISP" \
    -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
    -c:v libx264 -preset ultrafast -b:v "$BITRATE" -maxrate "$BITRATE" -bufsize 5000k \
    -pix_fmt yuv420p -g $((FPS*2)) -r "$FPS" \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "rtmp://a.rtmp.youtube.com/live2/${YT_KEY}"
  echo "ffmpeg exited, restarting in 5s..."
  sleep 5
done
