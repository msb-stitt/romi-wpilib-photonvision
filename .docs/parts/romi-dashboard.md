# Romi Dashboard (Javalin + Vue) — Parts Reference

**Status: superseded** on 2026-11-11 by [ADR-003](../architecture/ADR-003-base-and-network.md)
and `image/`. It was illustrative from 2026-06-18, `bb49e90`, labelled so at `ae008de`: it
describes code not written, and is unchecked.

## Overview

The Romi dashboard is a **Javalin + Vue/TypeScript** web server running on the Romi image (port 5801), providing:
- Network configuration (AP mode, WiFi client, Ethernet, hostname)
- 32U4 firmware flashing (upload .hex → avrdude → verify)
- System monitoring (CPU temp, disk, services, logs)
- PhotonVision camera stream embed/link
- Settings (timezone, SSH, overscan)
- NetworkTables 4.x variable view/edit (via NT4 WebSocket bridge)

**Aligns with PhotonVision stack**: same Javalin version, same Vue/Vite tooling, same Gradle structure.

## Project Structure

```
romi-dashboard/
├── build.gradle.kts
├── settings.gradle.kts
├── gradle.properties
├── src/
│   ├── main/
│   │   ├── java/org/romi/dashboard/
│   │   │   ├── Main.kt                    # Javalin entry point
│   │   │   ├── config/
│   │   │   │   └── DashboardConfig.kt     # Config from file/env
│   │   │   ├── routes/
│   │   │   │   ├── NetworkRoutes.kt       # Network config API
│   │   │   │   ├── FirmwareRoutes.kt      # 32U4 flash API
│   │   │   │   ├── SystemRoutes.kt        # System info API
│   │   │   │   ├── Nt4Routes.kt           # NT4 WebSocket bridge
│   │   │   │   └── ConfigServerRoutes.kt  # Legacy configServer compat
│   │   │   ├── services/
│   │   │   │   ├── FlashService.kt        # avrdude wrapper
│   │   │   │   ├── NetworkService.kt      # NetworkManager wrapper
│   │   │   │   ├── Nt4Bridge.kt           # NT4 WebSocket client
│   │   │   │   └── SystemService.kt       # System info (temp, disk, etc)
│   │   │   └── util/
│   │   │       └── ProcessUtil.kt         # Safe process execution
│   │   └── resources/
│   │       ├── application.yml            # Server config
│   │       └── web/                       # Vue build output (copied by Gradle)
│   └── test/
│       └── java/org/romi/dashboard/       # Unit/integration tests
├── dashboard-ui/                          # Vue project (separate or nested)
│   ├── package.json
│   ├── vite.config.ts
│   ├── tsconfig.json
│   ├── src/
│   │   ├── main.ts
│   │   ├── App.vue
│   │   ├── router/
│   │   ├── views/
│   │   │   ├── NetworkView.vue
│   │   │   ├── FirmwareView.vue
│   │   │   ├── SystemView.vue
│   │   │   ├── CameraView.vue
│   │   │   └── SettingsView.vue
│   │   ├── components/
│   │   ├── composables/
│   │   │   ├── useNetwork.ts
│   │   │   ├── useFirmware.ts
│   │   │   └── useNt4.ts
│   │   └── styles/
│   └── dist/                              # Built output → copied to resources/web
```

## Gradle Build (build.gradle.kts)

```kotlin
// build.gradle.kts
plugins {
    id("application")
    id("com.github.node-gradle.node") version "7.0.1"
    id("com.gradleup.shadow") version "8.3.4"
    kotlin("jvm") version "1.9.24"
}

group = "org.romi"
version = "2026.0.0"

application {
    mainClass.set("org.romi.dashboard.MainKt")
}

repositories {
    mavenCentral()
    maven("https://frcmaven.wpi.edu/artifactory/release/")
    maven("https://maven.photonvision.org/releases")
}

dependencies {
    // Javalin (same version as PhotonVision)
    implementation("io.javalin:javalin:6.7.0")
    implementation("org.slf4j:slf4j-simple:2.0.9")

    // WPILib NT4
    implementation("edu.wpi.first:ntcore-java:2026.2.1")
    implementation("edu.wpi.first:wpinet-java:2026.2.2.1.1")

    // JSON/Config
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin:2.17.0")
    implementation("commons-cli:commons-cli:1.5.0")

    // Test
    testImplementation(platform("org.junit:junit-bom:5.11.1"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testImplementation("org.mockito:mockito-junit-jupiter:5.12.0")
}

// Node/Gradle integration for Vue frontend
node {
    version.set("20.11.0")
    download.set(true)
    workDir.set(file("dashboard-ui"))
}

tasks.register("npmInstall", NpmTask) {
    args = ["ci"]
}

tasks.register("npmBuild", NpmTask) {
    args = ["run", "build"]
    dependsOn("npmInstall")
}

tasks.register("copyUiToResources", Copy) {
    from("dashboard-ui/dist")
    into("src/main/resources/web")
    dependsOn("npmBuild")
}

tasks.named("processResources") {
    dependsOn("copyUiToResources")
}

shadowJar {
    archiveBaseName.set("romi-dashboard")
    archiveVersion.set(project.version.toString())
    archiveClassifier.set("")
    mergeServiceFiles()
}
```

## Javalin Main (Main.kt)

```kotlin
// src/main/java/org/romi/dashboard/Main.kt
package org.romi.dashboard

import io.javalin.Javalin
import io.javalin.config.JavalinConfig
import org.romi.dashboard.config.DashboardConfig
import org.romi.dashboard.routes.*

fun main(args: Array<String>) {
    val config = DashboardConfig.load()
    
    val app = Javalin.create { cfg: JavalinConfig ->
        cfg.http.defaultContentType = "application/json"
        cfg.staticFiles.add("/web", Location.CLASSPATH)  // Vue SPA
        cfg.bundledPlugins.enableCors()
        cfg.requestLogger.slf4j { it.level = "INFO" }
    }
    
    // Routes
    NetworkRoutes.register(app, config)
    FirmwareRoutes.register(app, config)
    SystemRoutes.register(app, config)
    Nt4Routes.register(app, config)
    ConfigServerRoutes.register(app, config)  // Legacy compat
    
    // Health check
    app.get("/health") { ctx -> ctx.result("OK") }
    
    // SPA fallback
    app.get("/*") { ctx ->
        ctx.redirect("/web/index.html")
    }
    
    app.start(config.host, config.port)
    println("Romi Dashboard started on http://${config.host}:${config.port}")
}
```

## Configuration (application.yml)

```yaml
# src/main/resources/application.yml
server:
  host: "0.0.0.0"
  port: 5801

nt4:
  # Connect to robot NT4 server (desktop/sim)
  # Override via NT4_SERVER env var
  server: "10.0.0.2"  # Default robot IP
  port: 5810          # NT4 WebSocket port
  reconnect_interval_ms: 5000

flash:
  device: "/dev/ttyAMA0"      # RPi UART0
  baud: 57600
  programmer: "avr109"
  mcu: "m32u4"
  firmware_dir: "/opt/romi/firmware"

network:
  ap_ssid_prefix: "WPILibPi-"
  ap_password: "WPILib2026!"
  ethernet_static_ip: "10.0.0.2/24"
```

## Key Services

### FlashService (avrdude wrapper)

```kotlin
// FlashService.kt
@Service
class FlashService(private val config: DashboardConfig) {
    
    data class FlashResult(
        val success: Boolean,
        val output: String,
        val error: String?
    )
    
    suspend fun flashFirmware(hexPath: String, progress: (Int, String) -> Unit): FlashResult {
        val cmd = listOf(
            "avrdude",
            "-c", config.flash.programmer,
            "-p", config.flash.mcu,
            "-P", config.flash.device,
            "-b", config.flash.baud.toString(),
            "-U", "flash:w:$hexPath:i",
            "-U", "flash:v:$hexPath:i"  // verify
        )
        
        return ProcessUtil.runWithProgress(cmd, progress)
    }
    
    fun listBundledFirmware(): List<FirmwareInfo> {
        // Scan firmware_dir for .hex files + version.json
    }
}
```

### NT4 WebSocket Bridge

```kotlin
// Nt4Bridge.kt
@Service
class Nt4Bridge(private val config: DashboardConfig) {
    
    private val client = NetworkTableInstance.getDefault()
    private var connected = false
    
    @PostConstruct
    fun start() {
        client.startClient4("romi-dashboard")
        client.setServer(config.nt4.server, config.nt4.port)
        client.addConnectionListener({ event ->
            connected = event.isConnected
            // Broadcast connection status via WebSocket
        }, EventFlags.K_IMMEDIATE)
    }
    
    // Expose NT topics via REST for Vue
    fun getTopicValue(topic: String): Any? = client.getEntry(topic).getValue()
    fun setTopicValue(topic: String, value: Any) = client.getEntry(topic).setValue(value)
    
    // WebSocket endpoint for real-time updates
    fun registerWebSocket(app: Javalin) {
        app.ws("/nt4/ws") { ws ->
            ws.onMessage { msg ->
                // Parse JSON: {action: "subscribe"|"publish", topic: "...", value: ...}
            }
            ws.onClose { /* cleanup */ }
        }
    }
}
```

### NetworkService (NetworkManager wrapper)

```kotlin
// NetworkService.kt
@Service
class NetworkService {
    
    data class ApConfig(
        val ssid: String,
        val password: String,
        val enabled: Boolean
    )
    
    suspend fun getApConfig(): ApConfig = ProcessUtil.runJson("nmcli -j connection show Romi-AP")
    
    suspend fun setApConfig(ssid: String, password: String): Result<Unit> {
        return ProcessUtil.run(
            "nmcli", "connection", "modify", "Romi-AP",
            "802-11-wireless.ssid", ssid,
            "802-11-wireless-security.psk", password
        ).map { _ -> Unit }
    }
    
    suspend fun listWifiNetworks(): List<WifiNetwork> = 
        ProcessUtil.runJson("nmcli -j device wifi list")
    
    suspend fun connectWifi(ssid: String, password: String): Result<Unit> =
        ProcessUtil.run("nmcli", "device", "wifi", "connect", ssid, "password", password)
}
```

## Systemd Service

```ini
# /lib/systemd/system/romi-dashboard.service
[Unit]
Description=Romi Dashboard Web Server
After=network.target photonvision.service
Wants=photonvision.service

[Service]
Type=simple
User=romi
Group=romi
WorkingDirectory=/opt/romi-dashboard
ExecStart=/usr/bin/java -Xmx256m -jar /opt/romi-dashboard/romi-dashboard.jar
Restart=on-failure
RestartSec=2
Environment=NT4_SERVER=10.0.0.2

[Install]
WantedBy=multi-user.target
```

## Vue Frontend (Key Composables)

```typescript
// composables/useFirmware.ts
export function useFirmware() {
    const flashProgress = ref(0)
    const flashStatus = ref<'idle' | 'flashing' | 'verifying' | 'success' | 'error'>('idle')
    const flashOutput = ref('')
    
    async function flash(hexFile: File) {
        flashStatus.value = 'flashing'
        flashProgress.value = 0
        
        const formData = new FormData()
        formData.append('firmware', hexFile)
        
        const response = await fetch('/api/firmware/flash', {
            method: 'POST',
            body: formData
        })
        
        // Handle SSE/WebSocket progress updates
        const reader = response.body?.getReader()
        // ... parse progress events
    }
    
    return { flashProgress, flashStatus, flashOutput, flash }
}
```

## Testing

```bash
# Unit tests
./gradlew test

# Integration test (requires PhotonVision + NT4 server)
./gradlew integrationTest

# Build JAR
./gradlew shadowJar

# Run locally
java -jar build/libs/romi-dashboard-2026.0.0.jar
```

## Deployment to Image

Stage `05-romi-dashboard.sh`:
```bash
#!/bin/bash
# Copy shadowJar to /opt/romi-dashboard/
# Install systemd service
# Enable service
```

## References

- PhotonVision Gradle setup: https://github.com/PhotonVision/photonvision/blob/v2026.3.4/photon-server/build.gradle
- Javalin docs: https://javalin.io/documentation
- Vue 3 + TypeScript + Vite: https://vite.dev/guide/
- WPILib NT4 Java: https://github.com/wpilibsuite/allwpilib/tree/main/ntcore/java