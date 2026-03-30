# NAC Wave 4 Update Scripts for macOS

Two shell scripts to prepare USB drives for updating the infotainment system (Continental NAC Wave 4) found in Peugeot, Citroën, DS, Opel/Vauxhall vehicles from ~2017 onwards.

These scripts exist because the official Citroën/Peugeot/DS/Opel Update apps frequently fail with a **"Version not compatible with hardware"** error — often caused by broken files on Stellantis's CDN servers, expired certificates, or missing license files. These scripts bypass those issues by downloading from known-good sources, automatically resuming interrupted downloads, and correctly structuring the USB drive.

---

## What's Included

| Script | What it does |
|---|---|
| `prepare_nac_update_mac.sh` | Downloads and prepares firmware **44.07.33.32_NAC-r0** (latest NAC Wave 4 firmware) |
| `prepare_nac_map_update_mac.sh` | Downloads and prepares European map **17.0.0-r0** (latest cartography, ~19 GB) |

**Always install firmware first, then maps.** The map update requires Wave 4 firmware.

---

## Compatible Vehicles

Any PSA/Stellantis vehicle with a Continental NAC Wave 4 infotainment system, including but not limited to:

- Citroën C5 Aircross, C4, C3 Aircross, Berlingo, C5 X
- Peugeot 208, 2008, 308, 3008, 508, 5008, Rifter, Partner
- DS 3, DS 4, DS 7, DS 9
- Opel/Vauxhall Corsa, Mokka, Grandland, Combo
- Toyota Proace (PSA-based models)

To confirm you have a NAC Wave 4, check the firmware version on your screen (Settings → System info). If it starts with **42.xx** or **44.xx**, you have Wave 4. Versions starting with **31.xx** are Wave 3 (some can be upgraded to Wave 4), and **21.xx** are Wave 2 (not compatible with these scripts).

---

## Prerequisites

You need two command-line tools installed on your Mac. There are two ways to get them.

### Option A — Using Homebrew (for developers / power users)

If you already have [Homebrew](https://brew.sh) installed, just run:

```bash
brew install coreutils gnu-tar
```

That's it. This gives you `gstat` (for reliable file size verification) and `gtar` (for handling large tar archives more robustly than the built-in macOS tar).

### Option B — From scratch (for everyone else)

If you've never used the Terminal before, don't worry — here's a step-by-step:

**1. Open Terminal**

Press `Cmd + Space`, type **Terminal**, and hit Enter. A window with a text prompt appears. This is where you'll type commands.

**2. Install Homebrew**

Homebrew is a package manager for macOS — think of it as an app store for command-line tools. Paste this entire line into Terminal and press Enter:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

It will ask for your Mac's password (the one you use to log in). Type it — nothing will appear on screen as you type, that's normal — and press Enter. Follow any prompts that appear. The install takes a few minutes.

**Important:** When it finishes, Homebrew may print a message saying "Run these commands to add Homebrew to your PATH." If you see this, copy and paste those lines into Terminal and press Enter. On Apple Silicon Macs (M1/M2/M3/M4), this typically looks like:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

**3. Install the required tools**

Now paste this and press Enter:

```bash
brew install coreutils gnu-tar
```

This takes about a minute. When it finishes, you're ready.

**4. Verify everything works**

```bash
gtar --version
gstat --version
```

Both should print version info without errors.

---

## Before You Start

You will need:

- A **USB drive** — any size for firmware (8 GB+), at least **32 GB for maps**
- Your **NAC UIN** — a 20-character code that identifies your specific head unit

### How to Find Your UIN

1. Format any USB drive as FAT32 (or use Disk Utility → Erase → MS-DOS FAT)
2. Insert it into the car's USB port
3. On the NAC touchscreen, go to: **Settings → System info → System version**
4. Choose **"Export to USB"** (sometimes called "Export configuration")
5. Remove the USB and plug it into your Mac
6. Two files will be on the drive:
   - `instkey_XXXXXXXXXXXXXXXXXXXX.xml`
   - `packageslist_XXXXXXXXXXXXXXXXXXXX.txt`
7. The `XXXXXXXXXXXXXXXXXXXX` part (20 characters) is your UIN

Example UIN: `0D01071F79D4D1E3643C`

---

## Usage

### Firmware Update

```bash
bash prepare_nac_update_mac.sh
```

The script will:
1. Ask for your UIN
2. Show available USB drives and let you pick one
3. Format it as FAT32 (erasing everything on it)
4. Download the firmware (~5.9 GB) with automatic resume if the connection drops
5. Verify the file is the correct, working version (not the broken CloudFront one)
6. Extract it to the USB drive
7. Download and place your license file
8. Clean macOS metadata files that can break the NAC installer

**Options:**

```
bash prepare_nac_update_mac.sh --uin 0D01071F79D4D1E3643C    # skip the UIN prompt
bash prepare_nac_update_mac.sh --tar ~/Downloads/firmware.tar  # use a file you already downloaded
bash prepare_nac_update_mac.sh --skip-format                   # don't reformat the USB
```

### Map Update

```bash
bash prepare_nac_map_update_mac.sh
```

Same flow, but for the European cartography (17.0.0-r0). This is a ~19 GB download. No UIN or license file is needed for map updates.

**Options:**

```
bash prepare_nac_map_update_mac.sh --tar ~/Downloads/maps.tar  # use a file you already downloaded
bash prepare_nac_map_update_mac.sh --skip-format                # don't reformat the USB
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

### "Version not compatible with hardware"

| Cause | Fix |
|---|---|
| You used the official Citroën/Peugeot Update app | The CloudFront file is broken since Feb 2026. Use this script instead — it downloads from the working server |
| License file missing or invalid | The script handles this, but make sure the car has WiFi as backup |
| NAC needs a reset | Hold the power/volume button on the NAC panel for 10+ seconds |
| USB drive issues | Try a different USB drive. Some NAC units are picky |
| macOS metadata files on the USB | The script cleans these. If you manually copy files, delete `.DS_Store`, `._*`, `.Spotlight-V100`, `.fseventsd`, `.Trashes` files |

### "No media content on the USB memory stick"

- The USB must be **FAT32** formatted with an **MBR** partition table (the script handles this)
- The `SWL` folder and `UpdateInfo.xml` must be in the root of the USB, not inside another folder
- If you prepared the USB on a Mac without using this script, hidden macOS files are almost certainly the problem

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

## How It Works (Technical Details)

The NAC firmware update process requires:

1. **The firmware archive** — a `.tar` file containing an `SWL` folder with the signed firmware packages. The same archive works for all NAC Wave 4 units regardless of vehicle brand
2. **A license file** — a PKCS#7 signed, encrypted file specific to your NAC unit (identified by UIN) and the firmware version (identified by UpdateID). This is downloaded from Stellantis's Majestic API. Map updates do not require a license
3. **A FAT32-formatted USB drive** with an MBR partition table. The NAC does not support exFAT, NTFS, APFS, or GPT partition tables

The "incompatible hardware" error is a generic catch-all that can mean: bad archive, invalid/missing license, expired signing certificate, corrupted USB, or macOS metadata files interfering with the directory listing. It almost never actually means incompatible hardware.

### Why the official app fails

Since February 4, 2026, Stellantis uploaded a new version of the firmware to their CloudFront CDN (6,312,210,432 bytes) that is improperly signed. The Citroën/Peugeot/DS/Opel Update apps download from this CDN. However, the previous valid version (6,312,212,480 bytes) is still available on their majestic-web.mpsa.com server at a different path. These scripts download from the working server.

---

## Community Resources

These scripts were built using knowledge from the PSA/Stellantis NAC community:

- [rui.saraiva's NAC & RCC Updates](https://sites.google.com/view/nac-rcc/system/nac/wave-4) — definitive version tracker
- [Mittns Peugeot Forum](https://www.mittns.de/) — toolbox and support
- [Peugeot Forums](https://www.peugeotforums.com/) — active discussions
- [French Car Forum](https://frenchcarforum.co.uk/forum/viewtopic.php?t=81068) — long-running update thread
- [ludwig-v's firmware reverse engineering](https://github.com/ludwig-v/psa-nac-firmware-reverse-engineering) — technical reference

---

## License

These scripts are provided as-is for personal use. The firmware and map files are copyrighted by Stellantis/Continental/TomTom and are downloaded from their official servers. Use at your own risk — updating car infotainment systems always carries a small risk of issues.
