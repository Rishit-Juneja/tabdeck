#!/bin/sh
# Fixes for running the 2023 postmarketOS T110/T111 image on its 3.4 kernel. Run as root.
# Each one was found the hard way; see "Tablet notes" in the README.
#
# Set these for your network before running:
WIFI_CON="YourWifiName"      # NetworkManager connection name (nmcli con show)
WIFI_IP="192.168.1.50/24"    # a free address outside your router's DHCP range
WIFI_GW="192.168.1.1"
WIFI_DNS="192.168.1.1 1.1.1.1"

set -e

# 1. Keep packages on the repos that match the image. Newer Alpine edge packages pull libraries
#    that clash with the old base (WebKit vs GStreamer symbols, Firefox "Couldn't load XPCOM").
cp /etc/apk/repositories /etc/apk/repositories.bak
cat > /etc/apk/repositories <<R
http://mirror.postmarketos.org/postmarketos/v23.12
http://dl-cdn.alpinelinux.org/alpine/v3.19/main
http://dl-cdn.alpinelinux.org/alpine/v3.19/community
R
apk update && apk upgrade --available

# 2. The framebuffer is not a DRM device, so elogind reports seat0 CanGraphical=no and LightDM
#    waits for it forever (black screen after boot). Skip that check and start after elogind.
C=/etc/lightdm/lightdm.conf
grep -q "^logind-check-graphical" $C || sed -i "/^\[LightDM\]/a logind-check-graphical=false" $C
grep -q '^rc_need=.*elogind' /etc/conf.d/lightdm 2>/dev/null || echo 'rc_need="elogind"' >> /etc/conf.d/lightdm

# 3. NetworkManager associates with Wi-Fi but its IP config never lands on wlan0 on this kernel
#    (DHCP times out, a static profile reports "activated" with no address). Apply it by hand
#    whenever Wi-Fi is up.
nmcli con modify "$WIFI_CON" ipv4.method manual ipv4.addresses "$WIFI_IP" ipv4.gateway "$WIFI_GW" \
  ipv4.dns "$WIFI_DNS" ipv6.method ignore connection.autoconnect-retries 0
cat > /etc/local.d/wifi-ip.start <<W
#!/bin/sh
(
while true; do
  if nmcli -t -f DEVICE,STATE dev | grep -q '^wlan0:connected'; then
    ip addr show wlan0 | grep -q '${WIFI_IP%/*}/' || ip addr add $WIFI_IP dev wlan0
    ip route | grep -q '^default' || ip route add default via $WIFI_GW dev wlan0
  fi
  sleep 15
done
) >/dev/null 2>&1 &
W
chmod +x /etc/local.d/wifi-ip.start
rc-update add local default

# 4. No RTC battery backup worth trusting: set the timezone so chrony's sync shows local time.
#    ln -sf /usr/share/zoneinfo/<Region/City> /etc/localtime

echo "done; reboot to check the desktop and Wi-Fi come up on their own"
