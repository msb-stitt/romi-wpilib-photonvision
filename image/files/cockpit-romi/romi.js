"use strict";

const SERVICE = "wpilibws-romi";
const ROMI_JSON = "/boot/firmware/romi.json";
const STATUS_PORT = 9001;
const LOG_LINES = "15";
const EXT_PINS = 5;
// uploadRomi.py writes the 32U4 over its USB port, from wpilibws-romi's own firmware.hex.
const FIRMWARE_PORT = "/dev/ttyACM0";
const UPLOAD_ROMI = "/usr/local/sbin/uploadRomi.py";
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
                 `32U4 firmware ${firmware}; battery ${Number(battery.voltage).toFixed(2)} V`);
        })
        .catch(err => show("romi-status", `Its status page did not answer: ${failure(err)}`));
}

function refreshLog() {
    cockpit.spawn(["journalctl", "-u", SERVICE, "-n", LOG_LINES, "-o", "cat", "--no-pager"],
                  { superuser: "try", err: "message" })
        .then(out => show("service-log", out.trim() || "No log lines"))
        .catch(err => show("service-log", `Could not read the log: ${failure(err)}`));
}

let writingFirmware = false;

function refreshFirmwarePort() {
    if (writingFirmware) return;
    const button = document.getElementById("write-firmware");
    cockpit.spawn(["test", "-e", FIRMWARE_PORT], { err: "ignore" })
        .then(() => {
            show("firmware-port", `The 32U4's USB port is connected, at ${FIRMWARE_PORT}.`);
            button.disabled = false;
        })
        .catch(() => {
            show("firmware-port", "The 32U4's USB port is not connected.");
            button.disabled = true;
        });
}

function refresh() {
    refreshServiceState();
    refreshRomiStatus();
    refreshLog();
    refreshFirmwarePort();
}

function restart() {
    show("restart-result", "Restarting");
    return cockpit.spawn(["systemctl", "restart", SERVICE], { superuser: "require", err: "message" })
        .then(() => show("restart-result", "Restarted"))
        .catch(err => show("restart-result", `Restart failed: ${failure(err)}`))
        .finally(() => setTimeout(refresh, 6000));
}

function writeFirmware() {
    writingFirmware = true;
    document.getElementById("write-firmware").disabled = true;
    const log = document.getElementById("firmware-log");
    log.hidden = false;
    log.textContent = "";
    cockpit.spawn([UPLOAD_ROMI, "-p", FIRMWARE_PORT], { superuser: "require", err: "out" })
        .stream(data => { log.textContent += data; })
        .then(() => {
            log.textContent += "\nWritten. Restarting wpilibws-romi to read it.\n";
            return restart();
        })
        .catch(err => { log.textContent += `\nNot written: ${failure(err)}\n`; })
        .finally(() => {
            writingFirmware = false;
            refreshFirmwarePort();
        });
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

// The NetworkManager profile for WiFi, made by 02-network.sh, in either mode.
const WIFI = "WPILibPi";
const AP_ADDRESS = "10.0.0.2/24";
const WIFI_CHANNELS = 11;
const WIFI_FIELDS = ["802-11-wireless.mode", "802-11-wireless.ssid", "802-11-wireless.channel",
                     "802-11-wireless-security.psk", "ipv4.method", "ipv4.addresses",
                     "ipv4.gateway", "ipv4.dns"];
const ETH_FIELDS = ["ipv4.method", "ipv4.addresses", "ipv4.gateway", "ipv4.dns"];

function value(id) {
    return document.getElementById(id).value.trim();
}

function setValue(id, text) {
    document.getElementById(id).value = text;
}

// The profile's fields, one to a line in nmcli's output.
function nmGet(profile, fields) {
    return cockpit.spawn(["nmcli", "-s", "-t", "-g", fields.join(","), "connection", "show", profile],
                         { superuser: "try", err: "message" })
        .then(out => out.replace(/\n$/, "").split("\n"));
}

function nmApply(profile, settings) {
    return cockpit.spawn(["nmcli", "connection", "modify", profile, ...settings],
                         { superuser: "require", err: "message" })
        .then(() => cockpit.spawn(["nmcli", "connection", "up", profile],
                                  { superuser: "require", err: "message" }));
}

function ethProfile() {
    return cockpit.spawn(["nmcli", "-t", "-g", "UUID,TYPE", "connection", "show"], { err: "message" })
        .then(out => {
            const line = out.split("\n").find(l => l.endsWith(":802-3-ethernet"));
            if (!line) throw new Error("no Ethernet profile");
            return line.split(":")[0];
        });
}

function wifiMode() {
    return document.querySelector("input[name=wifi-mode]:checked").value;
}

function showNetworkRows() {
    const wifi = document.getElementById("wifi");
    const client = wifiMode() === "client";
    wifi.querySelectorAll(".ap-only").forEach(e => { e.hidden = client; });
    wifi.querySelectorAll(".client-only").forEach(e => { e.hidden = !client; });
    wifi.querySelectorAll(".static-only").forEach(e => {
        e.hidden = !client || value("wifi-method") !== "manual";
    });
    document.getElementById("eth").querySelectorAll(".static-only").forEach(e => {
        e.hidden = value("eth-method") !== "manual";
    });
}

function loadNetwork() {
    nmGet(WIFI, WIFI_FIELDS)
        .then(([mode, ssid, channel, psk, method, address, gateway, dns]) => {
            const client = mode !== "ap";
            document.querySelector(`input[name=wifi-mode][value=${client ? "client" : "ap"}]`).checked = true;
            setValue("wifi-ssid", ssid);
            setValue("wifi-psk", psk);
            setValue("wifi-channel", channel === "0" ? "6" : channel);
            setValue("wifi-method", client && method === "manual" ? "manual" : "auto");
            setValue("wifi-address", client ? address : "");
            setValue("wifi-gateway", client ? gateway : "");
            setValue("wifi-dns", client ? dns : "");
            showNetworkRows();
        })
        .catch(err => show("wifi-result", `Could not read the WiFi settings: ${failure(err)}`));
    ethProfile()
        .then(profile => nmGet(profile, ETH_FIELDS))
        .then(([method, address, gateway, dns]) => {
            setValue("eth-method", method === "manual" ? "manual" : "auto");
            setValue("eth-address", address);
            setValue("eth-gateway", gateway);
            setValue("eth-dns", dns);
            showNetworkRows();
        })
        .catch(err => show("eth-result", `Could not read the Ethernet settings: ${failure(err)}`));
}

// The ipv4 settings for DHCP or a static address, from the inputs named by prefix.
function ipv4Settings(prefix) {
    if (value(`${prefix}-method`) !== "manual") {
        return ["ipv4.method", "auto", "ipv4.addresses", "", "ipv4.gateway", "", "ipv4.dns", ""];
    }
    if (!/^\d+\.\d+\.\d+\.\d+\/\d+$/.test(value(`${prefix}-address`))) {
        throw new Error("the address is written like 192.168.1.50/24");
    }
    return ["ipv4.method", "manual", "ipv4.addresses", value(`${prefix}-address`),
            "ipv4.gateway", value(`${prefix}-gateway`), "ipv4.dns", value(`${prefix}-dns`)];
}

function saveWifi() {
    const ssid = value("wifi-ssid");
    const psk = document.getElementById("wifi-psk").value;
    let settings;
    try {
        if (ssid.length < 1) throw new Error("the SSID is empty");
        if (psk.length < 8 || psk.length > 63) throw new Error("the passphrase is 8 to 63 characters");
        settings = ["802-11-wireless.ssid", ssid,
                    "802-11-wireless-security.key-mgmt", "wpa-psk",
                    "802-11-wireless-security.psk", psk];
        if (wifiMode() === "ap") {
            settings.push("802-11-wireless.mode", "ap", "802-11-wireless.band", "bg",
                          "802-11-wireless.channel", value("wifi-channel"),
                          "ipv4.method", "shared", "ipv4.addresses", AP_ADDRESS,
                          "ipv4.gateway", "", "ipv4.dns", "");
        } else {
            settings.push("802-11-wireless.mode", "infrastructure", "802-11-wireless.band", "",
                          "802-11-wireless.channel", "0", ...ipv4Settings("wifi"));
        }
    } catch (err) {
        show("wifi-result", `Not saved: ${err.message}`);
        return;
    }
    show("wifi-result", "Applying");
    nmApply(WIFI, settings)
        .then(() => show("wifi-result", "Saved and applied"))
        .catch(err => show("wifi-result", `Not applied: ${failure(err)}`))
        .finally(loadNetwork);
}

function saveEth() {
    let settings;
    try {
        settings = ipv4Settings("eth");
    } catch (err) {
        show("eth-result", `Not saved: ${err.message}`);
        return;
    }
    show("eth-result", "Applying");
    ethProfile()
        .then(profile => nmApply(profile, settings))
        .then(() => show("eth-result", "Saved and applied"))
        .catch(err => show("eth-result", `Not applied: ${failure(err)}`))
        .finally(loadNetwork);
}

for (let ch = 1; ch <= WIFI_CHANNELS; ch++) {
    document.getElementById("wifi-channel").add(new Option(String(ch), String(ch)));
}
document.querySelectorAll("input[name=wifi-mode]").forEach(e => e.addEventListener("change", showNetworkRows));
document.getElementById("wifi-method").addEventListener("change", showNetworkRows);
document.getElementById("eth-method").addEventListener("change", showNetworkRows);
document.getElementById("save-wifi").addEventListener("click", saveWifi);
document.getElementById("save-eth").addEventListener("click", saveEth);
// The passphrase reads back only with administrative access, which can be turned on after loading.
cockpit.permission({ admin: true }).addEventListener("changed", loadNetwork);
loadNetwork();

for (let i = 0; i < EXT_PINS; i++) document.getElementById(`ext${i}`).addEventListener("change", showPorts);
document.getElementById("restart").addEventListener("click", restart);
document.getElementById("save-io").addEventListener("click", saveIo);
document.getElementById("calibrate").addEventListener("click", calibrate);
document.getElementById("write-firmware").addEventListener("click", writeFirmware);
document.getElementById("save").addEventListener("click", saveRomiJson);
document.getElementById("reload").addEventListener("click", loadRomiJson);

loadRomiJson();
refresh();
setInterval(refresh, 5000);
