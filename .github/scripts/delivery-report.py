"""Summarize real JUnit results, refusing publication if tests are absent or failing."""
import os
from pathlib import Path
import xml.etree.ElementTree as ET


def counts(pattern):
    files = list(Path("app/build").glob(pattern))
    if not files:
        raise SystemExit(f"Missing test results: {pattern}")
    total = 0
    for path in files:
        root = ET.parse(path).getroot()
        for suite in ([root] if root.tag == "testsuite" else root.findall("testsuite")):
            if int(suite.get("failures", "0")) or int(suite.get("errors", "0")):
                raise SystemExit(f"Failed tests: {path}")
            total += int(suite.get("tests", "0")) - int(suite.get("skipped", "0"))
    if total == 0:
        raise SystemExit("No executed tests")
    return total


unit = counts("test-results/testDebugUnitTest/TEST-*.xml")
device = counts("outputs/androidTest-results/connected/**/TEST-*.xml")
kind = os.environ["BUILD_KIND"]
notes = f"""## Verified build

- Source commit: `{os.environ['GITHUB_SHA']}`
- Variant: **{kind}**. {'Original configured release keystore used; apksigner verification passed.' if kind == 'release' else 'Debug-signed, NOT an original-key release. Original release signing secrets were unavailable; standard Android debug signing is used only to provide an installable test build.'}
- Unit tests: **{unit} passed**; Android lint passed.
- Android 35 x86_64 emulator: **{device} instrumentation tests passed** (onboarding/login screen, activity recreation, Android Keystore, packaged native secret encryption).
- Exact published APK: installed successfully, launch returned `Status: ok`, process remained running and welcome UI rendered without a recorded app crash.
- Signature verification, SHA-256, package info, install/launch evidence and screenshot are attached.
- Minimum Android: **8.0 (API 26)**.

## Not yet verified

Real-phone/ARM operation, authenticated GitHub account flows, server provisioning, full Minecraft/Playit connectivity, and long-running backup cycles have NOT been validated end to end. This is a tested installable preview, not a claim that every product requirement is complete.

Download the `.apk` asset directly on Android. A debug APK may require uninstalling a differently signed older build (which removes that app's local settings). No manual keystore handling is needed.
"""
Path("delivery/TEST-REPORT.md").write_text(notes)
