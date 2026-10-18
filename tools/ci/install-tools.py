#!/usr/bin/env python3
"""Install pinned, checksum-verified validation binaries in the CI workspace."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import tarfile
import tempfile
import urllib.request
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        parser.error("the pinned toolchain requires Linux amd64")
    args.directory.mkdir(parents=True, exist_ok=True)
    tools = json.loads(Path(__file__).with_name("toolchain.json").read_text())
    with tempfile.TemporaryDirectory(prefix="iac-ci-tools-") as directory:
        for tool in tools:
            archive = Path(directory) / tool["binary"]
            with urllib.request.urlopen(tool["url"], timeout=120) as response:
                with archive.open("wb") as destination:
                    shutil.copyfileobj(response, destination)
            with archive.open("rb") as source:
                digest = hashlib.file_digest(source, "sha256").hexdigest()
            if digest != tool["sha256"]:
                raise RuntimeError(f"checksum mismatch for {tool['binary']}")
            target = args.directory / tool["binary"]
            if tool["format"] == "zip":
                with zipfile.ZipFile(archive) as bundle:
                    target.write_bytes(bundle.read(tool["member"]))
            elif tool["format"] == "tar.gz":
                with tarfile.open(archive) as bundle:
                    source = bundle.extractfile(tool["member"])
                    if source is None:
                        raise RuntimeError(f"missing binary {tool['member']}")
                    with source, target.open("wb") as destination:
                        shutil.copyfileobj(source, destination)
            else:
                shutil.copyfile(archive, target)
            target.chmod(0o755)
            print(f"Installed {tool['binary']} {tool['version']}", flush=True)


if __name__ == "__main__":
    main()
