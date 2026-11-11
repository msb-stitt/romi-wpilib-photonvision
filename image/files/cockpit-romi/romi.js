"use strict";

const SERVICE = "wpilibws-romi";
const ROMI_JSON = "/boot/firmware/romi.json";
const STATUS_PORT = 9001;
const LOG_LINES = "15";
const EXT_PINS = 5;
// The robot code's first port for each function on the EXT pins, after the Romi's own.
const FIRST_PORT = { dio: ["Digital", 8], ain: ["Analog In", 0], pwm: ["PWM", 2] };

const romiJson = cockpit.file(ROMI_JSON, { superuser: "try" });
const romiStatus = cockpit.http(STATUS_PORT);

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
    romiStatus.get("/status")
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

function refreshLog() {
    cockpit.spawn(["journalctl", "-u", SERVICE, "-n", LOG_LINES, "-o", "cat", "--no-pager"],
                  { superuser: "try", err: "message" })
        .then(out => show("service-log", out.trim() || "No log lines"))
        .catch(err => show("service-log", `Could not read the log: ${failure(err)}`));
}

function refresh() {
    refreshServiceState();
    refreshRomiStatus();
    refreshLog();
}

function restart() {
    show("restart-result", "Restarting");
    return cockpit.spawn(["systemctl", "restart", SERVICE], { superuser: "require", err: "message" })
        .then(() => show("restart-result", "Restarted"))
        .catch(err => show("restart-result", `Restart failed: ${failure(err)}`))
        .finally(() => setTimeout(refresh, 6000));
}

function showPorts() {
    const next = {};
    for (const fn in FIRST_PORT) next[fn] = FIRST_PORT[fn][1];
    for (let i = 0; i < EXT_PINS; i++) {
        const fn = document.getElementById(`ext${i}`).value;
        show(`port${i}`, `${FIRST_PORT[fn][0]} ${next[fn]++}`);
    }
}

function showConfig(text) {
    document.getElementById("romi-json").value = text || "";
    let config;
    try {
        config = JSON.parse(text || "{}");
    } catch (err) {
        show("gyro-offset", "romi.json is not valid JSON");
        return;
    }
    if (Array.isArray(config.ioConfig)) {
        config.ioConfig.forEach((fn, i) => {
            const select = document.getElementById(`ext${i}`);
            if (select) select.value = fn;
        });
    }
    showPorts();
    const z = config.gyroZeroOffset;
    const n = v => Number(v).toFixed(3);
    show("gyro-offset", z ? `x ${n(z.x)}, y ${n(z.y)}, z ${n(z.z)} °/s` : "none saved");
}

function loadRomiJson() {
    return romiJson.read()
        .then(text => {
            showConfig(text);
            show("save-result", "");
        })
        .catch(err => show("save-result", `Could not read ${ROMI_JSON}: ${failure(err)}`));
}

// Writes the given keys into romi.json, keeping the others.
function updateRomiJson(changes) {
    return cockpit.file(ROMI_JSON, { superuser: "require" }).modify(text => {
        const config = JSON.parse(text || "{}");
        Object.assign(config, changes);
        return JSON.stringify(config, null, 4) + "\n";
    }).then(loadRomiJson);
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

function saveIo() {
    const ioConfig = [];
    for (let i = 0; i < EXT_PINS; i++) ioConfig.push(document.getElementById(`ext${i}`).value);
    show("io-result", "Saving");
    updateRomiJson({ ioConfig })
        .then(() => {
            show("io-result", "Saved");
            return restart();
        })
        .catch(err => show("io-result", `Not saved: ${failure(err)}`));
}

function calibrate() {
    const button = document.getElementById("calibrate");
    button.disabled = true;
    show("calibrate-result", "Starting");
    const done = text => {
        show("calibrate-result", text);
        button.disabled = false;
    };
    romiStatus.post("/imu/calibrate", "")
        .then(() => {
            const poll = setInterval(() => {
                romiStatus.get("/imu/status/calibration-state")
                    .then(body => {
                        const state = JSON.parse(body);
                        if (state.state === "CALIBRATING") {
                            show("calibrate-result", `Calibrating: ${state.percentComplete} %, ` +
                                 `${Math.ceil(state.estimatedTimeLeft)} s left`);
                            return;
                        }
                        clearInterval(poll);
                        return romiStatus.get("/imu/status/last-gyro-calibration-values")
                            .then(values => updateRomiJson({ gyroZeroOffset: JSON.parse(values).zeroOffset }))
                            .then(() => done("Calibrated and saved"));
                    })
                    .catch(err => {
                        clearInterval(poll);
                        done(`Calibration failed: ${failure(err)}`);
                    });
            }, 500);
        })
        .catch(err => done(`Calibration did not start: ${failure(err)}`));
}

for (let i = 0; i < EXT_PINS; i++) document.getElementById(`ext${i}`).addEventListener("change", showPorts);
document.getElementById("restart").addEventListener("click", restart);
document.getElementById("save-io").addEventListener("click", saveIo);
document.getElementById("calibrate").addEventListener("click", calibrate);
document.getElementById("save").addEventListener("click", saveRomiJson);
document.getElementById("reload").addEventListener("click", loadRomiJson);

loadRomiJson();
refresh();
setInterval(refresh, 5000);
