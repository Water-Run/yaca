#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-09-23
# File: extract_sdk71.py
# Description: Extract SDK 7.1 build files without running MSI installation actions.

"""Extract SDK 7.1 build files without running MSI installation actions.

Inputs are the verified SDK ISO's Setup directory and UTF-8 inventories from
msi_inventory.exe. The result is private build input, never a toolbox payload.
Run under run_with_resource_guard.sh. No registry, PATH or system files change.
"""

import argparse
import hashlib
import pathlib
import shutil
import subprocess
import tempfile


PACKAGES = ("vc_stdx86/vc_stdx86", "WinSDKBuild/WinSDKBuild_x86",
            "WinSDKTools/WinSDKTools_x86", "WinSDKWin32Tools/WinSDKWin32Tools_x86")


# Extracts a safe basename from an archive member path.
#@param value object Candidate value under validation.
#@return str name Safe final path component of an archive member.
def leaf(value):
    value = value.split(":", 1)[0].split("|")[-1]
    if value in ("", "..") or any(c in value for c in "/\\:\0\r\n"):
        raise ValueError("unsafe MSI path component")
    return value


# Computes the SHA-256 digest of one input file.
#@param path Path|str Input file or package path under inspection.
#@return bytes digest Raw SHA-256 digest of an extracted SDK input.
def digest(path):
    return hashlib.sha256(path.read_bytes()).digest()


# Extracts selected Windows SDK files from pinned setup archives.
#@param setup object The setup supplied to this proof operation.
#@param inventories object The inventories supplied to this proof operation.
#@param output Path Destination for staged proof artifacts.
#@return None result No value; writes selected SDK members beneath the staging root.
def extract(setup, inventories, output):
    output.mkdir()
    for package in PACKAGES:
        package = pathlib.Path(package)
        directories, components, files = {}, {}, []
        inventory = inventories / (package.name + ".tsv")
        for row in inventory.read_text(encoding="utf-8").splitlines():
            kind, name, second, third = row.split("\t")
            if kind == "Directory":
                directories[name] = (second, third)
            elif kind == "Component":
                components[name] = second
            elif kind == "File":
                files.append((name, second, third))
            else:
                raise ValueError("unknown MSI inventory row")

        # Creates a required destination directory under the staging root.
        #@param name str Selected fixture, component, or tool name.
        #@param ancestors object The ancestors supplied to this proof operation.
        #@return Path path Safe destination for the selected archive directory.
        def directory(name, ancestors=()):
            if name == "TARGETDIR":
                return pathlib.Path(".")
            if name in ancestors or name not in directories:
                raise ValueError("unresolved MSI directory: " + name)
            parent, filename = directories[name]
            prefix = directory(parent, ancestors + (name,))
            filename = leaf(filename)
            return prefix if filename == "." else prefix / filename

        with tempfile.TemporaryDirectory(prefix="sdk-cab-", dir=output) as temporary:
            cabinets = sorted((setup / package.parent).glob("*.cab"))
            if not cabinets:
                raise ValueError("SDK package cabinets are missing")
            for cabinet in cabinets:
                subprocess.check_call(["cabextract", "-q", "-d", temporary, str(cabinet)])
            for identifier, component, filename in files:
                source = pathlib.Path(temporary) / leaf(identifier)
                destination = output / directory(components[component]) / leaf(filename)
                destination.parent.mkdir(parents=True, exist_ok=True)
                if destination.exists() and digest(destination) != digest(source):
                    raise ValueError("conflicting SDK file: " + str(destination))
                shutil.copyfile(source, destination)
                if destination.suffix.lower() in (".exe", ".dll"):
                    destination.chmod(0o755)
        shutil.copyfile(inventory, output / inventory.name)
    print("sdk71-extract=PASS installation-actions=none")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("setup", type=pathlib.Path)
    parser.add_argument("inventories", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    extract(args.setup.resolve(), args.inventories.resolve(), args.output.resolve())
