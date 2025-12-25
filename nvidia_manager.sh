
#!/usr/bin/env bash
set -euo pipefail
trap cleanup EXIT




# ==========================================
# Proxmox Nvidia LXC Manager
# Author: Sanchit Dang
# Version: 1.4
# ==========================================

# Ensure required utilities are installed before proceeding
REQUIRED_UTILS=(whiptail wget awk pct curl)
MISSING_UTILS=()
for util in "${REQUIRED_UTILS[@]}"; do
    if ! command -v "$util" &>/dev/null; then
        MISSING_UTILS+=("$util")
    fi
done
if [ ${#MISSING_UTILS[@]} -gt 0 ]; then
    echo "The following required utilities are missing: ${MISSING_UTILS[*]}"
    read -p "Install them now? [Y/n]: " yn
    yn=${yn:-Y}
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        sudo apt-get update
        sudo apt-get install -y "${MISSING_UTILS[@]}"
    else
        echo "Cannot continue without required utilities. Exiting."
        exit 1
    fi
fi

# Persistent log file
LOGFILE="/var/log/pve-nvidia-manager.log"
TEMPFILES=()

# Cleanup function for temp files and graceful exit
function cleanup() {
    for tmp in "${TEMPFILES[@]:-}"; do
        [ -f "$tmp" ] && rm -f "$tmp"
    done
}

# Default Fallback Version
DRIVER_VERSION="580.119.02" 
DRIVER_FILENAME="NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
DOWNLOAD_URL_BASE="https://us.download.nvidia.com/XFree86/Linux-x86_64"
HOST_DOWNLOAD_DIR="/opt"
HOST_INSTALLER_PATH="${HOST_DOWNLOAD_DIR}/${DRIVER_FILENAME}"

# ==========================================
# Helper Functions
# ==========================================

## Check if running as root and required tools are present
function check_environment() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Error: Please run as root."
        exit 1
    fi
    if ! command -v pveversion >/dev/null 2>&1; then
        echo "Error: This script must be run on a Proxmox VE host."
        exit 1
    fi
    local MISSING_TOOLS=()
    for tool in whiptail wget awk pct curl; do
        if ! command -v "$tool" &> /dev/null; then
            MISSING_TOOLS+=("$tool")
        fi
    done
    if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
        echo "Missing required tools: ${MISSING_TOOLS[*]}."
        echo "Please install them (e.g., 'apt install whiptail curl')"
        exit 1
    fi
}

## Fetch the latest Nvidia driver version from the web
function fetch_latest_version() {
    (
        echo "XXX"; echo "20"; echo "Connecting to Nvidia..."; echo "XXX"
        local ONLINE_VER
        ONLINE_VER=$(curl -sL --max-time 5 "https://www.nvidia.com/en-us/drivers/unix/" | grep -A 5 "Latest Production Branch Version" | grep -Eo "[0-9]{3}\.[0-9]{2}\.[0-9]{2}" | head -1)
        echo "XXX"; echo "80"; echo "Comparing versions..."; echo "XXX"
        sleep 0.5
        if [[ -n "$ONLINE_VER" && "$ONLINE_VER" != "$DRIVER_VERSION" ]]; then
            echo "$ONLINE_VER" > /tmp/nvidia_latest_ver
        fi
        echo "XXX"; echo "100"; echo "Done."; echo "XXX"
    ) | whiptail --title "Version Check" --gauge "Checking for latest Nvidia drivers..." 8 60 0

    if [[ -f /tmp/nvidia_latest_ver ]]; then
        local NEW_VER
        NEW_VER=$(cat /tmp/nvidia_latest_ver)
        rm -f /tmp/nvidia_latest_ver
        if (whiptail --title "Update Available" --yesno "Newer Driver Found!\n\nScript Default: $DRIVER_VERSION\nLatest Online:  $NEW_VER\n\nUse latest version?" 12 60); then
            set_driver_version "$NEW_VER"
            whiptail --msgbox "Updated configuration to use version: $DRIVER_VERSION" 8 60
        fi
    fi
}

## Set the driver version and update related variables
function set_driver_version() {
    local ver="$1"
    DRIVER_VERSION="$ver"
    DRIVER_FILENAME="NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
    HOST_INSTALLER_PATH="${HOST_DOWNLOAD_DIR}/${DRIVER_FILENAME}"
    DOWNLOAD_URL="${DOWNLOAD_URL_BASE}/${DRIVER_VERSION}/${DRIVER_FILENAME}"
}

## Prompt user for a custom driver version and validate input
function handle_custom_version() {
    local INPUT
    INPUT=$(whiptail --title "Custom Version" --inputbox "Enter the specific Nvidia driver version you need (e.g., 535.183.01):" 10 60 "$DRIVER_VERSION" 3>&1 1>&2 2>&3)
    if [[ $? -eq 0 && -n "$INPUT" && "$INPUT" =~ ^[0-9]{3}\.[0-9]{2,3}\.[0-9]{2}$ ]]; then
        set_driver_version "$INPUT"
        whiptail --msgbox "Configured custom version: $DRIVER_VERSION\n\nNote: If this version doesn't exist on Nvidia's server, the download will fail." 10 60
    else
        whiptail --msgbox "Invalid version format. Please use the format: 535.183.01" 10 60
    fi
}

## Run a command with logging and progress gauge
function run_with_log() {
    local TITLE="$1"
    local CMD="$2"
    local LOGFILE
    LOGFILE=$(mktemp)
    TEMPFILES+=("$LOGFILE")
    (
        eval "$CMD" >"$LOGFILE" 2>&1 &
        local PID=$!
        local PCT=0
        while kill -0 "$PID" 2>/dev/null; do
            local LINE
            LINE=$(tail -n1 "$LOGFILE" | cut -c1-70)
            PCT=$(( (PCT + 5) % 100 ))
            echo "XXX"; echo "$PCT"; echo "$LINE"; echo "XXX"
            sleep 0.5
        done
        wait "$PID"
        exit $?
    ) | whiptail --title "$TITLE" --gauge "Please wait..." 10 80 0
    local EXIT_CODE=${PIPESTATUS[0]}
    # Append to persistent log
    {
        echo "==== $TITLE ===="
        cat "$LOGFILE"
        echo "==== END ===="
    } >> "$LOGFILE" 2>/dev/null
    if [[ $EXIT_CODE -ne 0 ]]; then
        whiptail --title "❌ Operation Failed" --msgbox "The command failed. Press OK to view the error logs." 10 60
        whiptail --title "Error Log: $TITLE" --textbox "$LOGFILE" 20 80 --scrolltext
        return 1
    fi
    return 0
}

## Get the major device number for Nvidia
function get_nvidia_major_number() {
    if [[ -e "/dev/nvidia0" ]]; then
        stat -c '%t' /dev/nvidia0 | xargs echo "obase=10; ibase=16;" | bc
    fi
}

## Check if passthrough is enabled for a container
function is_passthrough_enabled() {
    local ctid="$1"
    grep -q "lxc.mount.entry: /dev/nvidia0" "/etc/pve/lxc/${ctid}.conf"
}

## Check if LXC container is Debian/Ubuntu based
function check_lxc_os_supported() {
    local CTID="$1"
    if ! pct exec "$CTID" -- command -v apt-get &> /dev/null; then
        return 1
    fi
    return 0
}

## Ensure the Nvidia installer exists, download if missing
function ensure_installer_exists() {
    if [[ ! -f "$HOST_INSTALLER_PATH" ]]; then
        if (whiptail --title "Download Driver" --yesno "File missing: $DRIVER_FILENAME\n\nDownload from Nvidia now?" 12 70); then
            run_with_log "Downloading Driver" "wget -O '$HOST_INSTALLER_PATH' '$DOWNLOAD_URL'"
            if [[ $? -ne 0 ]]; then exit 1; fi
        else
            exit 1
        fi
    fi
    chmod +x "$HOST_INSTALLER_PATH"
}

# ==========================================
# UI Logic Blocks
# ==========================================

function show_about() {
    whiptail --title "Features & Info" --scrolltext --msgbox "\
Proxmox Nvidia LXC Manager v1.4
--------------------------------------------
Target Driver: $DRIVER_VERSION

FEATURES:
1. SAFE INSTALL: Checks for Debian/Ubuntu LXCs to prevent damage to Alpine/Arch.
2. MONITORING: Integrated 'nvtop' and 'nvidia-smi'.
3. FLEXIBILITY: Use 'Latest', 'Default', or 'Custom' driver versions.
4. HOST MGMT: Auto-blacklists nouveau, installs headers, creates udev rules.
5. PASSTHROUGH: Auto-configures cgroups and mount points.
" 20 70
}

function handle_monitor() {
    local TOOL=$(whiptail --title "GPU Monitoring" --menu "Select tool:" 15 60 3 \
        "1" "nvtop (Visual Task Manager)" \
        "2" "nvidia-smi (Live Watch)" \
        "3" "Back" 3>&1 1>&2 2>&3)
    
    case $TOOL in
        1)
            if ! command -v nvtop &> /dev/null; then
                if (whiptail --yesno "nvtop is missing. Install it?" 10 60); then
                    run_with_log "Installing nvtop" "apt-get update && apt-get install -y nvtop"
                else return; fi
            fi
            clear; nvtop ;;
        2)
            if ! command -v nvidia-smi &> /dev/null; then
                whiptail --msgbox "Error: nvidia-smi not found." 10 60; return
            fi
            clear; watch -n 1 nvidia-smi ;;
    esac
}

function show_status_dashboard() {
    local RAW_LIST=$(pct list | awk 'NR>1 {print $1, $3, $2}')
    local RESULTS_FILE=$(mktemp)
    local COUNT=0
    local TOTAL=$(echo "$RAW_LIST" | wc -l)

    (
    while read -r ctid name status; do
        COUNT=$((COUNT + 1))
        PCT=$((COUNT * 100 / TOTAL))
        
        local PASS_ICON="❌"
        local DRIVER_ICON="❌"
        local PRIV="Unpriv"
        
        # Check Unprivileged status
        if grep -q "unprivileged: 1" "/etc/pve/lxc/${ctid}.conf"; then
            PRIV="Unpriv"
        else
            PRIV="Priv  "
        fi

        if is_passthrough_enabled "$ctid"; then
            PASS_ICON="✅"
            if [ "$status" == "running" ]; then
                if pct exec "$ctid" -- nvidia-smi &>/dev/null; then
                    DRIVER_ICON="✅"
                fi
            fi
        fi
        printf "%-5s | %-12s | %s | %-4s | %-4s\n" "$ctid" "$name" "$PRIV" "$PASS_ICON" "$DRIVER_ICON" >> "$RESULTS_FILE"
        echo "XXX"; echo "$PCT"; echo "Scanning $name..."; echo "XXX"
    done <<< "$RAW_LIST"
    ) | whiptail --title "Scanning" --gauge "Analyzing..." 10 70 0

    local TABLE_DATA=$(cat "$RESULTS_FILE")
    whiptail --title "LXC Nvidia Status" --scrolltext --msgbox \
"CTID  | Name         | Type   | Pass | Drv
----------------------------------------------
$TABLE_DATA

Type: Privileged vs Unprivileged Container
Pass: Passthrough Configured
Drv:  Driver Working (nvidia-smi)" 20 75
    rm "$RESULTS_FILE"
}

function handle_host_driver() {
    # Nouveau Check
    if [ ! -f "/etc/modprobe.d/nvidia-installer-disable-nouveau.conf" ]; then
        if (whiptail --yesno "Create nouveau blacklist file?" 10 60); then
            echo -e "blacklist nouveau\noptions nouveau modeset=0" > /etc/modprobe.d/nvidia-installer-disable-nouveau.conf
            whiptail --msgbox "✅ Created blacklist.\nREBOOT RECOMMENDED." 10 60
        fi
    fi

    if (whiptail --title "Host Install" --yesno "Install/Update Host Driver ($DRIVER_VERSION)?" 10 60); then
        ensure_installer_exists
        run_with_log "Dependencies" "apt-get update && apt-get install -y build-essential pve-headers-$(uname -r)" || return
        run_with_log "Installing Driver" "'$HOST_INSTALLER_PATH' --silent" || return
        
        # Udev Rules
        cat <<EOF > /etc/udev/rules.d/70-nvidia.rules
KERNEL=="nvidia", RUN+="/bin/bash -c '/usr/bin/nvidia-smi -L && /bin/chmod 666 /dev/nvidia*'"
KERNEL=="nvidia_uvm", RUN+="/bin/bash -c '/usr/bin/nvidia-modprobe -c0 -u && /bin/chmod 0666 /dev/nvidia-uvm*'"
EOF
        udevadm control --reload-rules && udevadm trigger
        whiptail --msgbox "✅ Host Installation Complete!" 10 60
    fi
}

function handle_passthrough_setup() {
    local RAW_LIST=$(pct list | awk 'NR>1 {print $1, $3}')
    local MENU_ITEMS=()
    while read -r ctid name; do
        if ! is_passthrough_enabled "$ctid"; then MENU_ITEMS+=("$ctid" "$name"); fi
    done <<< "$RAW_LIST"

    if [ ${#MENU_ITEMS[@]} -eq 0 ]; then
        whiptail --msgbox "All containers have passthrough enabled." 10 60; return
    fi


    local CTID
    CTID=$(whiptail --title "Enable Passthrough" --menu "Select Container:" 15 60 6 "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3)
    if [[ -z "$CTID" || ! "$CTID" =~ ^[0-9]+$ ]]; then
        whiptail --msgbox "Invalid or empty Container ID." 10 60
        return
    fi

    local MAJOR
    MAJOR=$(get_nvidia_major_number)
    if [[ -z "$MAJOR" ]]; then
        whiptail --msgbox "Error: /dev/nvidia0 missing on host." 10 60
        return
    fi

    if [[ ! -f "/etc/pve/lxc/${CTID}.conf" ]]; then
        whiptail --msgbox "Container config not found!" 10 60
        return
    fi
    cp "/etc/pve/lxc/${CTID}.conf" "/etc/pve/lxc/${CTID}.conf.bak"
    cat <<EOF >> "/etc/pve/lxc/${CTID}.conf"

# --- NVIDIA GPU PASSTHROUGH ---
lxc.cgroup2.devices.allow: c $MAJOR:* rwm
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
EOF
    if (whiptail --yesno "✅ Config added. Restart $CTID now?" 10 60); then
        run_with_log "Restarting" "pct stop $CTID && pct start $CTID"
    fi
}

function handle_lxc_install() {
    local RAW_LIST=$(pct list | awk 'NR>1 {print $1, $3}')
    local MENU_ITEMS=()
    while read -r ctid name; do
        local status=$(pct status "$ctid" | awk '{print $2}')
        if [ "$status" == "running" ] && is_passthrough_enabled "$ctid"; then MENU_ITEMS+=("$ctid" "$name"); fi
    done <<< "$RAW_LIST"

    if [ ${#MENU_ITEMS[@]} -eq 0 ]; then
        whiptail --msgbox "No eligible containers found." 10 60; return
    fi


    local CTID
    CTID=$(whiptail --title "Install Driver" --menu "Select Container:" 15 60 6 "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3)
    if [[ -z "$CTID" || ! "$CTID" =~ ^[0-9]+$ ]]; then
        whiptail --msgbox "Invalid or empty Container ID." 10 60
        return
    fi

    # SAFETY CHECK
    if ! check_lxc_os_supported "$CTID"; then
        whiptail --title "OS Warning" --msgbox "⚠️  Container $CTID does not appear to be Debian/Ubuntu based (apt not found).\n\nThis script only supports apt-based containers." 12 60
        return
    fi

    ensure_installer_exists
    run_with_log "LXC: Dependencies" "pct exec $CTID -- bash -c 'dpkg -s build-essential &>/dev/null || (apt-get update && apt-get install -y build-essential)'" || return
    run_with_log "LXC: Push File" "pct push $CTID '$HOST_INSTALLER_PATH' '/tmp/${DRIVER_FILENAME}' && pct exec $CTID -- chmod +x '/tmp/${DRIVER_FILENAME}'" || return
    
    if ! pct exec "$CTID" -- ls /dev/nvidia0 &>/dev/null; then
        whiptail --msgbox "❌ Error: /dev/nvidia0 not found inside $CTID. Reboot container?" 10 60; return
    fi

    run_with_log "LXC: Installing" "pct exec $CTID -- '/tmp/${DRIVER_FILENAME}' --no-kernel-module --silent --accept-license" || return
    pct exec "$CTID" -- rm "/tmp/${DRIVER_FILENAME}"
    
    local SMI=$(pct exec "$CTID" -- nvidia-smi --query-gpu=driver_version --format=csv,noheader)
    whiptail --msgbox "✅ Success! Driver $SMI installed in $CTID." 10 60
}

function handle_uninstall() {
    local CHOICE
    CHOICE=$(whiptail --title "Uninstall Menu" --menu "Select Target:" 12 60 2 \
        "1" "Uninstall Host Driver" \
        "2" "Uninstall LXC Driver" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1)
            if (whiptail --yesno "Uninstall Nvidia driver from HOST?" 10 60); then
                run_with_log "Uninstalling Host" "nvidia-uninstall -s"
                whiptail --msgbox "Host driver removed." 10 60
            fi
            ;;
        2)
            local CTID
            CTID=$(whiptail --inputbox "Enter Container ID:" 10 60 3>&1 1>&2 2>&3)
            if [[ -n "$CTID" && "$CTID" =~ ^[0-9]+$ ]]; then
                if (whiptail --yesno "Uninstall driver from LXC $CTID?" 10 60); then
                    run_with_log "Uninstalling LXC" "pct exec $CTID -- nvidia-uninstall -s"
                    whiptail --msgbox "LXC driver removed." 10 60
                fi
            else
                whiptail --msgbox "Invalid or empty Container ID." 10 60
            fi
            ;;
    esac
}

# ==========================================
# Main Execution
# ==========================================

check_environment
fetch_latest_version

while true; do
    CHOICE=$(whiptail --title "Proxmox Nvidia Manager | by Sanchit Dang" --menu "Driver Version: $DRIVER_VERSION" 22 70 9 \
    "1" "Status Dashboard" \
    "2" "Monitor GPU (nvtop/smi)" \
    "3" "Check/Install Host Driver" \
    "4" "Configure Passthrough (LXC)" \
    "5" "Install Driver in LXC" \
    "6" "Uninstall Driver" \
    "7" "Set Custom Version" \
    "8" "Help/About" \
    "9" "Exit" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then exit 0; fi

    case $CHOICE in
        1) show_status_dashboard ;;
        2) handle_monitor ;;
        3) handle_host_driver ;;
        4) handle_passthrough_setup ;;
        5) handle_lxc_install ;;
        6) handle_uninstall ;;
        7) handle_custom_version ;;
        8) show_about ;;
        9) exit 0 ;;
    esac
done