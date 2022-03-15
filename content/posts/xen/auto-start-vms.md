---
title: "Setting Citrix XenServer 6.x/7.x/8.x to Auto-Start Virtual Machines"
description: ""
date: "2022-03-15T22:07:50+02:00"
thumbnail: "images/xen-center.png"
categories:
- "Virtualization"
tags:
- "xen"
widgets:
- "categories"
- "taglist"
---

If you are still running a Citrix Xen Hypervisor nowadays, you may figure out it comes with many challenges. 
One of them is to figure out a way to set up the imported VM appliances to start at boot time.

Upgrading the Xen server to a new version is quite simple and has the advantage of preserving the preview settings. 
Sometimes this is not possible due to hardware aging when we need to do a clean install for the supervisor and reimport the virtual appliances.

<!--more--> 

In XenServer versions 6.x, the direct GUI ability to auto-start a Virtual Machine on startup of XenServer was removed. 
The only option left is to use the access the XenServer cli via Citrix XenCenter or via SSH connection.


Setting the Citrix XenServer to allow Auto-Start
------------------------------------------------
1. Gather the UUIDs of the pools you wish to auto-start. To get the list of the pools on your XenServer, run “xe pool-list”
```shell
[root@xen ~]# xe pool-list
uuid ( RO)                : ae883deb-6278-18f1-b599-810a47066c33
          name-label ( RW): 
    name-description ( RW): 
              master ( RO): 5a5b8220-fe72-4439-a94f-e61d66860ff9
          default-SR ( RW): bd78ed68-112f-4929-f230-174c261bbf6b
```

2. Type the following command and update UUID value obtained in the preview screen to set the pool or server to allow auto-start:
```shell
[root@xen ~]# xe pool-param-set uuid=ae883deb-6278-18f1-b599-810a47066c33 other-config:auto_poweron=true
```


Setting the Virtual Machines to Auto-Start
------------------------------------------------

Gather the UUIDs of the Virtual Machine you want to auto-start by running xe vm-list.
```shell
[root@xen ~]# xe vm-list
uuid ( RO)           : 1b62d158-c01b-44ce-8ad1-55e3295b179f
     name-label ( RW): Control domain on host: spcop
    power-state ( RO): running


uuid ( RO)           : d20c6c7f-e3d3-5731-48c1-9b1d8163a23c
     name-label ( RW): Appliance1
    power-state ( RO): running
```

Type the following command and update UUID value obtained in the preview screen for each Virtual Machine to auto-start:
```shell
[root@xen ~]# xe vm-param-set uuid=d20c6c7f-e3d3-5731-48c1-9b1d8163a23c other-confi:auto_poweron=true
```

Inspiration for this article where taken from the support ticket [CTX133910](https://support.citrix.com/article/CTX133910).

