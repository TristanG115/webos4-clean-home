#!/bin/sh
# tv-inspect.sh - READ-ONLY inspection of an LG webOS 4.5 TV (Phase 1).
# It only reads files, lists directories and runs status/query commands.
# It writes nothing on the TV, stops nothing, mounts nothing.
# Run from Windows:  cmd /c "ssh root@10.0.0.63 sh -s < tv-inspect.sh > tv-report.txt"

sec() { echo; echo "=================== $1 ==================="; }
run() { echo "\$ $*"; sh -c "$*" 2>&1; echo; }

sec "IDENTITY"
run 'id'
run 'date'
run 'uname -a'
run 'cat /etc/starfish-release'
run 'cat /etc/os-release'
run 'cat /var/run/nyx/os_info.json'
run "luna-send -n 1 -f luna://com.webos.service.tv.systemproperty/getSystemInfo '{\"keys\":[\"modelName\",\"firmwareVersion\",\"sdkVersion\",\"boardType\"]}'"

sec "RESOURCES"
run 'uptime'
run 'free'
run 'df -h'
run 'cat /proc/mounts'
run 'grep -m1 -i "model name\|Processor" /proc/cpuinfo; grep -c ^processor /proc/cpuinfo'

sec "INIT SYSTEM"
run 'command -v initctl systemctl'
run 'initctl list'
run 'ls /etc/init/'

sec "PROCESSES"
run 'ps -ef || ps w'
run 'top -b -n 1 | head -50'

sec "NETWORK CONNECTIONS (evidence of phoning home)"
run 'netstat -tunp 2>/dev/null || netstat -tun'

sec "APPS"
run 'ls /usr/palm/applications'
run 'ls /usr/palm/services'
run 'ls /media/developer/apps/usr/palm/applications'
run 'ls /media/developer/apps/usr/palm/services'
run 'ls /media/cryptofs/apps/usr/palm/applications'
run "luna-send -n 1 -f luna://com.webos.applicationManager/listLaunchPoints '{}' | grep -E '\"(id|title|removable|systemApp)\"'"

sec "HOMEBREW / ROOT CUSTOMISATION"
run 'ls -la /var/lib/webosbrew'
run 'ls -la /var/lib/webosbrew/init.d'
run 'for f in /var/lib/webosbrew/init.d/*; do [ -f "$f" ] && { echo "----- $f"; cat "$f"; }; done'
run 'cat /var/lib/webosbrew/startup.sh'
run 'cat /media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service/startup.sh'
run 'ls /var/luna/preferences | grep -i -E "brew|hbchannel"'
run 'for f in /var/luna/preferences/*brew* /var/luna/preferences/*hbchannel*; do [ -f "$f" ] && { echo "----- $f"; cat "$f"; echo; }; done'
run 'ls -la /media/developer'
run 'ls -la /home/root'
run 'ls -la /home/root/.ssh'
run 'crontab -l; ls -la /var/spool/cron 2>&1'

sec "HOSTS AND DNS"
run 'ls -la /etc/hosts'
run 'cat /etc/hosts'
run 'grep -E "hosts|resolv" /proc/mounts'
run 'ls -la /etc/resolv.conf'
run 'cat /etc/resolv.conf'
run "luna-send -n 1 -f luna://com.webos.service.connectionmanager/getStatus '{}' | grep -i -E 'dns|gateway|method|state|interface'"

sec "AD / TELEMETRY CANDIDATES (from cleanyourtv-WebOS debloat list + LG names)"
PAT='admanager|adoverlay|acr|remotelogger|service-logger|servicelogger|contentminer|nudge|sportsalarm|smartad|lgads|logger|analytic|statistic|beacon|crash|livepl|reco|rdx'
run "ps -ef | grep -i -E '$PAT' | grep -v grep"
run "initctl list | grep -i -E '$PAT'"
run "ls /etc/init/ | grep -i -E '$PAT'"
run "for f in \$(ls /etc/init/*.conf | grep -i -E '$PAT'); do echo \"----- \$f\"; cat \"\$f\"; done"
run "find /usr/bin /usr/sbin /usr/lib/webos /usr/palm -maxdepth 2 2>/dev/null | grep -i -E '$PAT'"
run "ls /usr/share/dbus-1/system-services /usr/share/luna-service2/services.d 2>/dev/null | grep -i -E '$PAT'"
run "grep -rl -i -E 'lgsmartad|lgtvcommon|lgappstv|ibis\\.lgappstv' /etc 2>/dev/null | head -30"

sec "DONE"
