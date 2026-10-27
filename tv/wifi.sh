#!/bin/sh
# wifi.sh saved|status - what the TV knows about Wi-Fi, read-only, for Settings -> Network (luna://com.webos.service.wifi).
#   saved    getprofilelist: the networks the TV remembers (names, security type)
#   status   getstatus: is the Wi-Fi service enabled
# Joining a network is deliberately NOT done here: it needs a full text keyboard for the password and a TV with no cable to test on; Settings -> Network opens LG's Settings for that.
. /media/developer/tv-debloat/common.sh
W=luna://com.webos.service.wifi
case ${1:-saved} in
  saved)  lun $W/getprofilelist '{}';;
  status) lun $W/getstatus '{}';;
esac
