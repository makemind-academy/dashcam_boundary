#!/usr/bin/env python3
"""dashcam-boundary: the camera reports trips and settings and never describes footage; sensitivity is clamped to its range."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
from appplayer import AppPlayer  # noqa: E402
from mcpclient import Server  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "dashcam_server")
CAP = os.path.join(HERE, "captures")
SERVER_ID = "com.makemind.sample.dashcam"

FORBIDDEN = ["face", "plate", "person", "vehicle", "object"]
with Server(["dart", "run", "bin/server.dart"], cwd=SERVER) as s:
    names = " ".join(s.tool_names()).lower()
    for w in FORBIDDEN:
        assert w not in names, f"tool vocabulary describes footage: {w}"
    trips = s.call("trips.list")
    assert trips["tripCount"] >= 1 and all(r["clip"] for r in trips["rows"])
    clamped = s.call("camera.set_sensitivity", {"level": 9})
    assert clamped["sensitivity"] == "5 of 5", clamped

ap = AppPlayer()
ap.register_server(SERVER_ID, "Dashcam", cwd=SERVER)
ap.restart()
ap.open_server(SERVER_ID)
ap.wait_text("Trips recorded")
ap.expect_aligned("clip:", min_rows=2)
ap.shot(f"{CAP}/01_trips.png")
ap.tap("Sensitivity 9 (asked)")
ap.wait_text("5 of 5")
ap.shot(f"{CAP}/02_clamped.png")
print("dashcam-boundary: trips listed, footage never described, sensitivity clamped to 5 of 5")
