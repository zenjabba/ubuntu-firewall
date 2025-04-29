#!/bin/bash

# Exit on error
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Function to display usage
usage() {
    echo "Usage: $0 -w <WAN_INTERFACE> -l <LAN_INTERFACE>"
    echo "Example: $0 -w eth0 -l eth1"
    echo "Example with VLANs: $0 -w enp1s0.150@enp1s0 -l enp1s0.20@enp1s0"
    exit 1
}

# Function to get base interface name
get_base_interface() {
    local iface=$1
    # If interface contains @, take the part before it
    if [[ $iface == *"@"* ]]; then
        echo "${iface%%@*}"
    else
        echo "$iface"
    fi
}

# Function to validate interface
validate_interface() {
    local iface=$1
    local type=$2
    local base_iface=$(get_base_interface "$iface")
    
    # Check if interface exists
    if ! ip link show "$base_iface" >/dev/null 2>&1; then
        echo "Error: $type interface $base_iface does not exist"
        exit 1
    fi
    
    # Check if interface is up
    if ! ip link show "$base_iface" | grep -q "state UP"; then
        echo "Warning: $type interface $base_iface is not up. Please ensure it's properly configured."
    fi
}

# Parse command line arguments
while getopts "w:l:" opt; do
    case $opt in
        w) WAN_IFACE="$OPTARG";;
        l) LAN_IFACE="$OPTARG";;
        ?) usage;;
    esac
done

# Check if both interfaces are provided
if [ -z "$WAN_IFACE" ] || [ -z "$LAN_IFACE" ]; then
    echo "Error: Both WAN and LAN interfaces must be specified"
    usage
fi

# Get base interface names
WAN_BASE_IFACE=$(get_base_interface "$WAN_IFACE")
LAN_BASE_IFACE=$(get_base_interface "$LAN_IFACE")

# Validate interfaces
validate_interface "$WAN_IFACE" "WAN"
validate_interface "$LAN_IFACE" "LAN"

echo "Configuring firewall with:"
echo "WAN Interface: $WAN_BASE_IFACE"
echo "LAN Interface: $LAN_BASE_IFACE"

# Configure non-interactive frontend
echo "Configuring non-interactive frontend..."
export DEBIAN_FRONTEND=noninteractive

# Update and upgrade system
echo "Updating and upgrading system..."
apt-get update
apt-get upgrade -y
apt-get dist-upgrade -y
apt-get autoremove -y
apt-get clean

# Load required kernel modules
echo "Loading required kernel modules..."
modprobe nf_conntrack
modprobe nf_conntrack_netlink
modprobe nf_nat

# Enable IP forwarding
echo "Enabling IP forwarding..."
cat > /etc/sysctl.conf << EOF
# Enable IP forwarding
net.ipv4.ip_forward=1

# Increase system-wide limits
fs.file-max=2097152
fs.nr_open=2097152

# Increase network buffer sizes
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 87380 16777216

# Increase TCP buffer sizes
net.core.netdev_max_backlog=250000
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535

# TCP optimization
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_keepalive_intvl=15

# Increase connection tracking
net.netfilter.nf_conntrack_max=2000000
net.netfilter.nf_conntrack_tcp_timeout_established=1800
net.netfilter.nf_conntrack_tcp_timeout_time_wait=30
net.netfilter.nf_conntrack_tcp_timeout_close_wait=60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=120

# Disable TCP timestamps for better performance
net.ipv4.tcp_timestamps=0

# Increase local port range
net.ipv4.ip_local_port_range=1024 65535

# Increase the maximum number of open files
fs.inotify.max_user_watches=524288
EOF

# Apply sysctl settings
echo "Applying sysctl settings..."
sysctl -p || {
    echo "Warning: Some sysctl settings could not be applied. Continuing with available settings..."
}

# Install required packages
echo "Installing required packages..."
apt-get install -y iptables-persistent dnsmasq ntp

# Stop and disable systemd-resolved
echo "Stopping and disabling systemd-resolved..."
systemctl stop systemd-resolved
systemctl disable systemd-resolved

# Remove the symlink to systemd-resolved's stub resolver
if [ -L /etc/resolv.conf ]; then
    rm /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
fi

# Configure dnsmasq
echo "Configuring dnsmasq..."
cat > /etc/dnsmasq.conf << EOF
# Only listen on the LAN interface
interface=$LAN_BASE_IFACE
# Don't function as a DHCP server
no-dhcp-interface=$LAN_BASE_IFACE
# Use Google's DNS servers as upstream
server=8.8.8.8
server=8.8.4.4
# Don't read /etc/resolv.conf
no-resolv
# Don't read /etc/hosts
no-hosts
# Log DNS queries
log-queries
EOF

# Configure NTP
echo "Configuring NTP..."
cat > /etc/ntp.conf << EOF
# NTP configuration for internal network
driftfile /var/lib/ntp/drift
statistics loopstats peerstats clockstats
filegen loopstats file loopstats type day enable
filegen peerstats file peerstats type day enable
filegen clockstats file clockstats type day enable

# Allow NTP client access from local network
restrict default kod nomodify notrap nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery
restrict 127.0.0.1
restrict -6 ::1
restrict 192.168.0.0 mask 255.255.0.0 nomodify notrap

# Use Google's NTP servers
server time.google.com iburst
server time1.google.com iburst
server time2.google.com iburst
server time3.google.com iburst
server time4.google.com iburst

# Listen on all interfaces
interface listen all
EOF

# Restart services
echo "Restarting services..."
systemctl restart dnsmasq
systemctl restart ntp

# Clear existing rules
echo "Clearing existing iptables rules..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Set default policies
echo "Setting default policies..."
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow established connections
echo "Configuring basic firewall rules..."
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow SSH (adjust port if needed)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow DNS queries
iptables -A INPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p tcp --dport 53 -j ACCEPT

# Allow NTP
iptables -A INPUT -p udp --dport 123 -j ACCEPT
iptables -A INPUT -p tcp --dport 123 -j ACCEPT

# Configure NAT
echo "Configuring NAT..."
iptables -t nat -A POSTROUTING -o "$WAN_BASE_IFACE" -j MASQUERADE
iptables -A FORWARD -i "$LAN_BASE_IFACE" -o "$WAN_BASE_IFACE" -j ACCEPT

# Save rules
echo "Saving iptables rules..."
netfilter-persistent save

echo "Firewall, DNS, and NTP configuration complete!"
echo "Please make sure to configure your network interfaces in /etc/netplan/*.yaml"
echo "Reboot the system to ensure all changes take effect" 