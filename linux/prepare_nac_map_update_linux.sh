#!/usr/bin/env bash
#
# ============================================================================
#  PSA/Stellantis NAC Wave 4 Map Update — USB Preparation Script (Linux)
# ============================================================================
#
#  Vehicle:   Any PSA/Stellantis with NAC Wave 4 infotainment
#  Target:    map-eur 17.0.0-r0 (latest European cartography for NAC Wave 4)
#
#  NOTE: Map updates do NOT require a license file or UIN.
#  NOTE: Install the firmware update (44.07.33.32) BEFORE this map update.
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
#    1. Insert a USB drive (min 32 GB recommended, will be formatted FAT32)
#    2. Run: bash prepare_nac_map_update_linux.sh
#    3. Follow the prompts
#
#  If you already downloaded the .tar file:
#    bash prepare_nac_map_update_linux.sh --tar /path/to/map.tar
#
# ============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
MAP_VERSION="17.0.0-r0"
UPDATE_ID="002315011725520285"

# Download URL (TomTom CDN — this is the official source)
MAP_URL="https://download-cde.tomtom.com/OEM/PSA/MAP/PSA_map-eur_17.0.0-r0-NAC_EUR_WAVE4.tar"
MAP_FILENAME="PSA_map-eur_17.0.0-r0-NAC_EUR_WAVE4.tar"

# Expected size
EXPECTED_SIZE=20403312640

# Fallback URL (older TomTom domain)
FALLBACK_URLS=(
    "http://download.tomtom.com/OEM/PSA/MAP/PSA_map-eur_17.0.0-r0-NAC_EUR_WAVE4.tar"
)

# Volume label used for the formatted USB drive
VOLUME_LABEL="NAC_MAP"

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

# /dev/sdb -> /dev/sdb1 ; /dev/nvme0n1 -> /dev/nvme0n1p1 ; /dev/mmcblk0 -> /dev/mmcblk0p1
partition_for() {
    local dev="$1"
    if [[ "$dev" =~ [0-9]$ ]]; then
        echo "${dev}p1"
    else
        echo "${dev}1"
    fi
}

# Run a command as root (via sudo if not already root).
as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
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

# ── Prerequisite check ─────────────────────────────────────────────────────
check_firmware_prerequisite() {
    header "Firmware Prerequisite Check"

    echo "  This map update (17.0.0-r0) requires NAC Wave 4 firmware."
    echo "  Compatible firmware versions: 42.x or 44.x (Wave 4)"
    echo ""
    echo "  If you're not sure, check on the NAC screen:"
    echo "    Settings > System info > System version"
    echo ""

    echo "  What firmware version is currently installed?"
    echo "    1) 44.07.33.32 or newer  (latest Wave 4 — ideal)"
    echo "    2) 44.xx.xx.xx           (older Wave 4 — should work)"
    echo "    3) 42.xx.xx.xx           (early Wave 4 — should work)"
    echo "    4) 31.xx.xx.xx or older  (Wave 3 or older — won't work!)"
    echo "    5) I'm not sure / skip this check"
    echo ""
    read -rp "Select [1-5]: " fw_choice

    case "$fw_choice" in
        1|2|3|5)
            if [[ "$fw_choice" == "5" ]]; then
                warn "Skipping check. If the map install fails, update firmware first."
            else
                success "Firmware is compatible."
            fi
            ;;
        4)
            error "Your firmware is too old for this map update."
            echo ""
            echo "  You need to install the NAC Wave 4 firmware first."
            echo "  Use the firmware update script: prepare_nac_update_linux.sh"
            exit 1
            ;;
        *)
            warn "Invalid choice. Proceeding anyway."
            ;;
    esac
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

    # Check drive size — map is ~19 GB, need at least ~21 GB capacity.
    local disk_size_bytes
    disk_size_bytes=$(lsblk -dnb -o SIZE "$DISK_DEV" 2>/dev/null | head -1 | xargs || echo "0")
    if [[ -n "$disk_size_bytes" ]] && (( disk_size_bytes > 0 && disk_size_bytes < 21474836480 )); then
        local disk_size_gb=$(( disk_size_bytes / 1073741824 ))
        error "Drive is only ${disk_size_gb} GB. The map update is ~19 GB."
        error "You need at least a 32 GB USB drive."
        exit 1
    fi

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

    info "Creating MBR partition table with one FAT32 partition..."
    as_root parted -s "$DISK_DEV" mklabel msdos
    as_root parted -s "$DISK_DEV" mkpart primary fat32 1MiB 100%
    as_root parted -s "$DISK_DEV" set 1 lba on

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

    USB_MOUNT=$(mktemp -d /tmp/nac_map.XXXXXX)
    info "Mounting ${PART_DEV} at ${USB_MOUNT}..."
    if ! as_root mount -o "uid=$(id -u),gid=$(id -g),flush" "$PART_DEV" "$USB_MOUNT"; then
        error "Failed to mount ${PART_DEV}."
        exit 1
    fi
    success "Mounted at: ${USB_MOUNT}"
}

# ── Download with auto-resume ─────────────────────────────────────────────
MAX_RETRIES=50
RETRY_DELAY_BASE=5
CURL_TIMEOUT=30
CURL_SPEED_LIMIT=1024
CURL_SPEED_TIME=60

download_with_resume() {
    local url="$1"
    local dest="$2"

    local attempt=0
    local delay=$RETRY_DELAY_BASE

    while (( attempt < MAX_RETRIES )); do
        (( attempt++ )) || true

        local curl_flags=(
            -L
            --fail
            --progress-bar
            --connect-timeout "$CURL_TIMEOUT"
            --speed-limit "$CURL_SPEED_LIMIT"
            --speed-time "$CURL_SPEED_TIME"
            -o "$dest"
        )

        if [[ -f "$dest" ]]; then
            local current_size
            current_size=$(get_file_size "$dest" 2>/dev/null || echo 0)
            if (( current_size > 0 )); then
                curl_flags+=( -C - )
                if (( attempt > 1 )); then
                    local current_mb=$(( current_size / 1048576 ))
                    local expected_mb=$(( EXPECTED_SIZE / 1048576 ))
                    info "Resuming from ${current_mb} / ${expected_mb} MB  (attempt ${attempt}/${MAX_RETRIES})..."
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
            if (( final_size > 5000000000 )); then
                return 0
            else
                warn "File looks too small (${final_size} bytes). Retrying..."
            fi
        fi

        local curl_exit=$?

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

download_map() {
    local tar_path="$1"

    header "Downloading European Map"
    info "Version:  map-eur ${MAP_VERSION}"
    info "Size:     ~19 GB (${EXPECTED_SIZE} bytes)"
    info "Source:   TomTom CDN"
    info "Download will auto-resume if the connection drops."
    echo ""

    if [[ -f "$tar_path" ]]; then
        local existing
        existing=$(get_file_size "$tar_path" 2>/dev/null || echo 0)
        if (( existing == EXPECTED_SIZE )); then
            success "File already fully downloaded (${EXPECTED_SIZE} bytes)."
            return 0
        elif (( existing > 0 )); then
            local existing_mb=$(( existing / 1048576 ))
            info "Found partial download: ${existing_mb} MB of ~19,460 MB"
            info "Will resume automatically."
        fi
    fi

    info "Downloading from TomTom CDN..."
    echo "  ${MAP_URL}"
    echo ""

    if download_with_resume "$MAP_URL" "$tar_path"; then
        success "Download complete."
        return 0
    fi

    warn "Primary URL exhausted retries. Trying fallback..."
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
    echo "    curl -L -C - -o '${tar_path}' '${MAP_URL}'"
    echo ""
    echo "  Or download from rui.saraiva's site:"
    echo "    https://sites.google.com/view/nac-rcc/system/nac/wave-4"
    echo ""
    echo "  Then re-run:  bash $0 --tar /path/to/downloaded.tar"
    exit 1
}

# ── Validate map file ─────────────────────────────────────────────────────
validate_map() {
    local tar_path="$1"

    header "Validating Map File"

    local actual_size
    actual_size=$(get_file_size "$tar_path")

    info "File size: ${actual_size} bytes"

    if [[ "$actual_size" -eq "$EXPECTED_SIZE" ]]; then
        success "Size matches expected (${EXPECTED_SIZE} bytes)."
    else
        warn "Size ${actual_size} doesn't match expected ${EXPECTED_SIZE}."
        warn "Could be a re-upload. Proceeding — check forums if install fails."
    fi

    info "Checking archive integrity (this may take a moment for 19 GB)..."
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

# ── Extract map to USB ─────────────────────────────────────────────────────
extract_to_usb() {
    local tar_path="$1"
    local dest="$2"

    header "Extracting Map to USB"

    info "Extracting ~19 GB archive. This will take quite a while..."
    info "(USB 2.0 write speeds can make this 15-30 min)"
    echo ""

    tar xf "$tar_path" -C "$dest" 2>&1 | grep -v "unknown extended header" || true

    if [[ -d "${dest}/SWL" ]]; then
        success "Extraction complete. SWL/ directory present."
        local update_dir
        update_dir=$(find "${dest}/SWL" -maxdepth 1 -type d -name "002*" | head -1)
        if [[ -n "$update_dir" ]]; then
            success "Map update directory: $(basename "$update_dir")"
        fi
    else
        error "SWL/ directory missing after extraction!"
        exit 1
    fi
}

# ── Summary ────────────────────────────────────────────────────────────────
print_summary() {
    local dest="$1"

    header "USB Drive Ready — Map Update!"

    echo -e "${BOLD}USB contents:${NC}"
    find "$dest" -maxdepth 3 -type d ! -name ".*" \
        | head -20 \
        | sed "s|${dest}|USB:|"
    echo ""

    echo -e "  ${GREEN}✓${NC} No license file needed for map updates"
    echo ""

    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║              MAP INSTALLATION INSTRUCTIONS                   ║${NC}"
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}PREREQUISITE: Firmware must be 44.07.33.32 or newer!${NC}        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  (Run the firmware update script first if not done yet)       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  1. Start the car (engine on or READY mode for hybrid)        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  2. Insert USB drive                                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  3. System detects the map update automatically               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     You can choose which countries to install                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  4. Installation takes 45-90 minutes (19 GB via USB 2.0)      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     ${RED}Keep the engine running the entire time!${NC}                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     A long drive is ideal — install while driving.             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  5. System reboots when done — navigation is then available   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Important notes:${NC}"
    echo "  • All existing maps are deleted before new ones install."
    echo "    If you want to keep specific countries, re-select them during install."
    echo "  • No progress bar is shown — this is normal. Just let it run."
    echo "  • If it fails, try a different USB drive (USB 3.0 stick recommended)."
    echo ""
}

# ── Cleanup / unmount ──────────────────────────────────────────────────────
finalize_usb() {
    info "Flushing writes to disk (this can take a while for 19 GB)..."
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
    echo -e "${BOLD}${CYAN}  NAC Wave 4 Map Update — USB Prep (Linux)${NC}"
    echo -e "${BOLD}${CYAN}  Target: map-eur ${MAP_VERSION}${NC}"
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
            --skip-format)
                skip_format=true
                shift
                ;;
            --help|-h)
                echo "Usage: bash $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --tar FILE       Use a pre-downloaded .tar map file"
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
    check_firmware_prerequisite
    select_usb_drive

    if [[ "$skip_format" == false ]]; then
        format_usb
    else
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
        tar_file="/tmp/${MAP_FILENAME}"
        download_map "$tar_file"
    else
        if [[ ! -f "$tar_file" ]]; then
            error "File not found: ${tar_file}"
            exit 1
        fi
        info "Using provided file: ${tar_file}"
    fi

    validate_map "$tar_file"
    extract_to_usb "$tar_file" "$USB_MOUNT"

    print_summary "$USB_MOUNT"
    finalize_usb

    success "Done!"
    echo ""
}

main "$@"
