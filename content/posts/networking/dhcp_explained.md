---
title: "DHCP explained"
description: ""
date: "2021-08-27T21:53:11+03:00"
thumbnail: ""
categories:
- "Networking"
tags:
- "DHCP"
- "Networking"
---

DHCP stands for dynamic host configuration protocol and is a network protocol used on IP networks where a DHCP server automatically assigns an IP address and other information to each host on the network so they can communicate efficiently with other endpoints.

<!--more--> 

In addition to the IP address, DHCP also assigns the subnet mask, default gateway address, domain name server (DNS) address and other pertinent configuration parameters.


#### Benefits of DHCP servers

* Accurate IP configuration: Typographical errors are impossible due to the automatic configuration.
* Reduced IP address conflicts: DHCP server keeps track of the offered IPs in a lease database.
* Automation of IP address administration: Any computer connected to the network will get an IP address assigned automatically.
* Efficient change management: Changing IP addressing scheme from one range to another can be done by reconfiguring the DHCP server with the new information and will be propagated to the new endpoints.


### DHCP network
In most common scenarios, the DHCP communications happen between client and server when they are on the same physical subnet or with the aid of a relay agent when they are not.

##### DHCP server
A networked device running the DCHP service that holds IP addresses and related configuration information. This is most typically a server or a router but could be anything that acts as a host, such as an SD-WAN appliance.

##### DHCP client
The endpoint that receives configuration information from a DHCP server. This can be a computer, mobile device, IoT endpoint or anything else that requires connectivity to the network.  Most are configured to receive DHCP information by default.

##### DHCP relay agent
A router or host that listens for client messages being broadcast on that network and then forwards them to a configured server. The server then sends responses back to the relay agent that passes them along to the client. This can be used to centralize DHCP servers instead of having a server on each subnet.

### Example non-renewing DHCP session communication
![DHCP Communication](/images/dhcp-protocol.png 'DHCP Protocol')

You can find a more detailed technical explanation  on [Wikipedia](https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol) and in the DHCP [rfc1531](https://datatracker.ietf.org/doc/html/rfc1531) and [rfc2131](https://datatracker.ietf.org/doc/html/rfc2131).

#### 1. Discovery
The DHCP client broadcasts a DHCPDISCOVER message on the network subnet using the destination address 255.255.255.255 (limited broadcast) or the specific subnet broadcast address (directed broadcast).

##### 2. Offer
When a DHCP server receives a DHCPDISCOVER message from a client, which is an IP address lease request, the DHCP server reserves an IP address for the client and makes a lease offer by sending a DHCPOFFER message to the client.

##### 3. Request
In response to the DHCP offer, the client replies with a DHCPREQUEST message, broadcast to the server,[a] requesting the offered address. A client can receive DHCP offers from multiple servers, but it will accept only one DHCP offer.

##### 4. Acknowledgement
When the DHCP server receives the DHCPREQUEST message from the client, the configuration process enters its final phase. The acknowledgement phase involves sending a DHCPACK packet to the client. This packet includes the lease duration and any other configuration information that the client might have requested. At this point, the IP configuration process is completed.

### DHCP security risks

The DHCP protocol requires no authentication so any client can join a network quickly. Because of this,the following threats exist when you implement DHCP on your network:
* Unauthorized DHCP servers can issue incorrect TCP/IP configuration information to DHCP clients.
* DHCP servers can overwrite valid DNS resource records with incorrect information.
* DHCP can create DNS resource records without ownership defined.
* Unauthorized DHCP clients can obtain IP addresses

If attackers are able to compromise a DHCP server on the network, they might disrupt network services, preventing DHCP clients from connecting to network resources.
By gaining control of a DHCP server, attackers can configure DHCP clients with fraudulent TCP/IP configuration information, including an invalid default gateway or Domain Name System (DNS) server configuration.




