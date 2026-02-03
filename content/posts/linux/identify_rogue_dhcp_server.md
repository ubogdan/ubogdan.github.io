---
title: "Identify and Remove Rogue DHCP Server"
date: 2021-08-01T00:13:55+03:00
lastmod: 2026-02-03
description: "A DHCP (Dynamic Host Configuration Protocol) server is a networking service that automatically assigns IP addresses to devices on a network."
categories:
  - "Linux"
tags:
  - "linux"
  - "networking"
  - "dhcp"
---

A DHCP (Dynamic Host Configuration Protocol) server is a networking service that automatically assigns IP addresses to devices on a network. This is essential for modern networks to function efficiently without manual IP address configuration.

A "rogue" DHCP server is one that has been set up without the network administrator's knowledge or permission, and can cause serious conflicts and connectivity problems on the network.

<!--more-->

## Authorized vs Rogue DHCP Servers: Understanding the Difference

**Authorized DHCP Servers** are legitimate servers deployed and managed by your network administrators. They:
- Are properly configured and maintained
- Follow organizational security policies
- Provide consistent and reliable IP address assignments
- Are documented in your network infrastructure
- Support your organization's network requirements

**Rogue DHCP Servers** are unauthorized servers that pose security and operational risks:
- Can distribute incorrect network configuration
- May assign IPs that conflict with legitimate assignments
- Could be malicious tools used for network attacks or man-in-the-middle attacks
- Create unpredictable network behavior and service disruptions
- Can compromise network security and data integrity

## Why Identifying Rogue DHCP Servers Matters

Detecting and removing rogue DHCP servers is critical for network stability and security. These unauthorized servers can cause:
- IP address conflicts and lease problems
- Clients connecting to the wrong gateway or DNS servers
- Network performance degradation
- Potential security breaches through compromised configurations
- Compliance violations in regulated environments

To find and remove a rogue DHCP server on a Linux system, you can use network scanning tools to identify all DHCP servers active on your network, then compare them against your list of authorized servers. 

## Find DHCP servers using tcpdump
```shell
# tcpdump -i ens160 -s0 -nn -e  udp port 67
00:33:35.799553 00:0c:29:e1:a0:51 > ff:ff:ff:ff:ff:ff, ethertype IPv4 (0x0800), length 355: 192.168.0.91.68 > 255.255.255.255.67: BOOTP/DHCP, Request from de:ad:c0:de:ca:fe, length 313
00:33:35.804104 c4:ad:34:37:c0:f0 > ff:ff:ff:ff:ff:ff, ethertype IPv4 (0x0800), length 342: 192.168.0.1.67 > 255.255.255.255.68: BOOTP/DHCP, Reply, length 300
```

## Find DHCP servers using nmap
```shell
# nmap -sU -p 67 --script=dhcp-discover 192.168.1.0/24
Interesting ports on 192.168.1.1:
PORT   STATE SERVICE
67/udp open  dhcps
| dhcp-discover:
|   DHCP Message Type: DHCPACK
|   Server Identifier: 192.168.1.1
|   IP Address Lease Time: 1 day, 0:00:00
|   Subnet Mask: 255.255.255.0
|   Router: 192.168.1.1
|_  Domain Name Server: 208.81.7.10, 208.81.7.14
```

## Alternative Detection Methods

You can also use the DHCP client logs on your Linux system to identify any rogue DHCP servers. Check the system logs for DHCP offer messages:

```shell
grep -i dhcp /var/log/syslog
# or on systemd systems:
journalctl | grep -i dhcp
```

## Identifying the Rogue Server

Once you have detected DHCP server responses, compare the Server Identifier MAC addresses and IP addresses against your list of authorized DHCP servers. Look for:
- Unexpected MAC addresses in the responses
- DHCP offers from unauthorized network segments
- Server identifiers not matching your documented infrastructure

## Removing Rogue DHCP Servers

Once you have identified a rogue DHCP server on your network, you can use a variety of methods to remove it:

### Physical Removal
If you can physically identify the device, simply unplug it or disconnect it from the network. This is the most direct approach and immediately stops the threat.

### Network-Level Blocking
For more sophisticated environments, block the rogue DHCP server using a managed switch or router. You can read the article [Enable DHCP snooping on SG3XX layer 3 switches](/posts/cisco/dhcp_snooping/) to learn how to implement DHCP snooping, which prevents unauthorized DHCP servers from operating on trusted network segments.

### Port Security
Enable port security on network switches to prevent unauthorized devices from connecting to network ports, preventing rogue DHCP servers from being deployed in the first place.

## Best Practices for DHCP Security

To prevent rogue DHCP servers and maintain network integrity:

1. **Document All Authorized DHCP Servers**: Keep an inventory of all legitimate DHCP servers in your network, including IP addresses, MAC addresses, and the subnets they serve.

2. **Implement DHCP Snooping**: Enable DHCP snooping on all switches to filter and validate DHCP messages, preventing rogue servers from distributing IP addresses.

3. **Use Monitoring and Alerting**: Set up continuous network monitoring to detect unexpected DHCP server responses and alert administrators immediately.

4. **Regular Audits**: Conduct periodic network scans to verify only authorized DHCP servers are operational.

5. **Access Control**: Restrict administrative access to DHCP configuration and ensure only authorized personnel can deploy or modify DHCP services.

6. **Network Segmentation**: Isolate DHCP servers on dedicated management VLANs to limit unauthorized access.

7. **Change Management**: Follow change control procedures before deploying any new DHCP services on your network.
