#!/usr/bin/env bash
#
# cs2_install_and_debug.sh
# -----------------------------------------------------------
# 1) Installs minimal 32-bit deps on Rocky Linux 9.x for SteamCMD + CS2
# 2) Creates a 'steam' user at /home/steam
# 3) Manually installs SteamCMD into /home/steam/steamcmd
# 4) Symlinks steamclient.so so the server can properly load it
# 5) Installs/updates CS2 in /home/steam/cs2-base
#    5.1) Patches gameinfo.gi for Metamod if needed
# 6) (Optional) Adjusts SELinux context for .so plugins in /home/steam
# 7) (Optional) Appends LD_LIBRARY_PATH for the steam user
# 8) Prints multi-instance usage instructions
# 9) (Optional) Grants user "dijaz" permission to edit files in /home/steam
# -----------------------------------------------------------
# Then:
# - Optionally runs a debug script (the debug_info).
# - Optionally starts up your 'cs2_surf_easy' server with run_surf.sh
#
# Usage:
#   sudo su
#   chmod +x cs2_install_and_debug.sh
#   ./cs2_install_and_debug.sh

set -e  # Exit on first error

##############################################
# 1) Must be root
##############################################
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Please run this script as root (e.g. sudo ./cs2_install_and_debug.sh)."
  exit 1
fi

##############################################
# 1.1) Basic Setup
##############################################
echo "=== [STEP 1] Updating system + installing base dependencies on Rocky Linux 9.x... ==="
dnf -y update
dnf -y upgrade

echo "=== Installing 32-bit libs + basic tools (curl, screen, etc.)... ==="
dnf install -y \
  glibc.i686 \
  libstdc++.i686 \
  SDL2.i686 \
  curl \
  wget \
  nano \
  screen \
  xz \
  tar \
  ca-certificates \
  iproute \
  which \
  policycoreutils-python-utils  # for optional SELinux adjustments

##############################################
# 2) Create steam user if missing
##############################################
if ! id -u steam &>/dev/null; then
  echo "=== Creating system user 'steam' with /home/steam... ==="
  useradd -r -m -d /home/steam -s /usr/sbin/nologin steam
else
  echo ">>> Found existing 'steam' user."
fi

mkdir -p /home/steam
chown -R steam:steam /home/steam

##############################################
# 3) Manually install SteamCMD
##############################################
STEAMCMD_DIR="/home/steam/steamcmd"
echo ""
echo "=== [STEP 2] Manually installing (or reusing) SteamCMD at: $STEAMCMD_DIR ==="

if [[ ! -d "$STEAMCMD_DIR" ]]; then
  echo ">>> $STEAMCMD_DIR does not exist; creating + downloading SteamCMD..."
  mkdir -p "$STEAMCMD_DIR"
  chown -R steam:steam "$STEAMCMD_DIR"
  cd "$STEAMCMD_DIR"

  sudo -u steam wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
  sudo -u steam tar -xvzf steamcmd_linux.tar.gz
  rm -f steamcmd_linux.tar.gz
else
  echo ">>> Already found $STEAMCMD_DIR; skipping re-download."
fi

##############################################
# 4) Symlink steamclient.so for the server
##############################################
echo ""
echo "=== [STEP 3] Symlinking steamclient.so so dedicated server can load it ==="
sudo -u steam bash <<EOF_STEAM
mkdir -p /home/steam/.steam/sdk64
ln -sf /home/steam/steamcmd/linux64/steamclient.so /home/steam/.steam/sdk64/steamclient.so

# 32-bit link (usually not strictly needed for CS2, but safe):
mkdir -p /home/steam/.steam/sdk32
ln -sf /home/steam/steamcmd/linux32/steamclient.so /home/steam/.steam/sdk32/steamclient.so
EOF_STEAM

##############################################
# 5) Install/Update CS2 server
##############################################
echo ""
echo "=== [STEP 4] Installing/Updating CS2 into /home/steam/cs2-base... ==="
STEAMCMD_BIN="$STEAMCMD_DIR/steamcmd.sh"

if [[ ! -x "$STEAMCMD_BIN" ]]; then
  echo "ERROR: $STEAMCMD_BIN is missing or not executable. Aborting."
  exit 1
fi

BASE_DIR="/home/steam/cs2-base"
mkdir -p "$BASE_DIR"
chown -R steam:steam "$BASE_DIR"

# If there's a truncated (0-byte) libserver_valve.so, remove it
valve_lib="$BASE_DIR/game/bin/linuxsteamrt64/libserver_valve.so"
if [[ -f "$valve_lib" && ! -s "$valve_lib" ]]; then
  echo ">>> Detected truncated libserver_valve.so at $valve_lib. Removing..."
  rm -f "$valve_lib"
fi

echo ">>> Using SteamCMD at: $STEAMCMD_BIN"
sudo -u steam "$STEAMCMD_BIN" \
  +@sSteamCmdForcePlatformType linux \
  +@sSteamCmdForcePlatformBitness 64 \
  +force_install_dir "$BASE_DIR" \
  +login anonymous \
  +app_update 730 validate \
  +quit

# Optional: remove old Valve lib if you hit "Failed to open libtier0.so"
if [[ -f "$BASE_DIR/bin/libgcc_s.so.1" ]]; then
  echo "Removing old libgcc_s.so.1..."
  rm -f "$BASE_DIR/bin/libgcc_s.so.1"
fi

echo ""
echo "=== [STEP 5] CS2 server files now reside in $BASE_DIR ==="

##############################################
# 5.1) Patch gameinfo.gi for Metamod
##############################################
GAMEINFO_FILE="$BASE_DIR/game/csgo/gameinfo.gi"
if [[ -f "$GAMEINFO_FILE" ]]; then
  echo "=== [STEP 5.1] Patching $GAMEINFO_FILE for Metamod if needed... ==="
  PATTERN="Game_LowViolence[[:space:]]*csgo_lv // Perfect World content override"
  LINE_TO_ADD="			Game	csgo/addons/metamod"
  REGEX_TO_CHECK="^[[:space:]]*Game[[:space:]]*csgo/addons/metamod"

  if grep -qE "$REGEX_TO_CHECK" "$GAMEINFO_FILE"; then
    echo ">>> $GAMEINFO_FILE already patched for Metamod."
  else
    echo ">>> Patching in 'Game csgo/addons/metamod' after the $PATTERN line..."
    awk -v pattern="$PATTERN" -v lineToAdd="$LINE_TO_ADD" '{
        print $0;
        if ($0 ~ pattern) {
            print lineToAdd;
        }
    }' "$GAMEINFO_FILE" > /tmp/tmp_gameinfo && mv /tmp/tmp_gameinfo "$GAMEINFO_FILE"

    echo ">>> $GAMEINFO_FILE successfully patched."
  fi
else
  echo ">>> $GAMEINFO_FILE not found; skipping Metamod patch."
fi

##############################################
# 6) (Optional) Adjust SELinux for .so plugins
##############################################
echo ""
read -p "Do you want to adjust SELinux context for /home/steam to allow .so plugins? (y/n) [n]: " SELX
SELX="${SELX,,}"

if [[ "$SELX" == "y" ]]; then
  echo ">>> Setting SELinux type 'textrel_shlib_t' for /home/steam..."
  semanage fcontext -a -t textrel_shlib_t "/home/steam(/.*)?"
  restorecon -Rv /home/steam
fi

##############################################
# 7) (Optional) Append LD_LIBRARY_PATH for 'steam' user
##############################################
echo ""
read -p "Do you want to append LD_LIBRARY_PATH (linuxsteamrt64) to the steam user's ~/.bash_profile? (y/n) [n]: " LIBX
LIBX="${LIBX,,}"

if [[ "$LIBX" == "y" ]]; then
  echo ">>> Appending engine bin path to steam user's LD_LIBRARY_PATH..."
  sudo -u steam bash -c "cat >> /home/steam/.bash_profile <<EOF

# Ensure engine libraries are found for .so plugins:
export LD_LIBRARY_PATH=\"$BASE_DIR/game/bin/linuxsteamrt64:\$LD_LIBRARY_PATH\"

EOF"
fi

##############################################
# 8) Print usage
##############################################
cat <<EOF

===========================================================================
[STEP 8] Next Steps: Multi-Instance Usage

1) (Optional) For Metamod or other plugins:
   - Place them in:  $BASE_DIR/game/csgo/addons/
   - If hooking fails or the engine updates, keep Metamod updated.

2) For each additional server (e.g., "surf"), do:
     mkdir -p /home/steam/cs2_surf
     cd /home/steam/cs2_surf
     ln -s $BASE_DIR/game game
     chown -R steam:steam /home/steam/cs2_surf

3) Create a start script, e.g. run.sh:
     #!/usr/bin/env bash
     PORT=27015
     cd /home/steam/cs2_surf
     sudo -u steam env LD_LIBRARY_PATH="$BASE_DIR/game/bin/linuxsteamrt64:\$LD_LIBRARY_PATH" \\
       ./game/bin/linuxsteamrt64/cs2 -dedicated \\
         -console -usercon -autoupdate -tickrate 128 \\
         -port \$PORT +map de_dust2 +sv_lan 0 +sv_setsteamaccount <YOUR_GSLT>

4) chmod +x run.sh && ./run.sh

5) For future updates:
   cd $STEAMCMD_DIR
   sudo -u steam ./steamcmd.sh +force_install_dir $BASE_DIR \\
       +login anonymous +app_update 730 validate +quit

Restart your servers afterwards. Enjoy CS2 on Rocky Linux 9!
===========================================================================
EOF

echo "=== Installation steps complete. ==="

##############################################
# 9) (Optional) Let user "dijaz" also modify files
##############################################
if id -u dijaz &>/dev/null; then
  echo ""
  read -p "Allow user 'dijaz' to share group ownership of /home/steam? (y/n) [n]: " DIAJ_CHOICE
  DIAJ_CHOICE="${DIAJ_CHOICE,,}"
  if [[ "$DIAJ_CHOICE" == "y" ]]; then
    echo ">>> Adding 'dijaz' to group 'steam' and setting group-writable perms..."

    # 1) Add user 'dijaz' to steam group
    usermod -aG steam dijaz

    # 2) Ensure group-writability under /home/steam
    chmod -R g+rw /home/steam

    # 3) Keep setgid bit so new subfiles also get group=steam
    find /home/steam -type d -exec chmod g+s {} \;

    echo ">>> Done. Now 'dijaz' can read/write files in /home/steam."
    echo ">>> (Re-login as dijaz to update group membership.)"
  else
    echo "Skipping group changes for user 'dijaz'."
  fi
else
  echo ""
  echo "No local user named 'dijaz' found. Skipping any 'dijaz' group changes."
fi

##############################################
# Define: debug_info function
# (the debug script).
##############################################
debug_info() {
  echo ""
  echo "========================================================================="
  echo "        Debug Script: Gathering Diagnostic Info...              "
  echo "========================================================================="

  # -- 1) OS Release / Kernel / SELinux
  echo "===== [1/15] OS Release Information ====="
  cat /etc/*release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || echo "No OS release file found."

  echo ""
  echo "===== [2/15] Kernel / Architecture ====="
  uname -a

  echo ""
  echo "===== [3/15] SELinux Status ====="
  sestatus 2>/dev/null || echo "No SELinux or sestatus not found."

  echo ""
  echo "===== Current Logged-In User ====="
  whoami

  echo ""
  echo "===== Checking 'steam' User Info ====="
  id steam 2>/dev/null || echo "User 'steam' not found!"

  # -- 2) Check permissions
  echo ""
  echo "===== Checking Permissions on /home/steam ====="
  ls -ld /home/steam 2>/dev/null || echo "No /home/steam directory found!"

  echo ""
  echo "===== Checking Permissions on /home/steam/servers ====="
  ls -ld /home/steam/servers/ 2>/dev/null || echo "No /home/steam/servers dir"

  echo ""
  echo "===== Checking Permissions on /home/steam/cs2-base/game/csgo ====="
  ls -ld /home/steam/cs2-base/game/csgo 2>/dev/null || echo "No /home/steam/cs2-base/game/csgo"

  # -- 3) Searching for libs
  echo ""
  echo "===== Searching for server libs in bin/linuxsteamrt64 + addons... ====="
  find /home/steam/cs2-base/game/bin/linuxsteamrt64/ -type f -name 'libserver*' 2>/dev/null
  find /home/steam/cs2-base/game/csgo/addons/ -type f -name 'libserver*' 2>/dev/null

  echo ""
  echo "===== Detailed Listing of Metamod's bin/linuxsteamrt64/ ====="
  ls -l /home/steam/cs2-base/game/csgo/addons/metamod/bin/linuxsteamrt64/ 2>/dev/null || echo "No metamod bin dir"

  # -- 4) ldd checks
  echo ""
  echo "===== ldd on metamod.2.cs2.so ====="
  ldd /home/steam/cs2-base/game/csgo/addons/metamod/bin/linuxsteamrt64/metamod.2.cs2.so 2>/dev/null || echo "No metamod.2.cs2.so"

  echo ""
  echo "===== ldd on Metamod libserver.so ====="
  ldd /home/steam/cs2-base/game/csgo/addons/metamod/bin/linuxsteamrt64/libserver.so 2>/dev/null || echo "No metamod libserver.so"

  echo ""
  echo "===== ldd on Valve's main server binary (libserver.so in bin/linuxsteamrt64) ====="
  ldd /home/steam/cs2-base/game/bin/linuxsteamrt64/libserver.so 2>/dev/null || echo "No Valve libserver.so in bin/linuxsteamrt64"

  # -- 5) Check engine libtier0
  echo ""
  echo "===== Checking engine's libtier0.so existence + SELinux context + ldd ====="
  LIBTIER0_PATH="/home/steam/cs2-base/game/bin/linuxsteamrt64/libtier0.so"
  if [[ -f "$LIBTIER0_PATH" ]]; then
    echo "File exists: $LIBTIER0_PATH"
    ls -lZ "$LIBTIER0_PATH"
    echo ""
    echo "== ldd on libtier0.so =="
    ldd "$LIBTIER0_PATH" || echo "ldd reported errors"
  else
    echo "No libtier0.so found at $LIBTIER0_PATH"
  fi

  # -- 6) metamod.2.cs2.so RPATH / RUNPATH
  echo ""
  echo "===== Checking metamod.2.cs2.so for RPATH / RUNPATH + SELinux context ====="
  METAMOD_SO="/home/steam/cs2-base/game/csgo/addons/metamod/bin/linuxsteamrt64/metamod.2.cs2.so"
  if [[ -f "$METAMOD_SO" ]]; then
    ls -lZ "$METAMOD_SO"
    echo ""
    echo "== readelf -d metamod.2.cs2.so =="
    readelf -d "$METAMOD_SO" | grep -E 'RPATH|RUNPATH' || echo "No RPATH/RUNPATH lines found"
  else
    echo "No metamod.2.cs2.so found"
  fi

  # -- 7) Searching gameinfo.gi
  echo ""
  echo "===== Searching 'gameinfo.gi' near 'Game_LowViolence' lines ====="
  grep -C5 'Game_LowViolence' /home/steam/cs2-base/game/csgo/gameinfo.gi 2>/dev/null || echo 'No Game_LowViolence found'

  echo ""
  echo "===== Searching for 'Game  csgo/addons/metamod' lines in gameinfo.gi ====="
  grep -C5 'Game[[:blank:]]*csgo/addons/metamod' /home/steam/cs2-base/game/csgo/gameinfo.gi 2>/dev/null || echo 'No metamod line found'

  # -- 8) metamod .vdf
  echo ""
  echo "===== Checking for metamod .vdf Files ====="
  ls -l /home/steam/cs2-base/game/csgo/addons/metamod/*.vdf 2>/dev/null || echo "No .vdf files in metamod folder"

  echo ""
  echo "===== Print metamod_x64.vdf (if it exists) ====="
  cat /home/steam/cs2-base/game/csgo/addons/metamod/metamod_x64.vdf 2>/dev/null || echo "metamod_x64.vdf not found"

  # -- 9) If there's an install script
  echo ""
  echo "===== Checking if /home/dijaz/cs2_base_install.sh exists ====="
  cat /home/dijaz/cs2_base_install.sh 2>/dev/null || echo "No /home/dijaz/cs2_base_install.sh"

  # -- 10) Checking run_surf.sh
  echo ""
  echo "===== run_surf.sh from /home/steam/servers/cs2_surf_easy ====="
  cat /home/steam/servers/cs2_surf_easy/run_surf.sh 2>/dev/null || echo 'No run_surf.sh found'

  # -- 11) Dump environment
  echo ""
  echo "===== Environment Variables (sorted) ====="
  env | sort

  # -- 12) dmesg / journal segfault checks
  echo ""
  echo "===== Searching 'dmesg' for segfault or avc: denied lines (last 200 lines) ====="
  dmesg | tail -n 200 | grep -Ei 'segfault|avc:|denied' || echo 'No segfault/denials in last 200 lines of dmesg'

  echo ""
  echo "===== Searching system journal for segfault or metamod (last 500 lines) ====="
  journalctl -n 500 --no-pager 2>/dev/null | grep -Ei 'segfault|metamod|avc:|denied' || echo 'No segfault in last 500 lines of journal'

  # -- 13) SELinux contexts under /home/steam/cs2-base (optional)
  echo ""
  read -p "List SELinux contexts under /home/steam/cs2-base? (y/n) [n]: " REPLY_SELINUX
  REPLY_SELINUX="${REPLY_SELINUX,,}"
  if [[ "$REPLY_SELINUX" == "y" ]]; then
    echo "===== SELinux context listing under /home/steam/cs2-base (top-level) ====="
    ls -lZ /home/steam/cs2-base
    echo "...(Use 'ls -lZR /home/steam/cs2-base' for a deep recursive listing)."
  fi

  # -- 14) Running processes for 'steam|cs2|metamod'
  echo ""
  echo "===== Checking running processes for 'steam', 'cs2', or 'metamod' ====="
  ps auxw | grep -E 'steam|cs2|metamod' | grep -v grep || echo "No matching processes."

  # -- 15) Disk usage + memory + open ports + relevant packages
  echo ""
  echo "===== Disk Usage (df -h) ====="
  df -h

  echo ""
  echo "===== Free Memory (free -m) ====="
  free -m

  echo ""
  echo "===== Checking open ports (ss or netstat) ====="
  if command -v ss &>/dev/null; then
    ss -tuln | grep -E 'Proto|27015|cs2' || echo "No lines matching '27015' or 'cs2'"
  else
    netstat -tuln | grep -E 'Proto|27015|cs2' || echo "No lines matching '27015' or 'cs2'"
  fi

  echo ""
  echo "===== Searching for installed packages that might be relevant ====="
  if command -v dnf &>/dev/null; then
    dnf list installed glibc\* libstdc\* SDL2\* policycoreutils\* screen which iproute xz tar wget nano | \
      grep -E 'Installed|glibc|libstdc|SDL2|policycoreutils|screen|which|iproute|xz|tar|wget|nano' || echo "No matching packages found"
  elif command -v rpm &>/dev/null; then
    rpm -qa | grep -E 'glibc|libstdc|SDL2|policycoreutils|screen|which|iproute|xz|tar|wget|nano' || echo "No matching packages found in rpm -qa"
  fi

  echo ""
  echo "===== END OF DEBUG INFO ====="
}

##############################################
# Prompt: run debug script?
##############################################
echo ""
read -p "Would you like to run the debug script now? (y/n) [n]: " RUNDBG
RUNDBG="${RUNDBG,,}"
if [[ "$RUNDBG" == "y" ]]; then
  debug_info
fi

##############################################
# Prompt: start cs2_surf_easy server?
##############################################
echo ""
RUN_SURF_SCRIPT="/home/steam/servers/cs2_surf_easy/run_surf.sh"
if [[ -f "$RUN_SURF_SCRIPT" ]]; then
  read -p "Do you want to start the 'surf easy' server now? (y/n) [n]: " SURF_RUN_CHOICE
  SURF_RUN_CHOICE="${SURF_RUN_CHOICE,,}"
  if [[ "$SURF_RUN_CHOICE" == "y" ]]; then
    echo "Attempting to run: $RUN_SURF_SCRIPT"
    if [[ -x "$RUN_SURF_SCRIPT" ]]; then
      "$RUN_SURF_SCRIPT"
    else
      echo "Making $RUN_SURF_SCRIPT executable..."
      chmod +x "$RUN_SURF_SCRIPT"
      "$RUN_SURF_SCRIPT"
    fi
  else
    echo "Skipping server start. You can run it later via: $RUN_SURF_SCRIPT"
  fi
else
  echo "No /home/steam/servers/cs2_surf_easy/run_surf.sh script found, skipping server start."
fi

echo ""
echo "=== Script completed. Have fun! ==="
