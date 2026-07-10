#!/bin/bash

# Biometric Latency Cartographer - Environment Setup Script
# Configures kernel-level real-time permissions and performance tuning
# Supported: Linux (Debian/Ubuntu/Arch/Fedora)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Biometric Latency Cartographer: System Configuration ===${NC}"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root to modify kernel parameters.${NC}"
   exit 1
fi

CURRENT_USER=$(logname || echo $SUDO_USER)

# 1. Real-time Scheduling Permissions
echo -e "${BLUE}[1/5] Configuring Real-time Priorities...${NC}"
LIMITS_CONF="/etc/security/limits.d/99-biometric-latency.conf"
cat <<EOF > "$LIMITS_CONF"
@realtime - rtprio 99
@realtime - memlock unlimited
@realtime - nice -20
$CURRENT_USER - rtprio 99
$CURRENT_USER - memlock unlimited
$CURRENT_USER - nice -20
EOF

if ! getent group realtime > /dev/null; then
    groupadd realtime
fi
usermod -aG realtime "$CURRENT_USER"
echo -e "${GREEN}Real-time limits updated for user $CURRENT_USER.${NC}"

# 2. Kernel Parameters (sysctl)
echo -e "${BLUE}[2/5] Tuning Kernel for Sub-millisecond Latency...${NC}"
SYSCTL_CONF="/etc/sysctl.d/99-latency-tuning.conf"
cat <<EOF > "$SYSCTL_CONF"
# Reduce filesystem writeback latency
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
# Minimize swap usage
vm.swappiness = 10
# Increase maximum user watches for high-frequency input
fs.inotify.max_user_watches = 524288
# Network latency tuning (for remote telemetry)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
# Reduce task migration between cores
kernel.sched_migration_cost_ns = 5000000
# RT specific tuning
kernel.sched_rt_runtime_us = -1
EOF
sysctl -p "$SYSCTL_CONF" || true
echo -e "${GREEN}Kernel parameters applied.${NC}"

# 3. CPU Governor Setup
echo -e "${BLUE}[3/5] Setting CPU Scaling Governor to 'performance'...${NC}"
if command -v cpupower &> /dev/null; then
    cpupower frequency-set -g performance
elif [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo performance > "$gov" 2>/dev/null || true
    done
fi
echo -e "${GREEN}CPU fixed to performance mode.${NC}"

# 4. Udev Rules for High-Speed Input Hardware
echo -e "${BLUE}[4/5] Configuring Udev Rules for Input Polling...${NC}"
UDEV_RULES="/etc/udev/rules.d/99-biometric-latency.rules"
cat <<EOF > "$UDEV_RULES"
# Access to raw HID for sub-millisecond polling
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0666", GROUP="realtime"
# Access to input logs
SUBSYSTEM=="input", MODE="0666", GROUP="realtime"
EOF
udevadm control --reload-rules
udevadm trigger
echo -e "${GREEN}Udev rules updated.${NC}"

# 5. Environment Variables
echo -e "${BLUE}[5/5] Exporting Environment Variables...${NC}"
ENV_FILE="/etc/profile.d/biometric-latency.sh"
cat <<EOF > "$ENV_FILE"
# Rendering Backend Optimization
export SDL_VIDEODRIVER=wayland,x11
export DESKTOP_SESSION=null
export WGP_BACKEND=vulkan
export __GL_THREADED_OPTIMIZATIONS=1
export MESA_DEBUG=0
# Biometric Cartographer Paths
export BL_DATA_ROOT="/var/lib/biometric-latency"
export BL_LOG_LEVEL="DEBUG"
EOF
chmod +x "$ENV_FILE"

# Create Data Directory
mkdir -p /var/lib/biometric-latency
chown "$CURRENT_USER":realtime /var/lib/biometric-latency
chmod 775 /var/lib/biometric-latency

echo -e "${GREEN}=== Setup Complete ===${NC}"
echo -e "Please logout and login again for group changes to take effect."
echo -e "Verification: Run 'ulimit -r' and ensure it returns '99'."