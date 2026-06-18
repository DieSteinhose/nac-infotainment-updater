# NAC Wave 4 Update Scripts for Linux

Two shell scripts to prepare USB drives for updating the infotainment system (Continental NAC Wave 4) found in Peugeot, Citroën, DS, Opel/Vauxhall vehicles from ~2017 onwards.

These scripts exist because the official Citroën/Peugeot/DS/Opel Update apps frequently fail with a **"Version not compatible with hardware"** error — often caused by broken files on Stellantis's CDN servers, expired certificates, or missing license files. These scripts bypass those issues by downloading from known-good sources, automatically resuming interrupted downloads, and correctly structuring the USB drive.

They are a direct port of the macOS scripts, using native Linux tools (`lsblk`, `parted`, `mkfs.vfat`, `mount`) instead of macOS's `diskutil`.

---

## What's Included

| Script | What it does |
|---|---|
| `prepare_nac_update_linux.sh` | Downloads and prepares firmware **44.07.33.32_NAC-r0** (latest NAC Wave 4 firmware, ~5.9 GB) |
| `prepare_nac_map_update_linux.sh` | Downloads and prepares European map **17.0.0-r0** (latest cartography, ~19 GB) |

**Always install firmware first, then maps.** The map update requires Wave 4 firmware.

---

## Compatible Vehicles

Any PSA/Stellantis vehicle with a Continental NAC Wave 4 infotainment system, including but not limited to:

- Citroën C5 Aircross, C4, C3 Aircross, Berlingo, C5 X
- Peugeot 208, 2008, 308, 3008, 508, 5008, Rifter, Partner
- DS 3, DS 4, DS 7, DS 9
- Opel/Vauxhall Corsa, Mokka, Grandland, Combo
- Toyota Proace (PSA-based models)

To confirm you have a NAC Wave 4, check the firmware version on your screen (Settings → System info). If it starts with **42.xx** or **44.xx**, you have Wave 4. Versions starting with **31.xx** are Wave 3 (some can be upgraded), and **21.xx** are Wave 2 (not compatible with these scripts).

---

## Prerequisites

You need a handful of standard command-line tools. They are available in every major distribution's repositories:

| Tool | Package | Used for |
|---|---|---|
| `curl` | `curl` | Downloading firmware/maps with resume |
| `tar` | `tar` | Extracting the archive |
| `stat` | `coreutils` | Reliable byte-count file size checks |
| `lsblk` | `util-linux` | Detecting and inspecting USB drives |
| `parted`, `partprobe` | `parted` | Creating the MBR partition table |
| `mkfs.vfat` | `dosfstools` | Creating the FAT32 filesystem |

Install everything in one go:

```bash
# Debian / Ubuntu / Mint / Pop!_OS
sudo apt install curl tar dosfstools parted util-linux

# Fedora / RHEL / CentOS
sudo dnf install curl tar dosfstools parted util-linux

# Arch / Manjaro / EndeavourOS
sudo pacman -S curl tar dosfstools parted util-linux

# openSUSE
sudo zypper install curl tar dosfstools parted util-linux
```

**Root access:** formatting and mounting a USB drive requires root. The scripts call `sudo` only for those specific steps (partitioning, `mkfs`, mounting/unmounting), so you'll be prompted for your password once. The large download and extraction run as your normal user.

---

## Before You Start

You will need:

- A **USB drive** — any size for firmware (8 GB+), at least **32 GB for maps**
- Your **NAC UIN** — a 20-character code that identifies your specific head unit (firmware only)

### How to Find Your UIN

1. Format any USB drive as FAT32
2. Insert it into the car's USB port
3. On the NAC touchscreen, go to: **Settings → System info → System version**
4. Choose **"Export to USB"** (sometimes called "Export configuration")
5. Remove the USB and plug it into your computer
6. Two files will be on the drive:
   - `instkey_XXXXXXXXXXXXXXXXXXXX.xml`
   - `packageslist_XXXXXXXXXXXXXXXXXXXX.txt`
7. The `XXXXXXXXXXXXXXXXXXXX` part (20 characters) is your UIN

Example UIN: `0D01071F79D4D1E3643C`

---

## Usage

### Firmware Update

```bash
bash prepare_nac_update_linux.sh
```

The script will:
1. Ask for your UIN
2. Show detected removable drives and let you pick one
3. Format it as FAT32 with an MBR partition table (erasing everything on it)
4. Download the firmware (~5.9 GB) with automatic resume if the connection drops
5. Verify the file is the correct, working version (not the broken CloudFront one)
6. Extract it to the USB drive
7. Download and place your license file
8. Flush and safely unmount the drive

**Options:**

```bash
bash prepare_nac_update_linux.sh --uin 0D01071F79D4D1E3643C     # skip the UIN prompt
bash prepare_nac_update_linux.sh --tar ~/Downloads/firmware.tar # use a file you already downloaded
bash prepare_nac_update_linux.sh --skip-format                  # don't reformat the USB
```

### Map Update

```bash
bash prepare_nac_map_update_linux.sh
```

Same flow, but for the European cartography (17.0.0-r0). This is a ~19 GB download. No UIN or license file is needed for map updates.

**Options:**

```bash
bash prepare_nac_map_update_linux.sh --tar ~/Downloads/maps.tar  # use a file you already downloaded
bash prepare_nac_map_update_linux.sh --skip-format               # don't reformat the USB
```

---

## Installing in the Car

### Firmware

1. Start the car — engine on, or press the Start button twice for READY mode (hybrid/EV)
2. **Recommended:** connect the car to WiFi or your phone's hotspot first (Settings → Connectivity → WiFi). This provides a backup path for license verification
3. Insert the USB drive
4. The system should detect the update automatically. If not: Settings → System info → System update
5. Installation takes **30–45 minutes**. **Do not turn off the engine**
6. The system reboots automatically when done

### Maps (after firmware is updated)

1. Start the car
2. Insert the USB drive
3. The system will let you choose which countries to install. Note: all existing maps are deleted first regardless of selection
4. Installation takes **45–90 minutes** (19 GB over USB 2.0). A long drive is ideal
5. There is no visible progress bar — this is normal

---

## Troubleshooting

### USB drive not detected

The scripts only list drives the kernel reports as removable or on the USB bus. List your block devices manually to confirm the device node:

```bash
lsblk -do NAME,SIZE,MODEL,TRAN,RM
```

If your drive shows up there but not in the script (for example, an SSD in a USB enclosure that reports `RM=0` and `TRAN` other than `usb`), double-check you have the right device before forcing it. You can format it manually as FAT32/MBR and then use `--skip-format`.

### Wrong device picked / safety

The scripts only offer removable/USB disks and require you to type `YES` before erasing. Always confirm the device node (e.g. `/dev/sdb`) and size match your USB stick — **the selected disk is wiped completely**. Internal disks are normally `/dev/sda` or `/dev/nvme0n1` and are excluded, but always check.

### "Version not compatible with hardware"

| Cause | Fix |
|---|---|
| You used the official Citroën/Peugeot Update app | The CloudFront file is broken since Feb 2026. Use this script instead — it downloads from the working server |
| License file missing or invalid | The script handles this, but make sure the car has WiFi as backup |
| NAC needs a reset | Hold the power/volume button on the NAC panel for 10+ seconds |
| USB drive issues | Try a different USB drive. Some NAC units are picky |

### "No media content on the USB memory stick"

- The USB must be **FAT32** formatted with an **MBR** partition table (the script handles this)
- The `SWL` folder must be in the root of the USB, not inside another folder

### Download keeps failing

The scripts automatically resume interrupted downloads with exponential backoff (up to 50 retries). If your connection is very unstable, the partial download is preserved at `/tmp/PSA_*.tar` — just re-run the script and it picks up where it left off.

You can also download manually with:

```bash
# Firmware (use this URL, NOT the CloudFront one):
curl -L -C - -o firmware.tar "https://majestic-web.mpsa.com/nas/eu/mjb00/PSA/mjbsu/PSA_ovip-int-firmware-version_44-07-33-32_NAC-r0_NAC_EUR_WAVE4.tar"

# Maps:
curl -L -C - -o maps.tar "https://download-cde.tomtom.com/OEM/PSA/MAP/PSA_map-eur_17.0.0-r0-NAC_EUR_WAVE4.tar"
```

Then pass them to the scripts with `--tar /path/to/file.tar`.

### BSI Reset (last resort)

If nothing works, try a BSI (Body Systems Interface) reset:

1. Turn the car off
2. Disconnect the 12V battery for 15 minutes
3. Reconnect the battery
4. Start the car and try the update again

---

## How It Differs from the macOS Scripts

The logic is identical — same download URLs, same size checks, same SWL structure. Only the platform-specific disk handling changes:

| Step | macOS | Linux |
|---|---|---|
| List drives | `diskutil list external physical` | `lsblk` (removable / USB transport) |
| File size | `gstat`/`stat -f%z` | `stat -c%s` |
| Partition + format | `diskutil eraseDisk FAT32 ... MBRFormat` | `parted` (msdos label) + `mkfs.vfat -F 32` |
| Mount | automatic at `/Volumes/...` | `mount` to a temp dir with `uid=`/`gid=` |
| Cleanup | strips `.DS_Store`, `._*`, Spotlight files | not needed (Linux doesn't create them) |

Because Linux doesn't write macOS metadata files (`.DS_Store`, `._*`, `.Spotlight-V100`, etc.) onto the FAT32 drive, the artifact-cleaning step from the macOS scripts is unnecessary here.

---

## License

These scripts are provided as-is for personal use. The firmware and map files are copyrighted by Stellantis/Continental/TomTom and are downloaded from their official servers. Use at your own risk — updating car infotainment systems always carries a small risk of issues.
