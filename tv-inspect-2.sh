#!/bin/sh
# tv-inspect-2.sh - READ-ONLY. Second pass: which servers each candidate talks to,
# how the on-demand (luna) services are launched, and what admanager has cached.
# Writes nothing on the TV. Run from Windows:
#   cmd /c "ssh root@10.0.0.63 sh -s < tv-inspect-2.sh > tv-report-2.txt"
sec() { echo; echo "=================== $1 ==================="; }
run() { echo "\$ $*"; sh -c "$*" 2>&1; echo; }
DOM='[A-Za-z0-9.-]+\.(lgsmartad|lgtvsdp|lgappstv|lgtvcommon|lge|lgeapi|alphonso|lgads|lgtvads)\.(com|tv|net)'

sec "DOMAINS EMBEDDED IN CANDIDATE BINARIES"
for b in admanager acr2 rdxd rdx_reporter uploadd remotelogger contentminer nudge crashreportd; do
  run "tr -c '[:print:]' '\n' < /usr/sbin/$b | grep -o -E '$DOM' | sort -u"
done

sec "LUNA SERVICE LAUNCH FILES"
for s in com.webos.service.admanager com.webos.service.acr com.webos.statisticsmanager com.webos.service.contentminer com.webos.service.nudge com.webos.rdxd com.webos.service.crashreport; do
  run "cat /usr/share/dbus-1/system-services/$s.service /usr/share/luna-service2/services.d/$s.service 2>/dev/null"
done
run "ls -la /usr/sbin/admanager /usr/sbin/acr2 /usr/sbin/remotelogger /usr/sbin/contentminer /usr/sbin/nudge /usr/sbin/rdxd /usr/sbin/uploadd"

sec "WHAT THE AD MANAGER HAS DOWNLOADED"
run "ls -la /mnt/lg/cmn_data/admanager /mnt/lg/cmn_data/admanager/cache | head -40"
run "du -s /mnt/lg/cmn_data/admanager"

sec "HOSTNAMES SEEN IN SYSTEM LOGS"
run "cat /var/log/messages* /tmp/var/log/messages* 2>/dev/null | grep -o -E '$DOM' | sort | uniq -c | sort -rn | head -60"

sec "UPLOADD / RDX STATE (Homebrew already mounts these read-only)"
run "ls -la /var/spool/uploadd /var/spool/rdxd /tmp/uploadd /tmp/rdxd"
run "cat /etc/init/uploadd.conf"
sec "DONE"
