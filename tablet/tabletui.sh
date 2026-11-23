#!/bin/sh
# Turns a stock postmarketOS MATE desktop into a tablet-style home screen:
# a grid of big app icons, one bottom dock, dark theme, touch keyboard. Re-runnable.
# Run it as the desktop user from inside the running session (or over SSH: it finds the session).
export DISPLAY=${DISPLAY:-:0} XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
  P=$(pgrep -u "$(id -u)" -x mate-session | head -1)
  export $(tr "\0" "\n" < /proc/$P/environ | grep ^DBUS_SESSION_BUS_ADDRESS)
fi
A=/usr/share/applications
FIREFOX=$( [ -f $A/firefox-esr.desktop ] && echo firefox-esr || echo org.mozilla.firefox-esr )

# look: dark theme, bigger touch-friendly text
gsettings set org.mate.interface gtk-theme 'Arc-Dark'
gsettings set org.mate.interface icon-theme 'Papirus-Dark'
gsettings set org.mate.Marco.general theme 'Arc-Dark'
gsettings set org.mate.Marco.general titlebar-font 'Sans Bold 13'
gsettings set org.mate.interface font-name 'Sans 12'
gsettings set org.mate.interface document-font-name 'Sans 12'
gsettings set org.mate.caja.desktop font 'Sans Bold 12'
gsettings set org.mate.font-rendering dpi 120.0
gsettings set org.mate.background picture-filename "$(ls /usr/share/backgrounds/cosmos/*.jpg 2>/dev/null | head -1)"
gsettings set org.mate.background picture-options 'zoom'

# home screen: only app icons, single tap opens
gsettings set org.mate.caja.desktop computer-icon-visible false
gsettings set org.mate.caja.desktop home-icon-visible false
gsettings set org.mate.caja.desktop trash-icon-visible false
gsettings set org.mate.caja.desktop volumes-visible false
gsettings set org.mate.caja.icon-view default-zoom-level 'larger'
gsettings set org.mate.caja.preferences click-policy 'single'
gsettings set org.mate.caja.preferences executable-text-activation 'launch'

D=$HOME/Desktop; mkdir -p "$D"; rm -f "$D"/*.desktop
caja -q 2>/dev/null; sleep 1
# file:Name pairs, laid out in a 6-column grid. Caja doubles these coordinates at 120 dpi.
i=0
for pair in $FIREFOX:Firefox badwolf:Browser netsurf:NetSurf caja:Files mate-terminal:Terminal pluma:Notes \
            mate-calc:Calculator mate-system-monitor:Monitor mate-screenshot:Screenshot onboard:Keyboard \
            mate-appearance-properties:Settings; do
  f=${pair%%:*}; n=${pair#*:}
  [ -f $A/$f.desktop ] || continue
  cp $A/$f.desktop "$D/" && chmod +x "$D/$f.desktop"
  sed -i "s/^Name=.*/Name=$n/; /^Name\[/d" "$D/$f.desktop"
  gio set "$D/$f.desktop" metadata::trusted true
  gio set "$D/$f.desktop" metadata::caja-icon-position "$((12 + (i % 6) * 84)),$((14 + (i / 6) * 86))"
  i=$((i+1))
done
# Deck and YouTube (tablet/tabdeck.sh and tablet/youtube.sh, installed to ~/.local/bin)
for pair in tabdeck:Deck:input-gaming youtube:YouTube:youtube; do
  bin=${pair%%:*}; rest=${pair#*:}; n=${rest%%:*}; icon=${rest#*:}
  [ -x "$HOME/.local/bin/$bin" ] || continue
  F="$D/$bin.desktop"
  printf "[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nIcon=%s\nTerminal=false\n" "$n" "$HOME/.local/bin/$bin" "$icon" > "$F"
  chmod +x "$F"; gio set "$F" metadata::trusted true
  gio set "$F" metadata::caja-icon-position "$((12 + (i % 6) * 84)),$((14 + (i / 6) * 86))"
  i=$((i+1))
done
(caja -n >/dev/null 2>&1 &)

# one bottom dock instead of two menu bars: Home | apps | open windows | tray | clock
dconf reset -f /org/mate/panel/
dconf load /org/mate/panel/ <<EOF
[general]
toplevel-id-list=['dock']
object-id-list=['home','web','files','term','kbd','winlist','tray','clock']

[toplevels/dock]
orientation='bottom'
size=56
expand=true
screen=0

[objects/home]
object-type='applet'
applet-iid='WnckletFactory::ShowDesktopApplet'
toplevel-id='dock'
position=0
locked=true

[objects/web]
object-type='launcher'
launcher-location='$A/$FIREFOX.desktop'
toplevel-id='dock'
position=60
locked=true

[objects/files]
object-type='launcher'
launcher-location='$A/caja.desktop'
toplevel-id='dock'
position=120
locked=true

[objects/term]
object-type='launcher'
launcher-location='$A/mate-terminal.desktop'
toplevel-id='dock'
position=180
locked=true

[objects/kbd]
object-type='launcher'
launcher-location='$A/onboard.desktop'
toplevel-id='dock'
position=240
locked=true

[objects/winlist]
object-type='applet'
applet-iid='WnckletFactory::WindowListApplet'
toplevel-id='dock'
position=310
locked=true

[objects/tray]
object-type='applet'
applet-iid='NotificationAreaAppletFactory::NotificationArea'
toplevel-id='dock'
position=90
panel-right-stick=true
locked=true

[objects/clock]
object-type='applet'
applet-iid='ClockAppletFactory::ClockApplet'
toplevel-id='dock'
position=0
panel-right-stick=true
locked=true
EOF

# touch keyboard: dark, docked, pops up when a text box gets focus. Onboard already has a system
# autostart entry, so no user one (two would start two keyboards).
gsettings set org.mate.interface accessibility true
gsettings set org.onboard.auto-show enabled true
gsettings set org.onboard.window docking-enabled true
gsettings set org.onboard theme '/usr/share/onboard/themes/Nightshade.theme'
rm -f "$HOME/.config/autostart/onboard.desktop"

# no lock screen on a home tablet, and no postmarketOS upgrade nag at login
gsettings set org.mate.screensaver lock-enabled false
mkdir -p "$HOME/.config/autostart"
printf '[Desktop Entry]\nType=Application\nName=pmOS upgrade\nHidden=true\n' > "$HOME/.config/autostart/org.postmarketos.Upgrade.desktop"

(mate-panel --replace >/dev/null 2>&1 &)
echo done
