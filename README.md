# Ubuntu NAT Firewall Setup

This repository contains a script to configure an Ubuntu server as a NAT firewall with DNS and NTP services.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Prerequisites

- Fresh Ubuntu server installation
- Root access
- Two network interfaces:
  - External interface (connected to the internet)
  - Internal interface (connected to your local network)
- For VLAN support: Properly configured VLAN interfaces

## Features

- Automatic system updates and upgrades
- NAT routing with iptables
- DNS resolution using dnsmasq
- NTP time service
- Performance optimizations for 10G networking
- Support for VLAN interfaces
- Automatic handling of systemd-resolved
- Non-interactive installation
- SSH brute force protection with fail2ban

## Usage

1. Make the script executable:
   ```bash
   chmod +x setup-firewall.sh
   ```

2. Run the script as root with your WAN and LAN interfaces:
   ```bash
   sudo ./setup-firewall.sh -w <WAN_INTERFACE> -l <LAN_INTERFACE>
   ```
   
   Example with regular interfaces:
   ```bash
   sudo ./setup-firewall.sh -w eth0 -l eth1
   ```

   Example with VLAN interfaces:
   ```bash
   sudo ./setup-firewall.sh -w enp1s0.150@enp1s0 -l enp1s0.20@enp1s0
   ```

3. Configure your network interfaces in `/etc/netplan/*.yaml`

4. Reboot the system to ensure all changes take effect:
   ```bash
   sudo reboot
   ```

## Network Interface Configuration

You'll need to configure your network interfaces in `/etc/netplan/*.yaml`. Here's an example configuration:

```yaml
network:
  version: 2
  ethernets:
    eth0:  # External interface
      dhcp4: true
    eth1:  # Internal interface
      dhcp4: false
      addresses:
        - 192.168.1.1/24  # Change this to match your internal network
```

For VLAN interfaces:
```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: false
  vlans:
    enp1s0.150:  # WAN VLAN
      id: 150
      link: enp1s0
      dhcp4: true
    enp1s0.20:   # LAN VLAN
      id: 20
      link: enp1s0
      dhcp4: false
      addresses:
        - 192.168.0.2/20
```

## What the Script Does

1. System Preparation:
   - Updates and upgrades the system
   - Configures non-interactive mode
   - Loads required kernel modules

2. Network Configuration:
   - Enables IP forwarding
   - Configures performance settings for 10G networking
   - Sets up connection tracking

3. Service Configuration:
   - Installs and configures dnsmasq for DNS resolution
   - Installs and configures NTP for time service
   - Disables systemd-resolved to prevent conflicts
   - Sets up Google DNS as upstream servers
   - Configures fail2ban for SSH protection

4. Firewall Configuration:
   - Sets up NAT using iptables
   - Configures basic firewall rules
   - Allows established connections
   - Allows SSH, DNS, and NTP traffic
   - Makes the configuration persistent

## Performance Optimizations

The script includes several performance optimizations for 10G networking:
- Increased system-wide limits
- Optimized network buffer sizes
- TCP performance tweaks
- Connection tracking optimizations
- Disabled TCP timestamps
- Increased local port range

## Security Considerations

- The script sets up a basic firewall configuration. You may need to add additional rules based on your specific requirements.
- Make sure to change the default SSH port if needed.
- Consider adding rules for any additional services you need to allow through the firewall.
- The script disables systemd-resolved to prevent DNS conflicts.
- fail2ban is configured to protect against SSH brute force attacks on the WAN interface.

## Troubleshooting

If you encounter any issues:
1. Check that your network interfaces are properly configured
2. Verify that the interfaces are up and have IP addresses
3. Check the system logs for any service-related errors
4. Ensure that port 53 is not being used by another service
5. Verify that the kernel modules are loaded correctly
6. Check fail2ban status with `fail2ban-client status` 