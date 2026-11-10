# WPILib / NT4 Integration — Parts Reference

**Status: illustrative.** It describes code not yet written, and is unchecked.

## Overview

This project integrates **WPILib 2026/2027** components into the Romi image:
- **NT4 (NetworkTables 4.x)**: WebSocket-based pub/sub for robot data
- **cameraserver**: Multi-camera streaming (used by PhotonVision)
- **wpilibj**: Robot simulation support
- **NT4 Java client**: Used by Romi dashboard for NT4 WebSocket bridge

## Version Matrix

| Season | WPILib | NT4 Protocol | Java | GradleRIO |
|--------|--------|--------------|------|-----------|
| 2026   | 2026.2.x | 4.x | 17/21 | 2026.2.1 |
| 2027   | 2027.x (alpha/beta) | 4.x | 21 | 2027.x |

## NT4 WebSocket Bridge Architecture

```
┌─────────────────┐     NT4 WebSocket      ┌──────────────────┐
│  Romi Dashboard │ ◄─────────────────────► │  Robot Code      │
│  (Javalin)      │    Port 5810 (default)  │  (Desktop/Sim)   │
│  NT4 Client     │                          │  NT4 Server      │
└─────────────────┘                          └──────────────────┘
        │
        │ REST/WebSocket
        ▼
┌─────────────────┐
│  Vue Frontend   │
│  (Real-time NT  │
│   variable view)│
└─────────────────┘
```

## Romi Dashboard as NT4 Client

The Romi dashboard **connects to the robot's NT4 server** (running on desktop or simulator), not the other way around. This matches the standard FRC pattern where the robot is the server.

```kotlin
// Nt4Bridge.kt
val inst = NetworkTableInstance.getDefault()
inst.startClient4("romi-dashboard")  // Client identity
inst.setServer("10.0.0.2", 5810)     // Robot IP + NT4 port

// Subscribe to topics
val targetsEntry = inst.getEntry("/PhotonVision/front/targets")
val poseEntry = inst.getEntry("/PhotonVision/front/pose")

// Publish to topics (e.g., dashboard settings)
val ledEntry = inst.getEntry("/Romi/LED/color")
ledEntry.setString("green")
```

## NT4 Connection Flow

1. **Robot code starts** → NT4 server on port 5810 (configurable)
2. **Romi dashboard starts** → NT4 client connects to robot IP
3. **PhotonVision starts** → NT4 publisher on same server (robot IP)
4. **Dashboard subscribes** to `/PhotonVision/*` topics
5. **Dashboard publishes** to `/Romi/*` topics (settings, commands)

## Default Network Topology (Competition)

```
Robot Radio (10.0.0.1) ──► Robot Controller (10.0.0.2) ◄── Romi (10.0.0.3)
                              │
                              ▼
                    NT4 Server on 10.0.0.2:5810
```

| Device | IP | Role |
|--------|-----|------|
| Robot Radio | 10.0.0.1 | Gateway/DHCP |
| Robot Controller (Rio/PC) | 10.0.0.2 | **NT4 Server** |
| Romi (Pi) | 10.0.0.3 | NT4 Client (dashboard), NT4 Publisher (PhotonVision) |

## Simulator Network Topology

```
Desktop (192.168.x.x) ──► Simulator (127.0.0.1 or 192.168.x.x)
                              │
                              ▼
                    NT4 Server on sim IP:5810
```

For simulator testing:
- Robot sim runs on desktop (same machine or network)
- Romi dashboard in QEMU connects to desktop IP
- Use `--netdev user,hostfwd=tcp::5810-:5810` for QEMU port forward

## Key NT4 Topics for Romi

### PhotonVision Published (Dashboard Consumes)
```
/PhotonVision/<camera>/targets       # AprilTag/target array
/PhotonVision/<camera>/pose          # Robot pose (Pose3d)
/PhotonVision/<camera>/pipeline      # Pipeline status (latency, fps)
/PhotonVision/<camera>/version       # PhotonVision version
```

### Romi Dashboard Published (Robot Consumes)
```
/Romi/Network/Mode                   # "AP" | "Client" | "Ethernet"
/Romi/Network/AP_SSID                # Current AP SSID
/Romi/Network/Client_SSID            # Connected WiFi SSID
/Romi/System/CPU_Temp                # CPU temperature
/Romi/System/Disk_Usage              # Disk usage %
/Romi/Firmware/Version               # 32U4 firmware version
/Romi/Firmware/Status                # "idle" | "flashing" | "success" | "error"
```

### ConfigServer API Compatibility (Legacy)
```
/config/network                      # GET/POST network config
/config/firmware                     # GET firmware list, POST flash
/config/system                       # GET system info
```

## Java Dependencies (Gradle)

```kotlin
// build.gradle.kts dependencies
dependencies {
    // NT4 core (client + server)
    implementation("edu.wpi.first:ntcore-java:2026.2.1")
    
    // wpinet for NT4 server (if dashboard needs to be server too)
    implementation("edu.wpi.first:wpinet-java:2026.2.2.1.1")
    
    // For simulation testing
    testImplementation("edu.wpi.first:wpilibj-java:2026.2.1")
}
```

## NetworkTables 4.x WebSocket Protocol

NT4 uses **WebSocket + MessagePack** for transport. The Romi dashboard can:
1. **Use Java NT4 client** (recommended) — handles reconnection, serialization
2. **Raw WebSocket** — for Vue frontend real-time updates

### Option 1: Java NT4 Client → Javalin WebSocket → Vue

```kotlin
// Nt4Bridge.kt — bridge Java NT4 to Javalin WS
app.ws("/nt4/ws") { ws ->
    ws.onMessage { msg ->
        val cmd = Json.decodeFromString<Nt4Command>(msg)
        when (cmd.action) {
            "subscribe" -> subscribeToTopic(cmd.topic, ws)
            "publish" -> publishTopic(cmd.topic, cmd.value)
        }
    }
}

// Background: Java NT4 listener → broadcast to WebSocket sessions
fun subscribeToTopic(topic: String, ws: WsContext) {
    val entry = inst.getEntry(topic)
    entry.addListener(EventFlags.K_VALUE_ALL) { event ->
        ws.send(Json.encodeToString(Nt4Event(topic, event.value)))
    }
}
```

### Option 2: Vue Connects Directly to NT4 WebSocket (Advanced)

```typescript
// Vue composable - connects to robot's NT4 WebSocket directly
const NT4_WS_URL = `ws://${robotIP}:5810/nt4`

// Requires NT4 WebSocket subprotocol support in browser
// More complex: must implement MessagePack + NT4 protocol
```

**Recommendation**: Option 1 (Java bridge) — simpler, more robust, leverages existing NT4 Java client.

## Configuration for Different Environments

```yaml
# application.yml
nt4:
  # Override via NT4_SERVER env var
  server: "${NT4_SERVER:10.0.0.2}"
  port: 5810
  client_name: "romi-dashboard"
  reconnect_interval_ms: 5000
```

| Environment | NT4_SERVER | Notes |
|-------------|------------|-------|
| Competition | 10.0.0.2 | Robot controller IP |
| Practice field | 10.0.0.2 | Same |
| Simulator (local) | 127.0.0.1 | Desktop running sim |
| Simulator (remote) | 192.168.x.x | Desktop IP |
| QEMU testing | host.docker.internal | Docker host IP |

## Testing NT4 Integration

```bash
# 1. Start NT4 server (robot sim or test server)
./gradlew :wpilib:simulateJava  # Or run RobotSim

# 2. Start Romi dashboard with NT4_SERVER
NT4_SERVER=127.0.0.1 java -jar romi-dashboard.jar

# 3. Verify connection
curl http://localhost:5801/health
curl http://localhost:5801/api/nt4/status

# 4. Test WebSocket
# In browser console:
const ws = new WebSocket('ws://localhost:5801/nt4/ws')
ws.onmessage = (e) => console.log(JSON.parse(e.data))
ws.send(JSON.stringify({action: 'subscribe', topic: '/PhotonVision/front/targets'}))
```

## PhotonVision NT4 Integration

PhotonVision **automatically publishes** to NT4 when running on the same machine as the NT4 server (or configured server). No extra config needed on PhotonVision side.

On Romi image:
- PhotonVision runs as systemd service
- Romi dashboard runs as separate systemd service
- Both connect to **same NT4 server** (robot controller)

## References

- NT4 Protocol: https://github.com/wpilibsuite/allwpilib/blob/main/ntcore/docs/nt4_protocol.md
- NT4 Java API: https://github.com/wpilibsuite/allwpilib/tree/main/ntcore/java
- NetworkTables 4.x Overview: https://docs.wpilib.org/en/stable/docs/software/networktables/networktables-4.html
- WPILib 2026.2.1: https://github.com/wpilibsuite/allwpilib/releases/tag/v2026.2.1