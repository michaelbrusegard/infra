import re
import sys
from pathlib import Path

BUILD_ID = "BP1A.250505.005.B1"
INCREMENTAL = "13277630"
FINGERPRINT = f"google/shiba/shiba:15/{BUILD_ID}/{INCREMENTAL}:user/release-keys"
VALUES = {
    r"ro\.product\.(\w+\.)?brand": "google",
    r"ro\.product\.(\w+\.)?manufacturer": "Google",
    r"ro\.product\.(\w+\.)?model": "Pixel 8",
    r"ro\.product\.(\w+\.)?(name|device)": "shiba",
    r"ro\.(\w+\.)?build\.fingerprint": FINGERPRINT,
    r"ro\.(\w+\.)?build\.id": BUILD_ID,
    r"ro\.(\w+\.)?build\.version\.incremental": INCREMENTAL,
    r"ro\.(\w+\.)?build\.date": "Wed Mar 26 23:12:07 UTC 2025",
    r"ro\.(\w+\.)?build\.date\.utc": "1743030727",
    r"ro\.(\w+\.)?build\.type": "user",
    r"ro\.(\w+\.)?build\.tags": "release-keys",
    r"ro\.build\.display\.id": BUILD_ID,
    r"ro\.build\.description": f"shiba-user 15 {BUILD_ID} {INCREMENTAL} release-keys",
    r"ro\.build\.flavor": "shiba-user",
    r"ro\.build\.product": "shiba",
}
REQUIRED = {
    "system/build.prop": (
        "ro.system.build.fingerprint",
        "ro.product.system.model",
        "ro.build.description",
    ),
    "vendor/build.prop": ("ro.vendor.build.fingerprint", "ro.product.vendor.model"),
}
HARDWARE = "vendor/etc/permissions/handheld_core_hardware.xml"
UNSUPPORTED = (
    "android.hardware.camera",
    "android.hardware.sensor.accelerometer",
    "android.hardware.sensor.compass",
)


def brand(path: Path) -> set[str]:
    changed = set()
    lines = []
    for line in path.read_text().splitlines(keepends=True):
        key, separator, _ = line.strip().partition("=")
        value = next(
            (value for pattern, value in VALUES.items() if re.fullmatch(pattern, key)),
            None,
        )
        if separator and value is not None:
            lines.append(f"{key}={value}\n")
            changed.add(key)
        else:
            lines.append(line)
    if any("redroid_x86_64_only" in line for line in lines if not line.startswith("#")):
        raise ValueError(f"{path} still names the source build")
    path.write_text("".join(lines))
    return changed


def main() -> None:
    rootfs = Path(sys.argv[1])
    for path in sorted(rootfs.rglob("build.prop")):
        changed = brand(path)
        missing = set(REQUIRED.get(str(path.relative_to(rootfs)), ())) - changed
        if missing:
            raise ValueError(f"{path} lacks {sorted(missing)}")
    hardware = rootfs / HARDWARE
    text = hardware.read_text()
    for feature in UNSUPPORTED:
        line = f'    <feature name="{feature}" />\n'
        if text.count(line) != 1:
            raise ValueError(f"{HARDWARE} does not declare {feature} once")
        text = text.replace(line, "")
    hardware.write_text(text)


if __name__ == "__main__":
    main()
