#!/bin/bash

# NIS Diagnostic Script
# This script checks common NIS/ypbind issues

echo "=== NIS/YP Bind Diagnostic Report ==="
echo "Date: $(date)"
echo ""

echo "1. Checking ypbind service status:"
systemctl status ypbind.service --no-pager
echo ""

echo "2. Checking ypbind journal logs (last 50 lines):"
journalctl -u ypbind.service -n 50 --no-pager
echo ""

echo "3. Checking NIS domain configuration:"
echo "Current domain: $(domainname)"
cat /etc/sysconfig/network 2>/dev/null | grep -i nisdomain
echo ""

echo "4. Checking yp.conf configuration:"
cat /etc/yp.conf 2>/dev/null
echo ""

echo "5. Checking if NIS server is reachable:"
if [ -f /etc/yp.conf ]; then
    ypserver=$(grep -v '^#' /etc/yp.conf | grep -i 'ypserver\|domain' | head -1 | awk '{print $NF}')
    echo "Testing connection to NIS server: $ypserver"
    ping -c 2 "$ypserver" 2>&1
    echo ""
    echo "Checking RPC services on NIS server:"
    rpcinfo -p "$ypserver" 2>&1
fi
echo ""

echo "6. Checking rpcbind service:"
systemctl status rpcbind.service --no-pager
echo ""

echo "7. Checking network connectivity:"
ip addr show
echo ""

echo "8. Checking if ypbind package is installed:"
rpm -qa | grep ypbind
rpm -qa | grep yp-tools
echo ""

echo "9. Checking nsswitch.conf for NIS configuration:"
grep -E '^(passwd|shadow|group):' /etc/nsswitch.conf
echo ""

echo "10. Trying to query NIS manually:"
ypwhich 2>&1
ypcat passwd 2>&1 | head -5
echo ""

echo "11. Checking firewall status:"
systemctl status firewalld --no-pager
firewall-cmd --list-all 2>&1
echo ""

echo "12. Checking SELinux status:"
getenforce 2>&1
sestatus 2>&1
echo ""

echo "=== End of Diagnostic Report ==="
