#!/bin/bash

#bind-vfio-a100.sh
# This script binds the NVIDIA A100 GPU to the vfio-pci driver.
set -e

PCI_DEV="0000:18:00.0"
VENDOR="10de"
DEVICE="20f1"
DRIVER_PATH="/sys/bus/pci/devices/$PCI_DEV/driver"

# Only rebind if currently not using vfio-pci
if [[ "$(readlink -f "$DRIVER_PATH")" != *vfio-pci ]]; then
    echo "[INFO] Unbinding from current driver..."
    echo "$PCI_DEV" > "$DRIVER_PATH/unbind" 2>/dev/null || true

    echo "[INFO] Overriding with vfio-pci..."
    echo "vfio-pci" > "/sys/bus/pci/devices/$PCI_DEV/driver_override"

    echo "[INFO] Reprobing device..."
    echo "$PCI_DEV" > /sys/bus/pci/drivers_probe
fi


# [Unit]
# Description=Bind NVIDIA A100 to vfio-pci
# After=default.target
# Before=libvirtd.service

# [Service]
# Type=oneshot
# ExecStart=/usr/local/bin/bind-vfio-a100.sh
# RemainAfterExit=true

# [Install]
# WantedBy=multi-user.target



# systemctl daemon-reexec
# systemctl daemon-reload
# systemctl enable bind-vfio-a100.service