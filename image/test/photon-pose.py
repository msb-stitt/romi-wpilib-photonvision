#!/usr/bin/env python3
"""photon-pose.py CAMERA: check that PhotonVision publishes an AprilTag pose for CAMERA.

Connects to the NetworkTables server on this host, the robot simulation, and reads
/photonvision/CAMERA/hasTarget and targetPose, a Transform3d struct of seven doubles: translation
x, y and z in metres and the rotation's quaternion w, x, y and z. Exits 1 if no pose arrives in
30 s. Run with a Python that has pyntcore, such as the robot project's.
"""

import math
import struct
import sys
import time

import ntcore


def main(camera):
    inst = ntcore.NetworkTableInstance.create()
    ntcore.MultiSubscriber(inst, ["/photonvision"])
    inst.startClient4("photon-pose")
    inst.setServer("127.0.0.1")
    has_target = inst.getEntry(f"/photonvision/{camera}/hasTarget")
    pose = inst.getEntry(f"/photonvision/{camera}/targetPose")
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        value = pose.getValue()
        if has_target.getBoolean(False) and value.isValid() and len(value.value()) == 56:
            x, y, z, qw, qx, qy, qz = struct.unpack("<7d", value.value())
            print(f"{camera} targetPose: x {x:.3f} m, y {y:.3f} m, z {z:.3f} m, "
                  f"{math.hypot(x, y, z):.3f} m away; quaternion w {qw:.3f} x {qx:.3f} "
                  f"y {qy:.3f} z {qz:.3f}")
            return 0
        time.sleep(0.5)
    print(f"no pose from /photonvision/{camera} in 30 s")
    return 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: photon-pose.py CAMERA")
    sys.exit(main(sys.argv[1]))
