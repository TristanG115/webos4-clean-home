#!/bin/bash
# emulator-probe.sh [--effect]  - does our remote "emulator" (key injection, tv/keys.py) work on THIS TV? Run it from the PC against any rooted TV, before installing anything:
#     ./tv.sh -s ... is not needed: this script uses tv.sh itself.   ./tools/emulator-probe.sh            devices, key support, write + read-back round trip (this presses Home once: that is the only side effect)
#                                                                    ./tools/emulator-probe.sh --effect   also presses Home once and checks the TV reacts (goes to Home / changes app)
# It sends tv/keys.py to /tmp on the TV, runs it with the TV's own Python and prints PASS / WARN / FAIL lines and a verdict. The same file is what the TV runs after installation.
cd "$(dirname "$0")/.." || exit 1
{ echo "cat > /tmp/keys-probe.py <<'PYEOF'"; cat tv/keys.py; echo "PYEOF"; echo "command -v python >/dev/null 2>&1 || { echo 'FAIL no python on this TV: the emulator needs it (see AGENTS.md section 8)'; exit 1; }"; echo "python /tmp/keys-probe.py probe $*; r=\$?; rm -f /tmp/keys-probe.py; exit \$r"; } | ./tv.sh -s
