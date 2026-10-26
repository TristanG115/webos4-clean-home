#!/bin/sh
# lg-settings-test.sh [cat:key ...] - runs ON the TV (./tv.sh -s < tools/lg-settings-test.sh).
# For each key: read LG's current value, write the SAME value back through com.webos.settingsservice and report whether the TV accepted it.
# Nothing visibly changes (same value in, same value out). A key that fails here would show "The TV refused that setting" in our Settings screen.
# With no arguments it tests every key the Settings screen uses (the list below must match `LGKEYS` in tv/launcher/app.js).
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
KEYS=${*:-"picture:pictureMode picture:backlight picture:contrast picture:brightness picture:color picture:tint picture:sharpness picture:colorTemperature picture:energySaving picture:dynamicContrast picture:superResolution picture:noiseReduction picture:mpegNoiseReduction picture:gamma picture:colorGamut picture:blackLevel picture:dynamicColor picture:truMotionMode picture:motionEyeCare picture:eyeComfortMode picture:aspectRatio picture:localDimming picture:peakBrightness picture:hdrDynamicToneMapping
sound:soundMode sound:clearVoice sound:autoVolume sound:virtualSurround sound:soundOutput sound:audioBalance sound:soundOptimizer sound:soundOutputDigital sound:hdmiArcMode sound:eArcSupport sound:lgSoundSync sound:startupSound sound:tvPowerSound sound:audioDescription sound:visualImpaired
option:quickStartMode option:standByLight option:logoLight option:powerOnLight option:highContrast option:audioGuidance option:menuTransparency option:animationGuide option:baloonHelp option:focusedItemEnlarged option:pointerSpeed option:pointerSize option:pointerShape option:pointerAlignment option:motionRecognition option:livePlus option:speakToTv option:turnOnByVoice option:watchedListCollection option:enableToastPopup option:appUpdateMode
general:homeAutoLaunch general:homePromotion general:aiNudge general:adCookie general:customizedAd general:screenSaverAd general:lmt general:absenceRecognition general:voiceLongDistance general:tvOnSound general:homeEffect
time:autoClock time:sleepTimer time:noOperationAutoOff time:noSignalAutoOff time:automaticStandBy time:autoOff15Min time:daylightSaving
support:automaticUpdate
network:wolwowlOnOff network:bleAdvertisingOnOff network:allowMobileDeviceAccess
other:cursorAutoRemover other:simplinkEnable other:simplinkAutoPowerOn other:uhdDeepColorHDMI1 other:uhdDeepColorHDMI2 other:uhdDeepColorHDMI3 other:uhdDeepColorHDMI4 other:gameOptimizationHDMI1 other:gameOptimizationHDMI2
caption:captionEnable caption:hardOfHearing"}
ok=0; bad=0; absent=0
for cat in $(for k in $KEYS; do echo ${k%%:*}; done | sort -u); do
  ks=$(for k in $KEYS; do [ "${k%%:*}" = "$cat" ] && echo ${k#*:}; done | tr '\n' ' ')
  luna-send -n 1 -w 8000 luna://com.webos.settingsservice/getSystemSettings "{\"category\":\"$cat\"}" </dev/null > /tmp/lgt.json 2>/dev/null
  for k in $ks; do
    body=$(python - "$cat" "$k" <<'PY'
import sys, json
cat, key = sys.argv[1], sys.argv[2]
try:
    d = json.load(open('/tmp/lgt.json'))
    s = d['settings']
except Exception:
    print('NOCAT'); sys.exit()
if key not in s:
    print('ABSENT'); sys.exit()
print(json.dumps({'category': cat, 'settings': {key: s[key]}}))
PY
)
    case $body in
      NOCAT) echo "FAIL $cat.$k: could not read category"; bad=$((bad+1));;
      ABSENT) echo "skip $cat.$k: not present on this TV/input"; absent=$((absent+1));;
      *) r=$(luna-send -n 1 -w 8000 luna://com.webos.settingsservice/setSystemSettings "$body" </dev/null 2>&1 | tr -d '\n')
         case $r in *'"returnValue": true'*|*'"returnValue":true'*) echo "ok   $cat.$k"; ok=$((ok+1));; *) echo "FAIL $cat.$k: $r"; bad=$((bad+1));; esac;;
    esac
  done
done
echo "RESULT: $ok accepted, $bad failed, $absent not present"
