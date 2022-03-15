---
title: "Setting Up a Redundant Internet Connection With BGP on Mikrotik ROs7"
description: ""
date: "2021-11-30T11:45:22+02:00"
thumbnail: "images/mkt-ccr2004-16g-2s.png"
categories:
- "Networking"
tags:
- "bgp"
- "networking"
- "mikrotik"
widgets:
- "categories"
- "taglist"
---

Setting up bgp on mikrotik CCR2004-16G-2S+ was quite challenging because it only supports ROs7. 

<!--more--> 

We got the following instructions from our ISP.
```text
We have prepared the following setup for the two connections with us:

- for the main BGP session, we have allocated the subnet 10.192.58.72/29.
Please set up 10.192.58.75 on your router interface using 255.255.255.248 
as the subnet mask, and use 10.192.58.73 as the remote BGP peer with AS8708.

- for the backup BGP session, we have allocated the subnet 10.192.59.232/29.
Please set up 10.192.59.235 on your router interface using 255.255.255.248 
as the subnet mask, and use 10.192.59.233 as the remote BGP peer with AS8708.

For both BGP sessions, we have allowed subnet 216.128.55.96/28, and you need 
to use the following AS64764 when you peer with us.

For the main BGP session, you need to use port 1 of the ZTE F625G.

For the backup BGP session, you need to use port 1 of the AN5506-02-FG.

Thanks
Your internet provider
```

The internal network will be connected into a bridge with 2 interfaces (ether1 and ether2). 
```yaml
/interface bridge
add name=LAN
/interface bridge port
add bridge=LAN interface=ether1
add bridge=LAN interface=ether2
```
On this bridge we will assing the public subnet alocatd by the ISP.
```yaml
/ip address
add address=216.128.55.97/28 comment=LAN interface=LAN network=216.128.55.96
```

We will use port 16 of Mikrotik for the main connection and port 15 for the backup connection.
```yaml
/ip address
add address=10.192.58.75/29 comment="ISP-MAIN" interface=ether16 \
  network=10.192.58.72
add address=10.192.59.235/29 comment="ISP-BACKUP" interface=ether15 \
  network=10.192.59.232
```

And the most challenging part is the BGP configuration.
```yaml
/routing bgp connection
add as=64764 disabled=no input.filter=ISP-IN-MAIN local.role=ebgp name=main \
    output.filter-chain=ISP-OUT-MAIN .network=bgp-networks remote.address=\
    10.192.58.73/32 .as=8708 routing-table=main

add as=64764 input.filter=ISP-IN-BACKUP local.role=ebgp name=backup \
    output.filter-chain=ISP-OUT-BACKUP .network=bgp-networks remote.address=\
    10.192.59.233/32 .as=8708 routing-table=main

/routing filter rule
add chain=ISP-OUT-MAIN disabled=no rule="accept"
add chain=ISP-OUT-BACKUP disabled=no rule="set bgp-path-prepend 2; accept"
add chain=ISP-IN-MAIN disabled=no rule="set bgp-local-pref 200; accept"
add chain=ISP-IN-BACKUP disabled=no rule="set bgp-local-pref 100; accept"
  
/ip firewall address-list
add address=216.128.55.96/28 list=bgp-networks
```
Since ROs7 there is no networks tab to add the networks to the BGP session. This was replaced with
the ip firewall address list.


