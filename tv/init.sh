# init.sh - the TV's init system behind ONE set of functions, sourced by common.sh. Upstart (initctl, webOS 4.x: the dev TV) and systemd (systemctl, webOS 5 and newer).
# Every script asks for a service by its Upstart job name ("nudge", "contentminer", "update", ...); on systemd the unit name is looked up in systemd-units.tsv
# ("job|unit", default "<job>.service") so a port only has to fill in that one file, never touch the scripts.
#   INIT                  upstart | systemd | none
#   svc_known <job>       the service exists on this TV (so a missing one is skipped, not reported as a failure)
#   svc_running <job>     it is running now
#   svc_stop / svc_start / svc_restart <job>      (systemd: --no-block, like the reference ports, so a slow unit can never hang a boot script)
# STATUS: the Upstart half is what runs on the dev TV (verified). The systemd half is verified only against fake systemctl / initctl programs (tools/test-init.sh), NOT on a real
# webOS 5+ TV: unit names and what is safe to stop there still have to be confirmed with tools/list-services.sh on that TV.
INIT=$(command -v initctl >/dev/null 2>&1 && echo upstart || { command -v systemctl >/dev/null 2>&1 && echo systemd || echo none; })
UNITMAP=${UNITMAP:-/media/developer/tv-debloat/systemd-units.tsv}
svc_unit() { # job -> systemd unit name
  u=$(sed -n "s/^$1|\(.*\)$/\1/p" "$UNITMAP" 2>/dev/null | head -1)
  [ -n "$u" ] || u=$1
  case $u in *.service|*.socket|*.target|*.timer) echo "$u";; *) echo "$u.service";; esac
}
svc_known() {
  case $INIT in
    upstart) initctl status "$1" >/dev/null 2>&1;;
    systemd) systemctl cat "$(svc_unit "$1")" >/dev/null 2>&1;;
    *) return 1;;
  esac
}
svc_running() {
  case $INIT in
    upstart) initctl status "$1" 2>/dev/null | grep -q "start/running";;
    systemd) systemctl is-active --quiet "$(svc_unit "$1")" 2>/dev/null;;
    *) return 1;;
  esac
}
svc_stop() {
  case $INIT in
    upstart) initctl stop "$1" >/dev/null 2>&1;;
    systemd) systemctl --no-block stop "$(svc_unit "$1")" >/dev/null 2>&1;;
    *) return 1;;
  esac
}
svc_start() {
  case $INIT in
    upstart) initctl start "$1" >/dev/null 2>&1;;
    systemd) systemctl --no-block start "$(svc_unit "$1")" >/dev/null 2>&1;;
    *) return 1;;
  esac
}
svc_restart() {
  case $INIT in
    upstart) initctl restart "$1" >/dev/null 2>&1;;
    systemd) systemctl --no-block restart "$(svc_unit "$1")" >/dev/null 2>&1;;
    *) return 1;;
  esac
}
