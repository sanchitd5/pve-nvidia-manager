#!/bin/bash
# install.sh - Installer for pve-nvidia-manager

set -e

# Ensure required utilities are installed
REQUIRED_UTILS=(whiptail wget awk pct curl)
MISSING_UTILS=()
for util in "${REQUIRED_UTILS[@]}"; do
    if ! command -v "$util" &>/dev/null; then
        MISSING_UTILS+=("$util")
    fi
done
if [ ${#MISSING_UTILS[@]} -gt 0 ]; then
    echo "Installing missing utilities: ${MISSING_UTILS[*]}"
    sudo apt-get update
    sudo apt-get install -y "${MISSING_UTILS[@]}"
fi

SCRIPT_NAME="nvidia_manager.sh"
INSTALL_DIR="/usr/local/bin"
REPO_URL="https://github.com/sanchitd5/pve-nvidia-manager"

# Download the latest version of the script from GitHub
curl -fsSL "$REPO_URL/raw/main/$SCRIPT_NAME" -o "$SCRIPT_NAME"

# Make it executable
chmod +x "$SCRIPT_NAME"

# Move to /usr/local/bin
sudo mv "$SCRIPT_NAME" "$INSTALL_DIR/"

echo "pve-nvidia-manager installed successfully!"
echo "You can now run 'nvidia_manager.sh' from anywhere."

# Add alias to shell config if relevant
ALIAS_CMD='alias pve-nvidia-manager="nvidia_manager.sh"'
ADDED_ALIAS=false
if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
	if ! grep -Fxq "$ALIAS_CMD" "$HOME/.zshrc" 2>/dev/null; then
		echo "$ALIAS_CMD" >> "$HOME/.zshrc"
		echo "Alias added to .zshrc: pve-nvidia-manager"
		ADDED_ALIAS=true
	fi
fi
if [ -n "$BASH_VERSION" ] || [ -f "$HOME/.bashrc" ]; then
	if ! grep -Fxq "$ALIAS_CMD" "$HOME/.bashrc" 2>/dev/null; then
		echo "$ALIAS_CMD" >> "$HOME/.bashrc"
		echo "Alias added to .bashrc: pve-nvidia-manager"
		ADDED_ALIAS=true
	fi
fi
if [ "$ADDED_ALIAS" = false ]; then
	echo "You may want to add the following alias to your shell config manually:"
	echo "$ALIAS_CMD"
fi
