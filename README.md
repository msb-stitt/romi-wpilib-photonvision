# romi-wpilib-photonvision

A Raspberry Pi OS image for the Romi's Raspberry Pi that runs PhotonVision beside the Romi's own
service. Robot code runs in simulation on a host PC, drives the Romi, and reads AprilTag results
from PhotonVision on the robot, over the links the Romi and PhotonVision normally use.

It is a work in progress, tracked by the plan *One Pi image for the Romi and PhotonVision* in
`ftc-claude`. [ADR-003](.docs/architecture/ADR-003-base-and-network.md) records the decisions
and the versions used.

## What the image does

- **An access point, `WPILibPi-` and the last 8 hex digits of the Pi's serial number, with the
  Pi at `10.0.0.2`**, as WPILibPi's images had. The host PC joins it. Until it is renamed, the Pi
  speaks the name through its headphone jack.
- **`wpilibws-romi`**, which robot code on the host PC reaches through WPILib's WebSocket
  simulation extension.
- **PhotonVision**, on port 5800, which finds the simulation's NetworkTables by itself.
- **Cockpit**, on port 9090, with a Romi page first in its menu: the service's status and log,
  the external IO, the gyro calibration, the 32U4's firmware, the WiFi and Ethernet settings,
  `romi.json`, and which build made the card.
- **One account, `pi`, password `raspberry`.**

## Building it

`image/build.sh` makes the image from Raspberry Pi OS Trixie Lite by running the scripts in
`image/stages/` inside it. It runs as root on Linux, and prints its commands without running them
unless `DRY_RUN=0` is set. A stage can also be run on a running Pi. Each build records its commit,
the base image and its Debian packages, next to the image and on the card; `SOURCES.md`, next to
the image, links to the upstream source of the programs it holds.

The workflow in `.github/workflows/image.yml` builds the image on GitHub's arm64 runners and boots
its root as a container, with `image/test/container.sh`, to check its services and drive it from
`romiPyKitTiny` in simulation; a tag starting with `v` publishes an image that passed as a
release. `container.sh` runs the same way on an arm64 Linux machine.

## Documentation

`.docs/bibliography.md` maps the documents in `.docs/`. The integration plan and the parts in
`.docs/parts/` describe an earlier design and are superseded.

## License

- **This project**: BSD 3-Clause (see `LICENSE`)
- **WPILib**: BSD-3-Clause (upstream, used as library)
- **Raspberry Pi OS**: its own licenses

## Links

- PhotonVision: https://photonvision.org / https://github.com/PhotonVision
- WPILib: https://github.com/wpilibsuite/allwpilib
- Romi Robot: https://docs.wpilib.org/en/stable/docs/romi-robot/
- WPILibPi: https://github.com/wpilibsuite/WPILibPi
