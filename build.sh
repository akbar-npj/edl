#!/usr/bin/env bash
# ==============================================================================
# EDL (edlclient) Automated RPM Build & Verification Script
# ==============================================================================
# Automates the complete RPM compilation pipeline for Fedora / RHEL / Asahi Remix:
# 1. Validates build dependencies (rpmbuild, python3, git, tar)
# 2. Ensures the Loaders submodule is initialized and up to date
# 3. Creates clean source tarball in rpmbuild SOURCES
# 4. Stages edl.spec
# 5. Compiles binary (noarch) and source (SRPM) packages
# 6. Runs package integrity and dnf dependency resolution tests
# ==============================================================================

set -euo pipefail

# Text formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m"

log_info()    { echo -e "${BLUE}${BOLD}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}${BOLD}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}${BOLD}[ERROR]${NC} $*" >&2; }

# Determine repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_FILE="${SCRIPT_DIR}/edl.spec"

# Configuration defaults
RPMBUILD_DIR="${HOME}/rpmbuild"
DO_TEST=true
DO_INSTALL=false
DO_CLEAN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    -h, --help             Show this help message and exit
    -t, --test             Run package verification tests (default: enabled)
    --no-test              Skip package verification tests
    -i, --install          Install the built RPM package upon successful build
    -c, --clean            Clean rpmbuild BUILD/BUILDROOT dirs before building
    --rpmbuild-dir DIR     Custom rpmbuild workspace directory (default: ~/rpmbuild)

Example:
    ./build.sh             # Build and verify RPM package
    ./build.sh --install   # Build, verify, and prompt to install via dnf
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -t|--test)
            DO_TEST=true
            shift
            ;;
        --no-test)
            DO_TEST=false
            shift
            ;;
        -i|--install)
            DO_INSTALL=true
            shift
            ;;
        -c|--clean)
            DO_CLEAN=true
            shift
            ;;
        --rpmbuild-dir)
            RPMBUILD_DIR="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}   EDL (edlclient) Automated RPM Compilation Tool     ${NC}"
echo -e "${BOLD}======================================================${NC}"

# 1. Check prerequisites
log_info "Checking build prerequisites..."
MISSING_TOOLS=()
for tool in rpmbuild python3 git tar; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    log_error "Missing required build tools: ${MISSING_TOOLS[*]}"
    log_error "Install them using:"
    log_error "  sudo dnf install -y rpm-build python3 python3-devel python3-pip python3-setuptools git tar"
    exit 1
fi
log_success "All required build tools found."

# 2. Validate spec file
if [[ ! -f "$SPEC_FILE" ]]; then
    log_error "Spec file not found at: $SPEC_FILE"
    exit 1
fi

PKG_NAME=$(grep -E '^Name:' "$SPEC_FILE" | awk '{print $2}')
PKG_VERSION=$(grep -E '^Version:' "$SPEC_FILE" | awk '{print $2}')
log_info "Package: ${PKG_NAME} (Version: ${PKG_VERSION})"

# 3. Check and update git submodules (Loaders)
log_info "Verifying Loaders submodule..."
if [[ ! -d "${SCRIPT_DIR}/Loaders" ]] || [[ -z "$(ls -A "${SCRIPT_DIR}/Loaders" 2>/dev/null)" ]] || [[ ! -d "${SCRIPT_DIR}/Loaders/qualcomm" ]]; then
    log_warn "Loaders submodule is uninitialized or empty. Initializing..."
    git -C "$SCRIPT_DIR" submodule update --init --recursive Loaders
    log_success "Loaders submodule initialized."
else
    log_success "Loaders submodule is present."
fi

# 4. Prepare rpmbuild directory structure
log_info "Preparing rpmbuild workspace at: ${RPMBUILD_DIR}"
mkdir -p "${RPMBUILD_DIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

if [[ "$DO_CLEAN" == true ]]; then
    log_info "Cleaning previous build roots..."
    rm -rf "${RPMBUILD_DIR}/BUILD/${PKG_NAME}-${PKG_VERSION}"*
    rm -rf "${RPMBUILD_DIR}/BUILDROOT/${PKG_NAME}-${PKG_VERSION}"*
fi

# 5. Create source tarball
TARBALL_NAME="${PKG_NAME}-${PKG_VERSION}.tar.gz"
TARGET_TARBALL="${RPMBUILD_DIR}/SOURCES/${TARBALL_NAME}"

log_info "Generating source archive: ${TARGET_TARBALL}..."
tar -C "$SCRIPT_DIR" \
    --exclude-vcs \
    --exclude="*.pyc" \
    --exclude="__pycache__" \
    --exclude="fastpwn" \
    --exclude="fastpwn.exe" \
    --exclude="edlclient.egg-info" \
    --exclude="build" \
    --exclude="dist" \
    --exclude="*.whl" \
    --transform "s,^\./,${PKG_NAME}-${PKG_VERSION}/,S" \
    --transform "s,^\.$,${PKG_NAME}-${PKG_VERSION},S" \
    -czf "$TARGET_TARBALL" .

TARBALL_SIZE=$(du -h "$TARGET_TARBALL" | awk '{print $1}')
log_success "Source archive generated (${TARBALL_SIZE})."

# 6. Stage spec file
log_info "Staging spec file to ${RPMBUILD_DIR}/SPECS/${PKG_NAME}.spec..."
cp -f "$SPEC_FILE" "${RPMBUILD_DIR}/SPECS/${PKG_NAME}.spec"

# 7. Compile RPM with rpmbuild
log_info "Executing rpmbuild (building binary and source packages)..."
rpmbuild --define "_topdir ${RPMBUILD_DIR}" -ba "${RPMBUILD_DIR}/SPECS/${PKG_NAME}.spec"
log_success "RPM compilation completed successfully!"

# 8. Locate generated packages
BINARY_RPM=$(find "${RPMBUILD_DIR}/RPMS" -type f -name "${PKG_NAME}-${PKG_VERSION}-*.rpm" ! -name "*.src.rpm" | head -n 1)
SOURCE_RPM=$(find "${RPMBUILD_DIR}/SRPMS" -type f -name "${PKG_NAME}-${PKG_VERSION}-*.src.rpm" | head -n 1)

if [[ -z "$BINARY_RPM" || ! -f "$BINARY_RPM" ]]; then
    log_error "Binary RPM was not found after compilation."
    exit 1
fi

BINARY_SIZE=$(du -h "$BINARY_RPM" | awk '{print $1}')
SOURCE_SIZE=$(du -h "$SOURCE_RPM" | awk '{print $1}')

echo ""
echo -e "${GREEN}${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD}                BUILD ARTIFACTS CREATED               ${NC}"
echo -e "${GREEN}${BOLD}======================================================${NC}"
echo -e "  ${BOLD}Binary RPM:${NC}  ${BINARY_RPM} (${BINARY_SIZE})"
echo -e "  ${BOLD}Source SRPM:${NC} ${SOURCE_RPM} (${SOURCE_SIZE})"
echo -e "${GREEN}${BOLD}======================================================${NC}"

# 9. Verification & testing
if [[ "$DO_TEST" == true ]]; then
    echo ""
    log_info "Running verification tests on generated package..."
    
    # Check package headers
    log_info "Querying RPM metadata..."
    rpm -qip "$BINARY_RPM" | grep -E "(Name|Version|Release|Architecture|Size|License|Summary)"
    
    # Check provides
    log_info "Verifying capabilities provided by package..."
    rpm -qp --provides "$BINARY_RPM" | sed 's/^/  [Provides] /'
    
    # Check requires
    log_info "Verifying package dependencies..."
    rpm -qp --requires "$BINARY_RPM" | head -n 10 | sed 's/^/  [Requires] /'
    
    # Verify key executables and rules are present
    log_info "Checking key packaged files..."
    RPM_FILE_LIST=$(rpm -qlp "$BINARY_RPM")
    for req_file in "/usr/bin/edl" "/usr/bin/edl.py" "/usr/bin/qc_diag" "/usr/lib/udev/rules.d/51-edl.rules" "/usr/lib/modprobe.d/blacklist-qcserial.conf"; do
        if echo "$RPM_FILE_LIST" | grep -F -x "$req_file" >/dev/null; then
            echo -e "  ${GREEN}✓${NC} Found $req_file"
        else
            log_error "Missing expected file in RPM: $req_file"
            exit 1
        fi
    done
    
    # Test dependency resolution using dnf (dry-run)
    if command -v dnf &>/dev/null; then
        log_info "Testing dnf dependency resolution (dry-run)..."
        DNF_OUT=$(dnf --assumeno install "$BINARY_RPM" 2>&1 || true)
        if echo "$DNF_OUT" | grep -q "Transaction Summary"; then
            log_success "All package dependencies successfully resolved by dnf!"
        else
            log_warn "dnf dependency dry-run did not produce a transaction summary."
        fi
    fi
    
    log_success "Package integrity and verification tests PASSED!"
fi

# 10. Optional Installation
if [[ "$DO_INSTALL" == true ]]; then
    echo ""
    log_info "Installing ${BINARY_RPM} via sudo dnf..."
    sudo dnf install -y "$BINARY_RPM"
    sudo udevadm control --reload-rules && sudo udevadm trigger
    sudo depmod -a
    log_success "Installation complete! Try running: edl --help"
else
    echo ""
    log_info "To install the package manually, run:"
    echo -e "  ${BOLD}sudo dnf install ${BINARY_RPM}${NC}"
    echo -e "  ${BOLD}sudo udevadm control --reload-rules && sudo udevadm trigger${NC}"
    echo -e "  ${BOLD}sudo usermod -aG dialout,plugdev \$USER${NC}"
fi
