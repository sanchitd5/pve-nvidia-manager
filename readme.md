# PVE NVIDIA Manager

A shell script to manage NVIDIA GPU settings and operations on Proxmox VE (PVE) systems.

## Features
- Automate common NVIDIA GPU management tasks
- Designed for use with Proxmox VE
- Easy to use and modify


## Installation

You can install pve-nvidia-manager system-wide using the provided install script:

```bash
curl -fsSL https://raw.githubusercontent.com/sanchitd5/pve-nvidia-manager/main/install.sh | bash
```

This will download and install the latest version to `/usr/local/bin`.

## Usage

After installation, simply run:

```bash
nvidia_manager.sh
```

## Requirements
- Proxmox VE
- NVIDIA GPU and drivers
- Bash shell

## Customization
Edit `nvidia_manager.sh` to add or modify GPU management commands as needed for your setup.

## License
MIT License
