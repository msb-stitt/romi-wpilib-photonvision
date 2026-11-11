"use strict";

const SERVICE = "wpilibws-romi";
const ROMI_JSON = "/boot/firmware/romi.json";
const STATUS_PORT = 9001;

const romiJson = cockpit.file(ROMI_JSON, { superuser: "try" });

function show(id, text) {
    document.getElementById(id).textContent = text;
}

function failure(err) {
    return err.message || String(err);
}

function refreshServiceState() {
    cockpit.spawn(["systemctl", "is-active", SERVICE], { err: "ignore" })
        .then(out => show("service-state", out.trim()))
        .catch((err, out) => show("service-state", (out || "").trim() || failure(err)));
}

function refreshRomiStatus() {
    cockpit.http(STATUS_PORT).get("/status")
        .then(body => {
            const status = JSON.parse(body);
            const battery = status["battery-status"];
            const firmware = status["firmware-status"].firmwareMatch ? "matches" : "does not match";
            show("romi-status",
                 `Service ${status["service-version"].serviceVersion}; ` +
                 `32U4 firmware ${firmware}; battery ${battery.voltage} V`);
        })
        .catch(err => show("romi-status", `Its status page did not answer: ${failure(err)}`));
}

function refresh() {
    refreshServiceState();
    refreshRomiStatus();
}

function restart() {
    show("restart-result", "Restarting");
    return cockpit.spawn(["systemctl", "restart", SERVICE], { superuser: "require", err: "message" })
        .then(() => show("restart-result", "Restarted"))
        .catch(err => show("restart-result", `Restart failed: ${failure(err)}`))
        .finally(() => setTimeout(refresh, 6000));
}

function loadRomiJson() {
    romiJson.read()
        .then(text => {
            document.getElementById("romi-json").value = text || "";
            show("save-result", "");
        })
        .catch(err => show("save-result", `Could not read ${ROMI_JSON}: ${failure(err)}`));
}

function saveRomiJson() {
    const text = document.getElementById("romi-json").value;
    try {
        JSON.parse(text);
    } catch (err) {
        show("save-result", `Not saved; it is not valid JSON: ${err.message}`);
        return;
    }
    cockpit.file(ROMI_JSON, { superuser: "require" }).replace(text)
        .then(() => {
            show("save-result", "Saved");
            return restart();
        })
        .catch(err => show("save-result", `Not saved: ${failure(err)}`));
}

document.getElementById("restart").addEventListener("click", restart);
document.getElementById("save").addEventListener("click", saveRomiJson);
document.getElementById("reload").addEventListener("click", loadRomiJson);

loadRomiJson();
refresh();
setInterval(refresh, 5000);
