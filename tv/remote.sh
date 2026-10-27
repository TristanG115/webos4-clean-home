#!/bin/sh
# remote.sh json | telnet on|off - how this TV can be reached from a computer: SSH and Telnet facts for Settings -> Remote access, and the Telnet switch.
# Homebrew Channel keeps both as flag files read by its start-up script: /var/luna/preferences/webosbrew_telnet_disabled (exists = no Telnet at boot) and
# webosbrew_sshd_enabled (exists = SSH at boot). Only Telnet can be switched here; SSH stays on (it is the way back in, like the update lock stays on).
# Turning Telnet OFF is refused unless an SSH key is installed (otherwise nothing would be left to get in with but a password you may not know).
# revert.sh turns Telnet back ON: "undo everything" must leave every door open.
. /media/developer/tv-debloat/common.sh
PREF=/var/luna/preferences; TFLAG=$PREF/webosbrew_telnet_disabled; SFLAG=$PREF/webosbrew_sshd_enabled
SD=/media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service; AK=/home/root/.ssh/authorized_keys
listening() { netstat -tln 2>/dev/null | grep -q "[:.]$1 .*LISTEN"; }
keys() { grep -c -E '^(ssh-|ecdsa-|sk-)' "$AK" 2>/dev/null || echo 0; }
ip_of() { ip -4 addr show "$1" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1; }
tstart() { listening 23 || { [ -x "$SD/bin/telnetd" ] && ( setsid "$SD/bin/telnetd" -l /bin/sh </dev/null >/dev/null 2>&1 & ); }; }
tstop() { for p in $(pgrep -f "bin/telnetd"); do [ "$p" = "$$" ] || kill "$p" 2>/dev/null; done; }
case ${1:-json} in
  telnet) case $2 in
      on)  rm -f "$TFLAG"; tstart; log "remote: telnet on"; echo "on";;
      off) [ "$(keys)" -ge 1 ] 2>/dev/null && listening 22 || { echo "refused: no SSH key installed or SSH is not listening"; exit 1; }
           touch "$TFLAG"; sync -f "$TFLAG" 2>/dev/null; tstop; log "remote: telnet off"; echo "off";;
      *) echo "usage: remote.sh telnet on|off"; exit 2;;
    esac;;
  json) eth=$(ip_of eth0); wl=$(ip_of wlan0); [ -n "$wl" ] || wl=$(ip_of wlan1)
        mac() { cat "/sys/class/net/$1/address" 2>/dev/null | tr -cd '0-9a-fA-F:'; }
        printf '{"host":"%s","ethIp":"%s","wifiIp":"%s","ethMac":"%s","wifiMac":"%s","ssh":{"listening":%s,"port":22,"keys":%s,"atBoot":%s},"telnet":{"listening":%s,"port":23,"atBoot":%s},"devtools":{"on":%s,"port":9998},"api":{"port":8765}}' \
          "$(hostname | tr -cd 'A-Za-z0-9._-')" "$eth" "$wl" "$(mac eth0)" "$(mac wlan0)" "$(listening 22 && echo true || echo false)" "$(keys)" "$([ -e $SFLAG ] && echo true || echo false)" \
          "$(listening 23 && echo true || echo false)" "$([ -e $TFLAG ] && echo false || echo true)" "$([ -e "$D/DEBUG" ] && echo true || echo false)";;
esac
