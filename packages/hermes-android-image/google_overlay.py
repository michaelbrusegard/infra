import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

TRANSLATOR_FILES = [
    "system/bin/arm64",
    "system/lib64/arm64",
    "system/bin/ndk_translation_program_runner_binfmt_misc_arm64",
    "system/etc/init/ndk_translation.rc",
    "system/etc/ld.config.arm64.txt",
    "system/etc/cpuinfo.arm64.txt",
    "system/etc/binfmt_misc/arm64_exe",
    "system/etc/binfmt_misc/arm64_dyn",
]
GOOGLE_PACKAGES = [
    (
        "product",
        "PrebuiltGmsCore",
        "com.google.android.gms",
        "7ce83c1b71f3d572fed04c8d40c5cb10ff75e6d87d9df6fbd53f0468c2905053",
    ),
    (
        "product",
        "Phonesky",
        "com.android.vending",
        "f0fd6c5b410f25cb25c3b53346c8972fae30f8ee7411df910480ad6b2d60db83",
    ),
    (
        "system_ext",
        "GoogleServicesFramework",
        "com.google.android.gsf",
        "7ce83c1b71f3d572fed04c8d40c5cb10ff75e6d87d9df6fbd53f0468c2905053",
    ),
]
AARCH64_RET = bytes.fromhex("c0035fd6")


def extract(
    archive: Path, directory: Path, partitions: tuple[str, ...]
) -> dict[str, Path]:
    with zipfile.ZipFile(archive) as source:
        source.extract("x86_64/system.img", directory)
    disk = directory / "x86_64/system.img"
    table = json.loads(subprocess.check_output(["sfdisk", "--json", str(disk)]))[
        "partitiontable"
    ]
    (partition,) = [
        entry for entry in table["partitions"] if entry.get("name") == "super"
    ]
    super_image = directory / "super.img"
    sector = table["sectorsize"]
    subprocess.run(
        [
            "dd",
            f"if={disk}",
            f"of={super_image}",
            "bs=4M",
            "iflag=skip_bytes,count_bytes",
            f"skip={partition['start'] * sector}",
            f"count={partition['size'] * sector}",
            "status=none",
        ],
        check=True,
    )
    disk.unlink()
    images = directory / "partitions"
    images.mkdir()
    subprocess.run(
        [
            "python3",
            "/inputs/lpunpack.py",
            "-p",
            ",".join(partitions),
            str(super_image),
            str(images),
        ],
        check=True,
    )
    super_image.unlink()
    roots = {}
    for name in partitions:
        root = directory / name
        root.mkdir()
        image = images / f"{name}.img"
        kind = subprocess.check_output(
            ["blkid", "-o", "value", "-s", "TYPE", str(image)], text=True
        ).strip()
        if kind == "erofs":
            subprocess.run(["fsck.erofs", f"--extract={root}", str(image)], check=True)
        else:
            subprocess.run(["debugfs", "-R", f"rdump / {root}", str(image)], check=True)
        image.unlink()
        roots[name] = root
    return roots


def disable_cfi_slowpath(library: Path) -> None:
    data = bytearray(library.read_bytes())
    (headers_offset,) = struct.unpack_from("<Q", data, 0x28)
    entry_size, count = struct.unpack_from("<HH", data, 0x3A)
    sections = [
        struct.unpack_from("<IIQQQQIIQQ", data, headers_offset + index * entry_size)
        for index in range(count)
    ]

    def to_offset(address: int) -> int:
        for _, _, _, start, offset, size, *_ in sections:
            if start and start <= address < start + size:
                return offset + (address - start)
        raise ValueError("address is not in any section")

    (dynsym,) = [section for section in sections if section[1] == 11]
    names = sections[dynsym[6]]
    patched = set()
    for offset in range(dynsym[4], dynsym[4] + dynsym[5], dynsym[9]):
        (name_index,) = struct.unpack_from("<I", data, offset)
        (value,) = struct.unpack_from("<Q", data, offset + 8)
        end = data.index(b"\x00", names[4] + name_index)
        name = data[names[4] + name_index : end].decode()
        if name in ("__cfi_slowpath", "__cfi_slowpath_diag") and value:
            start = to_offset(value)
            data[start : start + len(AARCH64_RET)] = AARCH64_RET
            patched.add(name)
    if patched != {"__cfi_slowpath", "__cfi_slowpath_diag"}:
        raise ValueError("guest linker CFI slow path not found")
    library.write_bytes(data)


def copy_translator(source: Path, output: Path) -> None:
    paths = TRANSLATOR_FILES + [
        str(path.relative_to(source))
        for pattern in ("*ndk_translation*", "libberberis*")
        for path in (source / "system/lib64").glob(pattern)
    ]
    if "system/lib64/libndk_translation.so" not in paths:
        raise ValueError("native bridge is missing")
    for name in paths:
        original, target = source / name, output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if original.is_dir():
            shutil.copytree(original, target, symlinks=True)
        else:
            shutil.copy2(original, target, follow_symlinks=False)
    (output / "system/lib64/libnb.so").symlink_to("libndk_translation.so")
    disable_cfi_slowpath(output / "system/lib64/arm64/libdl.so")


def signers(apk: Path, apksigner: Path) -> set[str]:
    report = subprocess.check_output(
        [
            str(apksigner),
            "verify",
            "--verbose",
            "--print-certs",
            "--min-sdk-version",
            "35",
            str(apk),
        ],
        text=True,
    )
    return set(
        re.findall(
            r"^(?:V[\d.]+ )?Signer(?: #\d+)?:? certificate SHA-256 digest: ([0-9a-f]{64})$",
            report,
            re.MULTILINE,
        )
    )


def copy_google_services(roots: dict[str, Path], output: Path, apksigner: Path) -> None:
    for partition, name, _, signer in GOOGLE_PACKAGES:
        (original,) = (roots[partition] / "priv-app").glob(f"{name}*/{name}*.apk")
        if signers(original, apksigner) != {signer}:
            raise ValueError(f"{original.name} has an unexpected signing certificate")
        target = output / "system" / partition / "priv-app" / name / f"{name}.apk"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, target)
        with zipfile.ZipFile(original) as archive:
            for member in archive.namelist():
                if member.startswith("lib/x86_64/") and member.endswith(".so"):
                    library = target.parent / "lib/x86_64" / Path(member).name
                    library.parent.mkdir(parents=True, exist_ok=True)
                    with (
                        archive.open(member) as source,
                        library.open("wb") as destination,
                    ):
                        shutil.copyfileobj(source, destination)
    for partition, root in roots.items():
        selected = {
            package for owner, _, package, _ in GOOGLE_PACKAGES if owner == partition
        }
        permissions = ET.Element("permissions")
        found = set()
        for path in sorted((root / "etc/permissions").glob("*.xml")):
            for element in ET.parse(path).getroot():
                if (
                    element.tag == "privapp-permissions"
                    and element.get("package") in selected
                ):
                    permissions.append(element)
                    found.add(element.get("package"))
        if found != selected:
            raise ValueError("privileged permission list is incomplete")
        target = output / "system" / partition / "etc/permissions/google-services.xml"
        target.parent.mkdir(parents=True, exist_ok=True)
        ET.ElementTree(permissions).write(
            target, encoding="utf-8", xml_declaration=True
        )


def main() -> None:
    inputs, output, apksigner = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    with tempfile.TemporaryDirectory() as temporary:
        roots = extract(inputs / "google-apis.zip", Path(temporary), ("system",))
        copy_translator(roots["system"], output)
    with tempfile.TemporaryDirectory() as temporary:
        roots = extract(
            inputs / "google-play.zip", Path(temporary), ("product", "system_ext")
        )
        copy_google_services(roots, output, apksigner)


if __name__ == "__main__":
    main()
