#!/bin/bash
# Disable PBS/Torque cgroups

echo '$cgroups false' > /var/spool/torque/mom_priv/config
echo "Config file updated:"
cat /var/spool/torque/mom_priv/config
systemctl restart pbs_mom
echo "PBS MOM restarted"
