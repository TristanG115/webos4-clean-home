#!/bin/sh
# blocklist.sh apply|remove|update [id|all]|maybe-update|json|test <host>
# Pi-hole style ad blocking for the TV, using the RAM hosts file (/etc/hosts is a tmpfs copy made by the Homebrew startup script):
#   sources  = lists.tsv (built-in lists in this folder + remote lists downloaded to state/lists/) + state/block-custom.txt (your own)
#   switches = state/block.conf (id=on|off, defaults from lists.tsv)
#   never blocked = blocklists/allow.txt + state/block-allow.txt
# Result: "0.0.0.0 host" lines between "# tv-debloat begin" and "# tv-debloat end". Nothing outside /etc/hosts is touched.
. /media/developer/tv-debloat/common.sh
BL=$D/blocklists; LISTS=$BL/lists.tsv; CONF=$STATE/block.conf; LD=$STATE/lists
CUSTOM=$STATE/block-custom.txt; UALLOW=$STATE/block-allow.txt; COUNTS=$STATE/block.counts
MAXHOSTS=9000
mkdir -p "$LD"

on_of() { # id -> on|off
  v=$(sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -1)
  [ -z "$v" ] && v=$(awk -F'|' -v id="$1" '$1==id{print $3}' "$LISTS")
  echo "${v:-off}"
}
src_file() { # id -> file holding that list (may not exist yet)
  k=$(awk -F'|' -v id="$1" '$1==id{print $2}' "$LISTS")
  [ "$k" = builtin ] && echo "$BL/$1.txt" || echo "$LD/$1.txt"
}
# normalise any list format (hosts-file lines, bare domains, comments) to bare lower-case host names, one per line
norm() { awk '{ sub(/\r$/, ""); sub(/#.*/, ""); n = split($0, a, /[ \t]+/); k = 1; while (k <= n && a[k] == "") k++;
  if (k > n) next; d = a[k]; if (a[k] ~ /^(0\.0\.0\.0|127\.0\.0\.1|::1?)$/) { d = a[k + 1] } else if (a[k + 1] != "") next
  d = tolower(d); if (d == "localhost" || d !~ /^[a-z0-9_.-]+\.[a-z0-9-]+$/ || d ~ /^[0-9.]+$/) next; print d }'; }

build() { # writes /tmp/tv-block.hosts, state/block.counts; prints the number of hosts
  : > /tmp/tv-block.all; : > "$COUNTS"
  for id in $(awk -F'|' '!/^#/ && NF>=5{print $1}' "$LISTS"); do
    f=$(src_file $id); n=0
    if [ -s "$f" ]; then n=$(norm < "$f" | wc -l); fi
    echo "$id=$n" >> "$COUNTS"
    [ "$(on_of $id)" = on ] && [ -s "$f" ] && norm < "$f" >> /tmp/tv-block.all
  done
  [ -s "$CUSTOM" ] && { norm < "$CUSTOM" >> /tmp/tv-block.all; echo "custom=$(norm < "$CUSTOM" | wc -l)" >> "$COUNTS"; }
  [ -s "$UALLOW" ] && echo "allow_custom=$(norm < "$UALLOW" | wc -l)" >> "$COUNTS"
  # allow lists: "name" = that name and all its sub-domains, "=name" = that exact host only
  { sed 's/\r$//' "$BL/allow.txt" 2>/dev/null; sed 's/\r$//' "$UALLOW" 2>/dev/null; } > /tmp/tv-block.allow
  sort -u /tmp/tv-block.all | awk -v max=$MAXHOSTS '
    FILENAME ~ /allow/ { sub(/#.*/, ""); gsub(/[ \t]/, ""); if ($0 == "") next; if (substr($0, 1, 1) == "=") ex[tolower(substr($0, 2))] = 1; else sf[tolower($0)] = 1; next }
    { d = $0; if (d in ex) next; if (d in sf) next; s = d; ok = 1
      while ((i = index(s, ".")) > 0) { s = substr(s, i + 1); if (s in sf) { ok = 0; break } }
      if (ok && n < max) { print "0.0.0.0 " d; n++ } }' /tmp/tv-block.allow - > /tmp/tv-block.hosts
  wc -l < /tmp/tv-block.hosts
  rm -f /tmp/tv-block.all /tmp/tv-block.allow
}
strip_hosts() { # prints /etc/hosts without our block (also understands the old one-mark-per-line format)
  awk '/# tv-debloat begin/{skip=1} !skip && !/# tv-debloat( |$)/{print} /# tv-debloat end/{skip=0}' /etc/hosts
}
write_hosts() { # $1 = file with our block ("" = remove)
  strip_hosts > /tmp/hosts.new
  if [ -n "$1" ] && [ -s "$1" ]; then { echo "# tv-debloat begin"; cat "$1"; echo "# tv-debloat end"; } >> /tmp/hosts.new; fi
  [ -s /tmp/hosts.new ] && cat /tmp/hosts.new > /etc/hosts
  rm -f /tmp/hosts.new
}
fetch() { # id url -> state/lists/id.txt (only replaced when the download looks sane)
  t=$LD/$1.tmp
  curl -s -f -L -m 60 -A "tv-debloat" -o "$t" "$2" 2>/dev/null || { rm -f "$t"; echo "$1: download failed"; return 1; }
  n=$(norm < "$t" | wc -l)
  if [ "$n" -lt 20 ] || [ "$n" -gt 60000 ]; then rm -f "$t"; echo "$1: unexpected list size ($n), kept the old copy"; return 1; fi
  mv "$t" "$LD/$1.txt"; date +%s > "$LD/$1.stamp"; echo "$1: $n hosts"; return 0
}
update_remote() { # all|id  -> number of lists refreshed
  c=0
  for id in $(awk -F'|' '!/^#/ && $2=="remote"{print $1}' "$LISTS"); do
    [ "$1" != all ] && [ "$1" != "$id" ] && continue
    [ "$(on_of $id)" = on ] || [ "$1" = "$id" ] || continue
    url=$(awk -F'|' -v id="$id" '$1==id{print $6}' "$LISTS")
    fetch "$id" "$url" && c=$((c+1))
  done
  echo $c
}

case ${1:-apply} in
  apply)  n=$(build); write_hosts /tmp/tv-block.hosts; log "blocklist: $n hosts blocked"; echo "$n hosts blocked";;
  remove) write_hosts ""; log "blocklist: removed"; echo "removed";;
  update) r=$(update_remote "${2:-all}" | tail -1); n=$(build); write_hosts /tmp/tv-block.hosts; log "blocklist: updated $r list(s), $n hosts"; echo "updated $r list(s); $n hosts blocked";;
  maybe-update) # refresh enabled remote lists that are missing or older than 7 days; only when the TV is online
    need=0; now=$(date +%s)
    for id in $(awk -F'|' '!/^#/ && $2=="remote"{print $1}' "$LISTS"); do
      [ "$(on_of $id)" = on ] || continue
      s=$(cat "$LD/$id.stamp" 2>/dev/null || echo 0)
      [ ! -s "$LD/$id.txt" ] || [ $((now - s)) -gt 604800 ] && need=1
    done
    if [ $need = 1 ] && curl -s -m 5 -o /dev/null https://raw.githubusercontent.com/; then
      r=$(update_remote all | tail -1); n=$(build); write_hosts /tmp/tv-block.hosts; log "blocklist: auto-updated $r list(s), $n hosts"; echo "auto-updated $r"
    else echo "up to date"; fi;;
  json)   # for the Settings screen: all lists with state, size and age
    built=$(awk '/# tv-debloat begin/{f=1;next}/# tv-debloat end/{f=0}f' /etc/hosts | wc -l); [ "$built" = 0 ] && built=$(grep -c "# tv-debloat\$" /etc/hosts)
    printf '{"blocked":%s,"custom":%s,"allowCustom":%s,"lists":[' "$built" "$(sed -n 's/^custom=//p' "$COUNTS" 2>/dev/null | head -1 | grep . || echo 0)" "$(sed -n 's/^allow_custom=//p' "$COUNTS" 2>/dev/null | head -1 | grep . || echo 0)"
    first=1
    for id in $(awk -F'|' '!/^#/ && NF>=5{print $1}' "$LISTS"); do
      [ $first = 1 ] || printf ','; first=0
      cnt=$(sed -n "s/^$id=//p" "$COUNTS" 2>/dev/null | head -1); [ -z "$cnt" ] && cnt=0
      st=$(cat "$LD/$id.stamp" 2>/dev/null || echo 0)
      awk -F'|' -v id="$id" -v on="$(on_of $id)" -v cnt="$cnt" -v st="$st" '$1==id{
        printf "{\"id\":\"%s\",\"kind\":\"%s\",\"on\":%s,\"name\":\"%s\",\"desc\":\"%s\",\"count\":%s,\"stamp\":%s}", $1, $2, (on == "on" ? "true" : "false"), $4, $5, cnt, st }' "$LISTS"
    done
    printf ']}';;
  test)   h=$(printf %s "$2" | tr 'A-Z' 'a-z'); grep -q "^0.0.0.0 $h\$" /etc/hosts && echo "$h is BLOCKED" || echo "$h is allowed";;
  *) echo "usage: blocklist.sh apply|remove|update [id|all]|maybe-update|json|test <host>"; exit 1;;
esac
