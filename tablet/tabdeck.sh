#!/bin/sh
# Opens the PC's Tab Deck in Firefox kiosk mode.
# Tries the USB link first (postmarketOS USB networking: the PC is always 172.16.42.2), then Wi-Fi,
# where the PC is found by its MAC address because its DHCP address can change.
#
# Setup on the tablet:
#   ~/.config/tabdeck/token   the token from the PC's ~/.config/tabdeck/token
#   ~/.config/tabdeck/pc_mac  the PC's MAC address (optional, only needed over Wi-Fi)
CONF=$HOME/.config/tabdeck
TOKEN=$(cat "$CONF/token")
PC_MAC=$(cat "$CONF/pc_mac" 2>/dev/null)
PROFILE=$HOME/.deckprofile
PORT=8780

HOST=""
if wget -q -T 3 -O /dev/null "http://172.16.42.2:$PORT/api/status?t=$TOKEN"; then
  HOST=172.16.42.2
elif [ -n "$PC_MAC" ]; then
  IP=$(ip neigh | awk -v m="$PC_MAC" 'tolower($0) ~ tolower(m) {print $1; exit}')
  [ -n "$IP" ] && wget -q -T 8 -O /dev/null "http://$IP:$PORT/api/status?t=$TOKEN" && HOST=$IP
fi
if [ -z "$HOST" ]; then
  zenity --error --text="Can't reach the PC's Tab Deck. Is the PC on, and the tablet on USB or Wi-Fi?" 2>/dev/null
  exit 1
fi

# The page's x button calls this helper to close the kiosk; it only listens on the tablet itself.
mkdir -p "$HOME/.deckctl"
cat > "$HOME/.deckctl/closer.py" <<C
import http.server, subprocess
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(204); self.end_headers()
        if self.path == "/close":
            subprocess.run(["pkill", "-f", "--", "--profile $PROFILE"])
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", 8781), H).serve_forever()
C
pgrep -f deckctl/closer.py >/dev/null || (python3 "$HOME/.deckctl/closer.py" >/dev/null 2>&1 &)

# Quiet, single-purpose profile: no first-run pages, session restore or telemetry.
mkdir -p "$PROFILE"
cat > "$PROFILE/user.js" <<'P'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("app.update.enabled", false);
user_pref("browser.tabs.warnOnClose", false);
P
exec firefox-esr --kiosk --profile "$PROFILE" --no-remote "http://$HOST:$PORT/?t=$TOKEN"
