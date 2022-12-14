---
title: "Identify and remove rogue dhcp server"
description: ""
date: "2021-08-01T00:13:55+03:00"
thumbnail: ""
categories:
- "Linux"
tags:
- "linux"
- "networking"
- "dhcp"
---


A DHCP (Dynamic Host Configuration Protocol) server is a networking service that automatically assigns IP addresses to devices on a network.

A "rogue" DHCP server is one that has been set up without the network administrator's knowledge or permission, and can cause conflicts and connectivity problems on the network.

<!--more--> 

To find and remove a rogue DHCP server on a Linux system, you can use a network scanning tool to scan the network for DHCP servers, and then compare the results to the list of authorized DHCP servers to see if any unauthorized ones are present. 

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

You can also use the DHCP client logs on your Linux system to try to identify any rogue DHCP servers.

Once you have identified a rogue DHCP server on your network, you can use a variety of methods to remove it.

One option is to simply unplug the device that is running the rogue DHCP server, if you can easily identify it.

Another option is to block the rogue DHCP server using a managed switch or router, if you have one available. You can read the article [Enable DHCP snooping on SG3XX layer 3 switches](/posts/cisco/dhcp_snooping/) to learn how to do that.





