Name:           edl
Version:        3.62
Release:        1%{?dist}
Summary:        Qualcomm Sahara / Firehose exploitation and flashing tool

License:        GPL-3.0-or-later
URL:            https://github.com/akbar-npj/edl
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  python3-devel
BuildRequires:  python3-pip
BuildRequires:  python3-setuptools
BuildRequires:  systemd-rpm-macros

Requires:       python3
Requires:       python3-pyusb
Requires:       python3-pycryptodomex
Requires:       python3-colorama
Requires:       python3-pyserial
Requires:       python3-docopt
Requires:       python3-lxml
Requires:       python3-requests

Recommends:     python3-paramiko
Recommends:     python3-passlib
Recommends:     python3-capstone

Provides:       python3-edl = %{version}-%{release}
Provides:       edlclient = %{version}-%{release}
Provides:       python3-edlclient = %{version}-%{release}

# Filter out unresolvable / version-mismatched python dependencies in Fedora
%global __requires_exclude ^python3(\\.[0-9]+)?dist\\((exscript|pylzma|pycryptodome|requests|paramiko)\\)

# Disable debuginfo package and binary stripping for noarch data payloads (Loaders)
%global debug_package %{nil}
%global __strip /bin/true
%global __brp_strip %{nil}
%global __brp_strip_comment_note %{nil}
%global __brp_strip_static_archive %{nil}

%description
EDL (edlclient) is an open-source reverse engineering, exploit, and flashing
toolkit for Qualcomm Snapdragon / MDM SoCs utilizing the Sahara and Firehose
emergency download protocols.

Key capabilities include:
- Sahara protocol handshake, memory dumping, and PBL retrieval
- Sahara V3 extended chip identification (MSM_ID, OEM_ID, MODEL_ID, PKHash)
- Firehose XML/raw command execution, partition reading and writing (GPT/LUN)
- Automated loader detection via embedded Qualcomm programmer database
- Memory dumping (eMMC, UFS, NAND, SPI NOR), peek/poke, and QFPROM fuse readout
- UFS provisioning, partition slot switching (Slot A/B), and partition erasing
- Diagnostic toolsuite including qc_diag, fhloaderparse, and sierrakeygen

%prep
%autosetup -p1 -n %{name}-%{version}

# Remove bundled Windows binaries, DLLs, and scripts
rm -f fastpwn.exe edl.bat install_edl_win10_win11.ps1
rm -rf edlclient/Windows Drivers/Windows

# Remove host-incompatible precompiled binaries
rm -f fastpwn

# Remove any VCS metadata from submodules
rm -rf Loaders/.git Loaders/.gitignore

# Fix pyproject.toml requirements for standard Fedora setuptools build
sed -i 's/"wheel"//' pyproject.toml
sed -i 's/, *\]/\]/' pyproject.toml
sed -i 's/requests>=2.34.2/requests>=2.30.0/' pyproject.toml
sed -i 's/paramiko>=4.0.0,<5/paramiko>=3.5.0/' pyproject.toml

%build
%pyproject_wheel

%install
%pyproject_install

# Remove force-included top-level files from site-packages if present
rm -f %{buildroot}%{python3_sitelib}/LICENSE
rm -f %{buildroot}%{python3_sitelib}/README.md
rm -rf %{buildroot}%{python3_sitelib}/Example
rm -rf %{buildroot}%{python3_sitelib}/edlclient/Windows
rm -rf %{buildroot}%{python3_sitelib}/Loaders/.git*

# Ensure files in Loaders are non-executable data payloads
find %{buildroot}%{python3_sitelib}/Loaders -type f -exec chmod 0644 {} +
find %{buildroot}%{python3_sitelib}/Loaders -type d -exec chmod 0755 {} +

# Install convenience symlinks for command-line tools
ln -s edl %{buildroot}%{_bindir}/edl.py
ln -s qc_diag %{buildroot}%{_bindir}/qc_diag.py
ln -s sierrakeygen %{buildroot}%{_bindir}/sierrakeygen.py
ln -s boottodwnload %{buildroot}%{_bindir}/boottodwnload.py
ln -s enableadb %{buildroot}%{_bindir}/enableadb.py
ln -s fhloaderparse %{buildroot}%{_bindir}/fhloaderparse.py
ln -s beagle_to_loader %{buildroot}%{_bindir}/beagle_to_loader.py

# Install standalone helper scripts
install -D -p -m 0755 ubidump %{buildroot}%{_bindir}/ubidump
install -D -p -m 0755 qc_nand_extract.py %{buildroot}%{_bindir}/qc_nand_extract.py

# Install udev rules and kernel module blacklist
install -D -p -m 0644 Drivers/51-edl.rules %{buildroot}%{_udevrulesdir}/51-edl.rules
install -D -p -m 0644 Drivers/50-android.rules %{buildroot}%{_udevrulesdir}/50-android-edl.rules
install -D -p -m 0644 Drivers/blacklist-qcserial.conf %{buildroot}%{_modprobedir}/blacklist-qcserial.conf

%check
test -x %{buildroot}%{_bindir}/edl
test -x %{buildroot}%{_bindir}/edl.py
test -x %{buildroot}%{_bindir}/qc_diag
test -x %{buildroot}%{_bindir}/ubidump
test -f %{buildroot}%{_udevrulesdir}/51-edl.rules
test -f %{buildroot}%{_modprobedir}/blacklist-qcserial.conf
PYTHONPATH=%{buildroot}%{python3_sitelib} %{python3} -c "import edlclient; print('edlclient import test passed')"

%files
%license LICENSE
%doc README.md API_README.md sierrakeygen_README.md Example
%{_bindir}/edl
%{_bindir}/edl.py
%{_bindir}/qc_diag
%{_bindir}/qc_diag.py
%{_bindir}/sierrakeygen
%{_bindir}/sierrakeygen.py
%{_bindir}/boottodwnload
%{_bindir}/boottodwnload.py
%{_bindir}/enableadb
%{_bindir}/enableadb.py
%{_bindir}/fhloaderparse
%{_bindir}/fhloaderparse.py
%{_bindir}/beagle_to_loader
%{_bindir}/beagle_to_loader.py
%{_bindir}/ubidump
%{_bindir}/qc_nand_extract.py
%{python3_sitelib}/edlclient
%{python3_sitelib}/edlclient-%{version}.dist-info
%{python3_sitelib}/Loaders
%{_udevrulesdir}/51-edl.rules
%{_udevrulesdir}/50-android-edl.rules
%{_modprobedir}/blacklist-qcserial.conf

%changelog
* Fri Oct 02 2026 akbar_npj <akbar.npj@protonmail.com> - 3.62-1
- Initial RPM package for Fedora Asahi Remix
