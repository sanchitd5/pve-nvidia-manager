# PVE NVIDIA Manager

A powerful interactive shell script to manage NVIDIA GPU drivers and passthrough for LXC containers on Proxmox VE (PVE) systems.

**Author:** Sanchit Dang

## Features
- **Status Dashboard:** View all LXC containers and their GPU passthrough/driver status.
- **GPU Monitoring:** Launch `nvtop` (visual GPU task manager) or `nvidia-smi` (live watch) from the menu.
- **Host Driver Management:** Install, update, or uninstall NVIDIA drivers on the Proxmox host.
- **LXC Passthrough Configuration:** Automatically configure LXC containers for NVIDIA GPU passthrough.
- **LXC Driver Installation:** Install NVIDIA drivers inside eligible LXC containers.
- **Custom Driver Version:** Use the latest, default, or any custom NVIDIA driver version.
- **Safe Install:** Checks for Debian/Ubuntu containers to prevent damage to unsupported OS types.
- **Persistent Logging:** All actions are logged to `/var/log/pve-nvidia-manager.log`.
- **Interactive UI:** User-friendly TUI powered by `whiptail`.

## Requirements
- Proxmox VE (tested on 7.x/8.x)
- NVIDIA GPU
- Bash shell (4.x or newer recommended)
- Tools: `whiptail`, `wget`, `awk`, `pct`, `curl`, `nvtop` (optional for monitoring)
- Internet access (for driver downloads)

## Installation

You can install pve-nvidia-manager system-wide using the provided install script:

```bash
curl -fsSL https://raw.githubusercontent.com/sanchitd5/pve-nvidia-manager/main/install.sh | bash
```

This will download and install the latest version to `/usr/local/bin`.

## Usage

After installation, simply run:

```bash
sudo nvidia_manager.sh
```

> **Note:** You must run as root on the Proxmox host.

### Main Menu Example
```
1. Status Dashboard
2. Monitor GPU (nvtop/smi)
3. Check/Install Host Driver
4. Configure Passthrough (LXC)
5. Install Driver in LXC
6. Uninstall Driver
7. Set Custom Version
8. Help/About
9. Exit
```

## Troubleshooting
- Ensure all required tools are installed: `apt install whiptail wget awk curl pct`
- For driver issues, check `/var/log/pve-nvidia-manager.log` for details.
- Only Debian/Ubuntu-based containers are supported for driver install.
- If `nvtop` is missing, the script can install it for you.

## Customization
Edit `nvidia_manager.sh` to add or modify GPU management commands as needed for your setup. The script is modular and well-commented for easy extension.

## Contributing
Pull requests and suggestions are welcome! Please open an issue or PR on GitHub.

## License
MIT License

---
**Author:** Sanchit Dang
