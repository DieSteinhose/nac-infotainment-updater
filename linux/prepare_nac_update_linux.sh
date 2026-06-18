#!/usr/bin/env bash
#
# ============================================================================
#  PSA/Stellantis NAC Wave 4 Firmware Update — USB Preparation Script (Linux)
# ============================================================================
#
#  Vehicle:   Any PSA/Stellantis with NAC Wave 4 infotainment
#  Target:    44.07.33.32_NAC-r0 (latest NAC Wave 4 firmware)
#
#  IMPORTANT: The Citroën/Peugeot/DS/Opel Update app downloads from CloudFront
#  which is INVALID since 4 Feb 2026. This script downloads from the working
#  majestic-web.mpsa.com server instead.
#
#  Prerequisites (install via your package manager):
#    Debian/Ubuntu:  sudo apt install curl tar dosfstools parted util-linux
#    Fedora:         sudo dnf install curl tar dosfstools parted util-linux
#    Arch:           sudo pacman -S curl tar dosfstools parted util-linux
#
#  Formatting and mounting the USB drive requires root, so this script uses
#  sudo for those steps. You will be prompted for your password.
#
#  Usage:
#    1. Insert a USB drive (any size, will be formatted FAT32)
#    2. Run: bash prepare_nac_update_linux.sh
#    3. Follow the prompts (you will need your NAC UIN — see below)
#
#  If you already downloaded the .tar file:
#    bash prepare_nac_update_linux.sh --tar /path/to/firmware.tar
#
#  How to find your UIN:
#    On the NAC screen: Settings > System info > System version
#    Choose "Export to USB" (insert any FAT32 USB first).
#    Two files are created: instkey_<UIN>.xml and packageslist_<UIN>.txt
#    The UIN is the 20 hex-character string in the filename.
#
# ============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
FIRMWARE_VERSION="44.07.33.32_NAC-r0"
UPDATE_ID="001315031692686757"

# UIN will be set interactively or via --uin flag
UIN=""

# The WORKING download URL (majestic-web, NOT CloudFront)
FIRMWARE_URL="https://majestic-web.mpsa.com/nas/eu/mjb00/PSA/mjbsu/PSA_ovip-int-firmware-version_44-07-33-32_NAC-r0_NAC_EUR_WAVE4.tar"
FIRMWARE_FILENAME="PSA_ovip-int-firmware-version_44-07-33-32_NAC-r0_NAC_EUR_WAVE4.tar"

# Expected size of the VALID firmware file
EXPECTED_SIZE=6312212480

# Fallback URL
FALLBACK_URLS=(
    "https://majestic-web.mpsa.com/nas/eu/mjb00/NAC_EU/ovip-int-firmware-version/PSA_ovip-int-firmware-version_44-07-33-32_NAC-r0_NAC_EUR_WAVE4.tar"
)

# Volume label used for the formatted USB drive
VOLUME_LABEL="NAC_UPDATE"

# License URL is constructed dynamically after UIN is provided

# These get filled in during USB selection / formatting
DISK_DEV=""      # whole-disk device, e.g. /dev/sdb
PART_DEV=""      # partition device, e.g. /dev/sdb1
USB_MOUNT=""     # mount point

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR ]${NC} $*"; }
header()  { echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

# Return the partition device for a whole-disk device.
# /dev/sdb -> /dev/sdb1 ; /dev/nvme0n1 -> /dev/nvme0n1p1 ; /dev/mmcblk0 -> /dev/mmcblk0p1
partition_for() {
    local dev="$1"
    if [[ "$dev" =~ [0-9]$ ]]; then
        echo "${dev}p1"
    else
        echo "${dev}1"
    fi
}

# ── Dependency check ───────────────────────────────────────────────────────
check_dependencies() {
    header "Checking Dependencies"

    local missing=()

    command -v curl     &>/dev/null || missing+=("curl")
    command -v tar      &>/dev/null || missing+=("tar")
    command -v stat     &>/dev/null || missing+=("coreutils (stat)")
    command -v lsblk    &>/dev/null || missing+=("util-linux (lsblk)")
    command -v parted   &>/dev/null || missing+=("parted")
    command -v mkfs.vfat &>/dev/null || missing+=("dosfstools (mkfs.vfat)")

    if ! command -v sudo &>/dev/null && [[ "$(id -u)" -ne 0 ]]; then
        error "Neither sudo nor root privileges available."
        error "Run this script as root, or install sudo."
        exit 1
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        echo ""
        echo "  Install them with your package manager, for example:"
        echo "    Debian/Ubuntu:  sudo apt install curl tar dosfstools parted util-linux"
        echo "    Fedora:         sudo dnf install curl tar dosfstools parted util-linux"
        echo "    Arch:           sudo pacman -S curl tar dosfstools parted util-linux"
        exit 1
    fi

    success "All dependencies satisfied."
}

# Run a command as root (via sudo if not already root).
as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ── UIN Prompt ─────────────────────────────────────────────────────────────
prompt_uin() {
    if [[ -n "$UIN" ]]; then
        info "UIN provided: ${UIN}"
    else
        header "NAC Unit Identification (UIN)"

        echo "  Your UIN is a 20-character hex string that identifies your NAC unit."
        echo ""
        echo "  How to find it:"
        echo "    1. Insert any FAT32-formatted USB into the car"
        echo "    2. On the NAC screen: Settings > System info > System version"
        echo "    3. Choose 'Export to USB' (or 'Export configuration')"
        echo "    4. Two files are created on the USB:"
        echo "       instkey_<UIN>.xml  and  packageslist_<UIN>.txt"
        echo "    5. The UIN is the 20-character hex string in those filenames"
        echo "       Example: 0D01071F79D4D1E3643C"
        echo ""

        read -rp "Enter your UIN (20 hex characters): " UIN
    fi

    # Validate: must be exactly 20 hex characters
    UIN=$(echo "$UIN" | tr '[:lower:]' '[:upper:]' | tr -d ' ')
    if [[ ! "$UIN" =~ ^[0-9A-F]{20}$ ]]; then
        error "Invalid UIN: '${UIN}'"
        error "Must be exactly 20 hexadecimal characters (0-9, A-F)."
        exit 1
    fi

    LICENSE_FILENAME="license_${UIN}_${UPDATE_ID}.key"
    LICENSE_URL="https://majestic-web.mpsa.com/mjf00-web/rest/LicenseDownload?mediaVersion=${UPDATE_ID}&uin=${UIN}"

    success "UIN: ${UIN}"
}

get_file_size() {
    local filepath="$1"
    stat -c%s "$filepath"
}

# ── USB Drive Selection ────────────────────────────────────────────────────
select_usb_drive() {
    header "USB Drive Selection"

    echo "Scanning for removable drives..."
    echo ""

    # Collect candidate removable/USB whole disks.
    local disks=()
    while IFS= read -r line; do
        local name type rm tran
        name=$(awk '{print $1}' <<<"$line")
        type=$(awk '{print $2}' <<<"$line")
        rm=$(awk '{print $3}'   <<<"$line")
        tran=$(awk '{print $4}'  <<<"$line")
        [[ "$type" == "disk" ]] || continue
        if [[ "$rm" == "1" || "$tran" == "usb" ]]; then
            disks+=("/dev/${name}")
        fi
    done < <(lsblk -dn -o NAME,TYPE,RM,TRAN)

    if [[ ${#disks[@]} -eq 0 ]]; then
        error "No removable USB drives detected."
        echo "  Make sure your USB drive is plugged in."
        echo "  If it still isn't found, list disks with:  lsblk -do NAME,SIZE,MODEL,TRAN,RM"
        exit 1
    fi

    # Show details for the candidates
    lsblk -o NAME,SIZE,MODEL,TRAN,RM,MOUNTPOINT "${disks[@]}"
    echo ""

    if [[ ${#disks[@]} -eq 1 ]]; then
        DISK_DEV="${disks[0]}"
        info "Only one removable drive found: ${DISK_DEV}"
    else
        echo "Multiple removable drives found:"
        local i=1
        for d in "${disks[@]}"; do
            local dname dsize
            dname=$(lsblk -dn -o MODEL "$d" 2>/dev/null | xargs || echo "unknown")
            dsize=$(lsblk -dn -o SIZE  "$d" 2>/dev/null | xargs || echo "unknown")
            echo "  $i) $d  —  ${dname:-unknown}  (${dsize})"
            ((i++))
        done
        echo ""
        read -rp "Select drive number: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#disks[@]} )); then
            DISK_DEV="${disks[$((choice-1))]}"
        else
            error "Invalid selection."
            exit 1
        fi
    fi

    PART_DEV=$(partition_for "$DISK_DEV")

    echo ""
    lsblk -o NAME,SIZE,MODEL,TRAN,RM,MOUNTPOINT "$DISK_DEV"
    echo ""

    warn "${BOLD}ALL DATA ON ${DISK_DEV} WILL BE ERASED!${NC}"
    echo ""
    read -rp "Type 'YES' to confirm: " confirm
    if [[ "$confirm" != "YES" ]]; then
        info "Aborted."
        exit 0
    fi
}

# Unmount every mounted partition of the selected disk.
unmount_all() {
    local dev="$1"
    local part
    while IFS= read -r part; do
        [[ -n "$part" ]] || continue
        if mountpoint -q "$part" 2>/dev/null || lsblk -no MOUNTPOINT "/dev/${part}" 2>/dev/null | grep -q .; then
            as_root umount "/dev/${part}" 2>/dev/null || true
        fi
    done < <(lsblk -ln -o NAME "$dev" | tail -n +2)
    # Best-effort blanket unmount as well
    for p in "${dev}"*; do
        [[ -b "$p" ]] || continue
        as_root umount "$p" 2>/dev/null || true
    done
}

# ── Format USB as FAT32 ───────────────────────────────────────────────────
format_usb() {
    header "Formatting USB Drive as FAT32"

    info "Unmounting any mounted partitions on ${DISK_DEV}..."
    unmount_all "$DISK_DEV"

    info "Wiping existing filesystem signatures..."
    as_root wipefs -a "$DISK_DEV" >/dev/null

    # Create an MBR (msdos) partition table with a single FAT32 partition.
    # The NAC requires an MBR partition table — not GPT.
    info "Creating MBR partition table with one FAT32 partition..."
    as_root parted -s "$DISK_DEV" mklabel msdos
    as_root parted -s "$DISK_DEV" mkpart primary fat32 1MiB 100%
    as_root parted -s "$DISK_DEV" set 1 lba on

    # Wait for the kernel to create the partition node.
    as_root partprobe "$DISK_DEV" 2>/dev/null || true
    command -v udevadm &>/dev/null && as_root udevadm settle 2>/dev/null || true

    local waited=0
    while [[ ! -b "$PART_DEV" ]] && (( waited < 10 )); do
        sleep 1
        ((waited++))
    done
    if [[ ! -b "$PART_DEV" ]]; then
        error "Partition ${PART_DEV} did not appear after formatting."
        error "Try replugging the drive and re-running with --skip-format."
        exit 1
    fi

    # Desktop environments (KDE/GNOME via udisks) auto-mount the new partition
    # as soon as it appears, which makes mkfs.vfat fail with "contains a
    # mounted filesystem". Unmount it (best-effort) before formatting.
    if command -v udisksctl &>/dev/null; then
        udisksctl unmount -b "$PART_DEV" 2>/dev/null || true
    fi
    as_root umount "$PART_DEV" 2>/dev/null || true

    info "Creating FAT32 filesystem (label: ${VOLUME_LABEL})..."
    as_root mkfs.vfat -F 32 -n "$VOLUME_LABEL" "$PART_DEV" >/dev/null

    success "Drive formatted as FAT32 (MBR)."

    mount_usb
}

# Mount PART_DEV so the current user can write to it without sudo.
mount_usb() {
    # Drop any auto-mount udisks may have created so we control the mount point.
    if command -v udisksctl &>/dev/null; then
        udisksctl unmount -b "$PART_DEV" 2>/dev/null || true
    fi
    as_root umount "$PART_DEV" 2>/dev/null || true

    USB_MOUNT=$(mktemp -d /tmp/nac_update.XXXXXX)
    info "Mounting ${PART_DEV} at ${USB_MOUNT}..."
    # uid/gid options make the FAT32 mount writable by the current user.
    if ! as_root mount -o "uid=$(id -u),gid=$(id -g),flush" "$PART_DEV" "$USB_MOUNT"; then
        error "Failed to mount ${PART_DEV}."
        exit 1
    fi
    success "Mounted at: ${USB_MOUNT}"
}

# ── Download firmware (with auto-resume) ───────────────────────────────────
MAX_RETRIES=50          # generous — a 5.9 GB file over a flaky link can drop many times
RETRY_DELAY_BASE=5      # seconds; doubles each consecutive failure, caps at 120s
CURL_TIMEOUT=30         # --connect-timeout
CURL_SPEED_LIMIT=1024   # abort if speed drops below this many bytes/sec ...
CURL_SPEED_TIME=60      # ... for this many seconds (stall detection)

download_with_resume() {
    # Download a single URL with automatic resume-on-failure.
    # Returns 0 on success, 1 if all retries exhausted.
    local url="$1"
    local dest="$2"

    local attempt=0
    local delay=$RETRY_DELAY_BASE

    while (( attempt < MAX_RETRIES )); do
        (( attempt++ )) || true

        local curl_flags=(
            -L                              # follow redirects
            --fail                          # fail on HTTP errors
            --progress-bar                  # show progress
            --connect-timeout "$CURL_TIMEOUT"
            --speed-limit "$CURL_SPEED_LIMIT"
            --speed-time "$CURL_SPEED_TIME"
            -o "$dest"
        )

        if [[ -f "$dest" ]]; then
            local current_size
            current_size=$(get_file_size "$dest" 2>/dev/null || echo 0)
            if (( current_size > 0 )); then
                curl_flags+=( -C - )        # auto-resume
                if (( attempt > 1 )); then
                    info "Resuming from $(( current_size / 1048576 )) MB  (attempt ${attempt}/${MAX_RETRIES})..."
                fi
            fi
        else
            if (( attempt > 1 )); then
                info "Retrying from scratch  (attempt ${attempt}/${MAX_RETRIES})..."
            fi
        fi

        if curl "${curl_flags[@]}" "$url" 2>&1; then
            local final_size
            final_size=$(get_file_size "$dest" 2>/dev/null || echo 0)
            if (( final_size > 1000000000 )); then  # at least ~1 GB
                return 0
            else
                warn "File looks too small (${final_size} bytes). Retrying..."
            fi
        fi

        local curl_exit=$?

        # If the server doesn't support range requests, curl -C - exits 33.
        if [[ $curl_exit -eq 33 ]]; then
            warn "Server rejected resume. Starting from the beginning..."
            rm -f "$dest"
            delay=$RETRY_DELAY_BASE
            continue
        fi

        warn "Download interrupted (curl exit ${curl_exit}). Waiting ${delay}s before retry..."
        sleep "$delay"

        delay=$(( delay * 2 ))
        (( delay > 120 )) && delay=120
    done

    return 1
}

download_firmware() {
    local tar_path="$1"

    header "Downloading Firmware"
    info "Version:  ${FIRMWARE_VERSION}"
    info "Size:     ~5.9 GB (${EXPECTED_SIZE} bytes)"
    info "Download will auto-resume if the connection drops."
    echo ""

    if [[ -f "$tar_path" ]]; then
        local existing
        existing=$(get_file_size "$tar_path" 2>/dev/null || echo 0)
        if (( existing == EXPECTED_SIZE )); then
            success "File already fully downloaded (${EXPECTED_SIZE} bytes)."
            return 0
        elif (( existing > 0 )); then
            info "Found partial download: $(( existing / 1048576 )) MB of ~5880 MB"
            info "Will resume automatically."
        fi
    fi

    info "Downloading from majestic-web.mpsa.com..."
    echo "  ${FIRMWARE_URL}"
    echo ""

    if download_with_resume "$FIRMWARE_URL" "$tar_path"; then
        success "Download complete."
        return 0
    fi

    warn "Primary URL exhausted retries. Trying fallback URL..."
    for url in "${FALLBACK_URLS[@]}"; do
        rm -f "$tar_path"
        info "Trying: $url"
        if download_with_resume "$url" "$tar_path"; then
            success "Download complete."
            return 0
        fi
    done

    error "All download URLs failed after ${MAX_RETRIES} retries each."
    echo ""
    echo "  Your partial download is kept at: ${tar_path}"
    echo "  You can resume manually with:"
    echo "    curl -L -C - -o '${tar_path}' '${FIRMWARE_URL}'"
    echo ""
    echo "  Or download from rui.saraiva's site:"
    echo "    https://sites.google.com/view/nac-rcc/system/nac/wave-4"
    echo ""
    echo "  Then re-run:  bash $0 --tar /path/to/downloaded.tar"
    exit 1
}

# ── Validate firmware ──────────────────────────────────────────────────────
validate_firmware() {
    local tar_path="$1"

    header "Validating Firmware File"

    local actual_size
    actual_size=$(get_file_size "$tar_path")

    info "File size: ${actual_size} bytes"

    if [[ "$actual_size" -eq "$EXPECTED_SIZE" ]]; then
        success "Size matches the known-good version (${EXPECTED_SIZE} bytes). This is the correct file."
    elif [[ "$actual_size" -eq 6312210432 ]]; then
        echo ""
        error "╔══════════════════════════════════════════════════════════╗"
        error "║  THIS IS THE BROKEN CLOUDFRONT FILE!                    ║"
        error "║  Size: 6,312,210,432 bytes (should be 6,312,212,480)    ║"
        error "║  This WILL fail with 'incompatible hardware'.           ║"
        error "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo "  You need the correct file from the majestic-web server."
        echo "  Re-run this script without --tar to download automatically,"
        echo "  or get it from: https://sites.google.com/view/nac-rcc/system/nac/wave-4"
        exit 1
    else
        warn "Size ${actual_size} doesn't match expected ${EXPECTED_SIZE}."
        warn "Could be a newer upload. Proceeding — but if it fails in the car,"
        warn "check rui.saraiva's site for the latest known-good file."
    fi

    info "Checking archive integrity..."
    if tar tf "$tar_path" &>/dev/null; then
        success "Archive is valid."
    else
        error "Archive appears corrupted. Re-download it."
        exit 1
    fi

    # Read only the first entries. `grep -q` closes the pipe on the first match,
    # which sends SIGPIPE to tar; under `set -o pipefail` that would otherwise
    # make the whole pipeline look failed. Capturing into a variable avoids it.
    local listing
    listing=$(tar tf "$tar_path" 2>/dev/null | head -100 || true)
    if grep -q "SWL/" <<<"$listing"; then
        success "Contains SWL/ directory structure."
    else
        error "No SWL/ directory found. Wrong file?"
        exit 1
    fi
}

# ── License file ───────────────────────────────────────────────────────────
prepare_license() {
    local dest_dir="$1"

    header "Preparing License File"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local license_found=""

    for search_path in \
        "${script_dir}/${LICENSE_FILENAME}" \
        "./${LICENSE_FILENAME}" \
        "$HOME/${LICENSE_FILENAME}" \
        "$HOME/Downloads/${LICENSE_FILENAME}" \
        "$HOME/Desktop/${LICENSE_FILENAME}" \
        ; do
        if [[ -f "$search_path" ]]; then
            license_found="$search_path"
            break
        fi
    done

    if [[ -n "$license_found" ]]; then
        info "Found license: ${license_found}"
    else
        info "License not found locally. Downloading from Stellantis server..."
        local tmp_license="/tmp/${LICENSE_FILENAME}"
        if curl -L --fail -s -o "$tmp_license" "$LICENSE_URL" 2>/dev/null; then
            if head -c 50 "$tmp_license" | grep -q '"errorCode"\|"file":null'; then
                warn "Server returned an error. License not available for download."
                warn "Proceeding WITHOUT license — the car must have internet access!"
                rm -f "$tmp_license"
                return 1
            fi
            license_found="$tmp_license"
            success "License downloaded."
        else
            warn "Download failed."
            warn "Proceeding WITHOUT license — the car must have internet access!"
            return 1
        fi
    fi

    mkdir -p "${dest_dir}/license"
    cp "$license_found" "${dest_dir}/license/${LICENSE_FILENAME}"
    success "License placed at: USB:/license/${LICENSE_FILENAME}"
    return 0
}

# ── Extract firmware ───────────────────────────────────────────────────────
extract_to_usb() {
    local tar_path="$1"
    local dest="$2"

    header "Extracting Firmware to USB"

    info "Extracting ~5.9 GB archive. This takes several minutes..."
    info "(Ignore any 'Ignoring unknown extended header' warnings)"
    echo ""

    tar xf "$tar_path" -C "$dest" 2>&1 | grep -v "unknown extended header" || true

    if [[ -d "${dest}/SWL" ]]; then
        success "Extraction complete. SWL/ directory present."
        local update_dir
        update_dir=$(find "${dest}/SWL" -maxdepth 1 -type d -name "001*" | head -1)
        if [[ -n "$update_dir" ]]; then
            success "Update directory: $(basename "$update_dir")"
        fi
    else
        error "SWL/ directory missing after extraction!"
        exit 1
    fi
}

# ── Summary ────────────────────────────────────────────────────────────────
print_summary() {
    local dest="$1"
    local has_license="$2"

    header "USB Drive Ready!"

    echo -e "${BOLD}USB contents:${NC}"
    find "$dest" -maxdepth 3 -type d ! -name ".*" \
        | head -20 \
        | sed "s|${dest}|USB:|"
    echo ""

    if [[ -f "${dest}/license/${LICENSE_FILENAME}" ]]; then
        echo -e "  ${GREEN}✓${NC} License file present"
    else
        echo -e "  ${YELLOW}⚠${NC} No license file — car MUST have internet!"
    fi
    echo ""

    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║              INSTALLATION INSTRUCTIONS                       ║${NC}"
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  1. Start the car (engine on or READY mode for hybrid)        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    if [[ "$has_license" != "true" ]]; then
    echo -e "${CYAN}║${NC}  2. ${YELLOW}Connect car to WiFi or phone hotspot FIRST${NC}               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     Settings > Connectivity > WiFi                            ${CYAN}║${NC}"
    else
    echo -e "${CYAN}║${NC}  2. Optionally connect to WiFi (recommended as backup)        ${CYAN}║${NC}"
    fi
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  3. Insert USB drive                                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  4. System should detect the update automatically             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     If not: Settings > System info > System update             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  5. Installation takes 30-45 minutes                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     ${RED}DO NOT turn off the engine during install!${NC}                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  6. System reboots automatically when done                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}If it still says 'incompatible hardware':${NC}"
    echo "  • Hold the NAC power/volume button 10+ seconds to reset it"
    echo "  • Connect car to WiFi/hotspot before inserting USB"
    echo "  • Try a different USB drive (some units are picky)"
    echo "  • Try a BSI reset: disconnect 12V battery 15 min, reconnect"
    echo ""
    echo "  Community help:"
    echo "    https://www.mittns.de/"
    echo "    https://www.peugeotforums.com/"
    echo "    https://frenchcarforum.co.uk/"
    echo ""
}

# ── Cleanup / unmount ──────────────────────────────────────────────────────
finalize_usb() {
    info "Flushing writes to disk (this can take a moment)..."
    sync
    if [[ -n "$USB_MOUNT" ]] && mountpoint -q "$USB_MOUNT" 2>/dev/null; then
        as_root umount "$USB_MOUNT" && rmdir "$USB_MOUNT" 2>/dev/null || true
        success "USB safely unmounted. You can now remove the drive."
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}${CYAN}============================================================${NC}"
    echo -e "${BOLD}${CYAN}  NAC Wave 4 Firmware Update — USB Prep (Linux)${NC}"
    echo -e "${BOLD}${CYAN}  Target: ${FIRMWARE_VERSION}${NC}"
    echo -e "${BOLD}${CYAN}============================================================${NC}"
    echo ""

    local tar_file=""
    local skip_format=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tar)
                tar_file="$2"
                shift 2
                ;;
            --uin)
                UIN="$2"
                shift 2
                ;;
            --skip-format)
                skip_format=true
                shift
                ;;
            --help|-h)
                echo "Usage: bash $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --uin UIN        Your NAC unit's 20-char hex ID (prompted if omitted)"
                echo "  --tar FILE       Use a pre-downloaded .tar firmware file"
                echo "  --skip-format    Don't format USB (must already be FAT32 MBR)"
                echo "  --help           Show this help"
                echo ""
                echo "Prerequisites (Debian/Ubuntu):"
                echo "  sudo apt install curl tar dosfstools parted util-linux"
                echo ""
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    check_dependencies
    prompt_uin
    select_usb_drive

    if [[ "$skip_format" == false ]]; then
        format_usb
    else
        # Use the existing FAT32 partition. Find or create a mount point.
        local existing_mount
        existing_mount=$(lsblk -no MOUNTPOINT "$PART_DEV" 2>/dev/null | head -1 | xargs || echo "")
        if [[ -n "$existing_mount" ]]; then
            USB_MOUNT="$existing_mount"
            info "Using existing mount: ${USB_MOUNT}"
        else
            mount_usb
        fi

        local fstype
        fstype=$(lsblk -no FSTYPE "$PART_DEV" 2>/dev/null | head -1 | xargs || echo "")
        if [[ "$fstype" != "vfat" ]]; then
            warn "Partition ${PART_DEV} is '${fstype:-unknown}', not vfat (FAT32)."
            warn "The NAC requires FAT32. Consider removing --skip-format."
        fi
    fi

    if [[ -z "$tar_file" ]]; then
        tar_file="/tmp/${FIRMWARE_FILENAME}"
        download_firmware "$tar_file"
    else
        if [[ ! -f "$tar_file" ]]; then
            error "File not found: ${tar_file}"
            exit 1
        fi
        info "Using provided file: ${tar_file}"
    fi

    validate_firmware "$tar_file"
    extract_to_usb "$tar_file" "$USB_MOUNT"

    local has_license="false"
    if prepare_license "$USB_MOUNT"; then
        has_license="true"
    fi

    print_summary "$USB_MOUNT" "$has_license"
    finalize_usb

    success "Done!"
    echo ""
}

main "$@"
