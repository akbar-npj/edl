# EDL (edlclient) Compilation & Packaging Guide

This guide provides comprehensive instructions for building, packaging, and installing **EDL (edlclient)** as a native RPM package on Fedora, Fedora Asahi Remix (Apple Silicon `aarch64`), RHEL, and compatible distributions, as well as alternative installation methods.

---

## Table of Contents

- [Overview](#overview)
- [Architecture & Package Design](#architecture--package-design)
- [Prerequisites & Build Dependencies](#prerequisites--build-dependencies)
  - [Fedora / Fedora Asahi Remix / RHEL](#fedora--fedora-asahi-remix--rhel)
  - [Debian / Ubuntu](#debian--ubuntu)
  - [Arch Linux](#arch-linux)
- [RPM Package Compilation Guide (Fedora / RHEL)](#rpm-package-compilation-guide-fedora--rhel)
  - [1. Initialize RPM Build Environment](#1-initialize-rpm-build-environment)
  - [2. Clone Repository & Initialize Submodules](#2-clone-repository--initialize-submodules)
  - [3. Generate Source Tarball](#3-generate-source-tarball)
  - [4. Stage the RPM Spec File](#4-stage-the-rpm-spec-file)
  - [5. Compile Binary and Source RPMs](#5-compile-binary-and-source-rpms)
  - [6. Install the Generated RPM](#6-install-the-generated-rpm)
  - [7. Configure Hardware Permissions & Udev](#7-configure-hardware-permissions--udev)
- [Alternative Installation Methods](#alternative-installation-methods)
  - [Using pip (User Mode)](#using-pip-user-mode)
  - [Using a Virtual Environment (venv)](#using-a-virtual-environment-venv)
  - [Using uv](#using-uv)
- [Package Verification & Testing](#package-verification--testing)
  - [Inspecting the RPM Package](#inspecting-the-rpm-package)
  - [Testing Installed CLI Tools](#testing-installed-cli-tools)
- [Hardware Troubleshooting & FAQ](#hardware-troubleshooting--faq)
  - [1. Qualcomm EDL 9008 Device Not Detected](#1-qualcomm-edl-9008-device-not-detected)
  - [2. Permission Denied on USB Device](#2-permission-denied-on-usb-device)
  - [3. qcserial or cdc_acm Driver Conflicts](#3-qcserial-or-cdc_acm-driver-conflicts)
  - [4. ModemManager Interference](#4-modemmanager-interference)
  - [5. Sahara V3 Extended Chip Detection](#5-sahara-v3-extended-chip-detection)

---

## Overview

`EDL` (edlclient) is an open-source reverse-engineering, forensic dumping, exploitation, and flashing toolkit for Qualcomm Snapdragon and MDM SoCs. It implements the Qualcomm Sahara and Firehose Emergency Download (EDL) protocols over USB.

Key features include:
- Sahara protocol handshake, memory dumping, and Primary Bootloader (PBL) retrieval.
- **Sahara V3 support** (enhanced in this fork): extended chip identification (`cmd=0x0A`) for `MSM_ID`, `OEM_ID`, `MODEL_ID`, and PKHash autodetection on modern Snapdragon SoCs (SM8350, SM8450, SM8550, etc.).
- Firehose XML/raw command execution, partition read/write (GPT, LUN management, raw XML).
- Comprehensive built-in **Qualcomm Firehose Loaders database** covering Xiaomi, OnePlus, Oppo, Vivo, LG, Samsung, Quectel, ZTE, and generic platforms.
- Partition slot switching (Slot A/B), UFS provisioning, and partition erasing.
- Diagnostic and utility suite: `qc_diag`, `fhloaderparse`, `sierrakeygen`, `boottodwnload`, `enableadb`, and `ubidump`.

---

## Architecture & Package Design

The RPM package is built with `BuildArch: noarch`:
- All client and execution logic is implemented in **Python 3**.
- Embedded programmer binaries (`Loaders/*.bin`, `*.mbn`, `*.elf`) are ARM/Qualcomm target device firmware payloads rather than host Linux executables, allowing the package to run seamlessly across both `x86_64` and `aarch64` (including Apple Silicon on Fedora Linux Asahi Remix).
- Host-incompatible precompiled binaries (e.g. legacy x86_64 helper binaries) and Windows DLLs are cleanly excluded from the Linux RPM package.
- System integration is handled automatically:
  - Standard commands in `/usr/bin/` (`edl`, `qc_diag`, `sierrakeygen`, `boottodwnload`, `enableadb`, `fhloaderparse`, `beagle_to_loader`, `ubidump`, `qc_nand_extract.py`).
  - Backward-compatible symlinks (`edl.py`, `qc_diag.py`, `sierrakeygen.py`, etc.).
  - Udev rules in `/usr/lib/udev/rules.d/51-edl.rules` for non-root USB device access (`uaccess`, `0666`).
  - Kernel module blacklist in `/usr/lib/modprobe.d/blacklist-qcserial.conf` to prevent the Linux kernel `qcserial` driver from monopolizing the raw USB endpoint.

---

## Prerequisites & Build Dependencies

### Fedora / Fedora Asahi Remix / RHEL

Install the build toolchain and RPM utilities:

```bash
sudo dnf install -y \
    python3 \
    python3-devel \
    python3-pip \
    python3-setuptools \
    rpm-build \
    systemd-rpm-macros \
    git \
    libusb1
```

For runtime dependencies (automatically satisfied when installing the compiled RPM):

```bash
sudo dnf install -y \
    python3-pyusb \
    python3-pyserial \
    python3-docopt \
    python3-colorama \
    python3-lxml \
    python3-requests \
    python3-pycryptodomex \
    python3-passlib \
    python3-paramiko \
    python3-capstone
```

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install -y \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-pyusb \
    python3-serial \
    python3-colorama \
    python3-docopt \
    python3-lxml \
    python3-requests \
    python3-cryptography \
    libusb-1.0-0-dev \
    git
```

### Arch Linux

```bash
sudo pacman -S --needed \
    python \
    python-pip \
    python-setuptools \
    python-pyusb \
    python-pyserial \
    python-colorama \
    python-docopt \
    python-lxml \
    python-requests \
    python-pycryptodome \
    libusb \
    git
```

---

## RPM Package Compilation Guide (Fedora / RHEL)

### Quick Start: Automated Compilation (`build.sh`)

An automated build script [`build.sh`](build.sh) is provided in the repository to orchestrate the entire compilation and testing pipeline:

```bash
# 1. Run automated build and verification tests
./build.sh

# 2. Or build, verify, and prompt to install directly
./build.sh --install
```

`build.sh` automatically performs:
- Dependency validation (`rpmbuild`, `python3`, `git`, `tar`).
- Submodule check and clone (`Loaders`).
- Source archive generation with symlink protection.
- Spec staging and `rpmbuild -ba` compilation.
- Automated package verification (metadata query, capability checks, required binary checks).
- `dnf` dry-run transaction test to verify all dependencies are resolvable from system repositories.

---

### Manual Compilation Walkthrough

If you prefer building manually without `build.sh`:

#### 1. Initialize RPM Build Environment

Create the standard `rpmbuild` directory tree in your home directory:

```bash
mkdir -p ~/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
```

#### 2. Clone Repository & Initialize Submodules

Ensure you clone the repository and initialize the `Loaders` submodule:

```bash
git clone https://github.com/akbar-npj/edl.git
cd edl
git submodule update --init --recursive
```

Verify that the `Loaders` directory contains Qualcomm programmer binaries:

```bash
ls -d Loaders/*/ | head -n 10
```

#### 3. Generate Source Tarball

Package the source tree into `~/rpmbuild/SOURCES/edl-3.62.tar.gz`. Use the `S` flag in `--transform` to prevent modifying symbolic link targets:

```bash
tar --exclude-vcs \
    --exclude="*.pyc" \
    --exclude="__pycache__" \
    --exclude="fastpwn" \
    --exclude="fastpwn.exe" \
    --exclude="edlclient.egg-info" \
    --exclude="build" \
    --exclude="dist" \
    --exclude="*.whl" \
    --transform "s,^\./,edl-3.62/,S" \
    --transform "s,^\.$,edl-3.62,S" \
    -czf ~/rpmbuild/SOURCES/edl-3.62.tar.gz .
```

Verify that the archive contains the source files with the expected prefix:

```bash
tar -tzf ~/rpmbuild/SOURCES/edl-3.62.tar.gz | head -n 15
```

### 4. Stage the RPM Spec File

Copy `edl.spec` to the RPM specifications directory:

```bash
cp edl.spec ~/rpmbuild/SPECS/
```

### 5. Compile Binary and Source RPMs

Execute `rpmbuild` to compile the package:

```bash
rpmbuild -ba ~/rpmbuild/SPECS/edl.spec
```

Upon successful compilation, the output packages are created at:
- **Binary RPM:** `~/rpmbuild/RPMS/noarch/edl-3.62-1.fc*.noarch.rpm`
- **Source RPM (SRPM):** `~/rpmbuild/SRPMS/edl-3.62-1.fc*.src.rpm`

### 6. Install the Generated RPM

Install the package directly using `dnf` (which automatically pulls in any required Python runtime dependencies):

```bash
sudo dnf install ~/rpmbuild/RPMS/noarch/edl-3.62-1.fc*.noarch.rpm
```

Alternatively, install using `rpm`:

```bash
sudo rpm -Uvh ~/rpmbuild/RPMS/noarch/edl-3.62-1.fc*.noarch.rpm
```

### 7. Configure Hardware Permissions & Udev

1. Reload the udev subsystem to apply the Qualcomm EDL udev rules:
   ```bash
   sudo udevadm control --reload-rules
   sudo udevadm trigger
   ```

2. Add your user account to the `dialout` and `plugdev` groups to allow non-root USB access:
   ```bash
   sudo usermod -aG dialout,plugdev $USER
   ```

3. Update the kernel module dependencies to respect `blacklist-qcserial.conf`:
   ```bash
   sudo depmod -a
   ```

4. Log out and log back in (or reboot) for user group changes to take full effect.

---

## Alternative Installation Methods

If you prefer installing directly without RPM:

### Using pip (User Mode)

```bash
cd edl
git submodule update --init --recursive
pip install --user .
```

For editable / development mode:

```bash
pip install --user -e .
```

### Using a Virtual Environment (venv)

```bash
cd edl
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install -e .
edl --help
```

### Using uv

```bash
cd edl
uv sync
uv run edl --help
```

---

## Package Verification & Testing

### Inspecting the RPM Package

Query package metadata, capabilities, and dependencies:

```bash
# View general package details
rpm -qip ~/rpmbuild/RPMS/noarch/edl-3.62-*.rpm

# List all installed files and symlinks
rpm -qlp ~/rpmbuild/RPMS/noarch/edl-3.62-*.rpm

# Check package provides
rpm -qp --provides ~/rpmbuild/RPMS/noarch/edl-3.62-*.rpm

# Verify runtime requirements
rpm -qp --requires ~/rpmbuild/RPMS/noarch/edl-3.62-*.rpm
```

### Testing Installed CLI Tools

Test the primary commands and entrypoints:

```bash
# Print general usage and firehose subcommands
edl --help

# Verify backward compatibility symlink
edl.py --help

# Diagnostic tool
qc_diag --help

# Loader parser
fhloaderparse --help

# UBI image extraction utility
ubidump --help
```

---

## Hardware Troubleshooting & FAQ

### 1. Qualcomm EDL 9008 Device Not Detected

**Symptoms:** `edl` loops waiting for device or prints `Device not found`.  
**Resolution:**
- Confirm the device is recognized on the USB bus:
  ```bash
  lsusb | grep -i "05c6:9008"
  ```
- Put the device into EDL mode:
  - **Hardware Key Combination:** Power off the device completely, hold both `Volume Up` and `Volume Down` (or `Volume Down` only on some devices), then insert the USB cable connected to the computer.
  - **ADB Command:** If Android is booted with USB debugging enabled, run `adb reboot edl`.
  - **Fastboot Command:** If the bootloader allows, run `fastboot oem edl` or `fastboot reboot-edl`.
  - **Hardware Testpoints:** For bricked devices, short the EDL testpoint to ground while connecting USB.

### 2. Permission Denied on USB Device

**Symptoms:** `usb.core.USBError: [Errno 13] Access denied (insufficient permissions)`.  
**Resolution:**
- Check that udev rules are installed and active:
  ```bash
  ls -l /usr/lib/udev/rules.d/51-edl.rules
  sudo udevadm control --reload-rules && sudo udevadm trigger
  ```
- Confirm your user belongs to `dialout` and `plugdev`:
  ```bash
  groups $USER
  ```
- If needed, run the command temporarily under `sudo` to determine if permissions are the sole root cause.

### 3. qcserial or cdc_acm Driver Conflicts

**Symptoms:** `pyusb` cannot claim the interface or disconnects immediately after handshake.  
**Resolution:**
- The Linux kernel driver `qcserial` may bind automatically to VID/PID `05c6:9008`.
- The installed RPM configures `/usr/lib/modprobe.d/blacklist-qcserial.conf` with:
  ```
  blacklist qcserial
  blacklist cdc_acm
  ```
- Unload the module immediately if currently loaded:
  ```bash
  sudo rmmod qcserial 2>/dev/null || true
  ```

### 4. ModemManager Interference

**Symptoms:** Port is busy, communication timeouts during Sahara handshake.  
**Resolution:**
- `ModemManager` attempts to probe newly connected cellular and diagnostic serial ports.
- Stop or mask `ModemManager`:
  ```bash
  sudo systemctl stop ModemManager
  sudo systemctl disable ModemManager
  ```

### 5. Sahara V3 Extended Chip Detection

**Usage:**
- Devices using Sahara Protocol V3 (e.g. Snapdragon 8 Gen 1/2/3, SM8450, SM8550) use extended info command `cmd=0x0A`.
- If automatic loader matching still fails due to unusual vendor hash configurations, explicitly supply the programmer loader with the `--loader` option:
  ```bash
  edl printgpt --loader=/path/to/prog_firehose_lite.elf
  ```
