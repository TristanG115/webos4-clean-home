// ---- tv-debloat (inserted by qspatch.sh in front of init): tell the TV-side API that this script was loaded ----
// (the `compositor` object is NOT visible in this script on webOS 4.5, only inside the QML files: the pointer work lives in StarfishKeyFilter.qml)
function tvdInit() {
    try {
        var x = new XMLHttpRequest();
        x.open("GET", "http://127.0.0.1:8765/api/qs?e=loaded&m=systemUi");
        x.send(null);
    } catch (e) {}
}
// ---- end tv-debloat ----
