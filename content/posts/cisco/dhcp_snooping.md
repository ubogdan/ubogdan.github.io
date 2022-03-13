---
title: "Enable DHCP snooping on SG3XX layer 3 switches"
description: ""
date: "2021-08-20T21:31:58+03:00"
thumbnail: ""
categories:
- "Networking"
tags:
- "Cisco"
- "DHCP"
- "Networking"
widgets:
- "categories"
- "taglist"
---

DHCP snooping is a security feature that acts as a firewall between untrusted hosts and trusted DHCP servers.

To protect your network against rogue DHCP servers and remove malicious or malformed DHCP traffic, the DHCP snooping needs to be configured on LAN switches to block the unwanted traffic.

<!--more-->

For example, the switch we are using is an access switch, and it has previously configured 4 VLANs (5,10,15,20). In our exercise, we are going to enable DHCP snooping only for VLAN 5 and 15.
```sh
#sh vlan Created by: D-Default, S-Static, G-GVRP, R-Radius Assigned VLAN, V-Voice VLAN
Created by: D-Default, S-Static, G-GVRP, R-Radius Assigned VLAN, V-Voice VLAN

Vlan       Name           Tagged Ports      UnTagged Ports      Created by
---- ----------------- ------------------ ------------------ ----------------
1           1                                gi49-52,Po1-8           V
5           5                gi49-52                                 S
10          10               gi49-52                                 S
15          15               gi49-52                                 S
20          20               gi49-52                                 S
```

The uplink to distribution switch, which is also the direction for the trusted DHCP server, is connected in port 52 of our switch.
Using the configuration mode, we will set up the interface as `ip dhcp snooping trust`.
```sh
interface GigabitEthernet52
  ip dhcp snooping trust
  switchport mode trunk
!
```

Before enabling DHCP snooping globally on the switch, we will add the VLANs we want to protect.
```sh
ip dhcp snooping vlan 5
ip dhcp snooping vlan 15
```

To avoid DHCP request spoofings, we are going to enable DHCP snooping mac-address verification. If the device receives a packet on an untrusted interface and the source MAC address and the DHCP client hardware address do not match, address verification causes the device to drop the packet.
```sh
ip dhcp snooping verify
```

A misconfiguration of the trusted port may cause network outages because DHCP clients won't receive the response from the DHCP server.
```sh
ip dhcp snooping
```

Finally, we are going to exit the configuration mode and are going to check it.

```sh
switch#sh ip dhcp snooping
DHCP snooping is Enabled
DHCP snooping is configured on following VLANs: 5,15
DHCP snooping database is Disabled
Relay agent Information option 82 is Disabled
Option 82 on untrusted port is forbidden
Verification of hwaddr field is Enabled

Interface    Trusted
----------- ------------
Gi52           Yes
```