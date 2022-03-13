---
title: "Install and configure a tftp server"
description: ""
date: "2021-09-06T18:27:37+03:00"
thumbnail: ""
categories:
- "Linux"
tags:
- "linux"
- "tftp"
widgets:
- "categories"
- "taglist"
---

TFTP (Trivial File Transfer Protocol) is a simplified version of FTP (File Transfer Protocol). It was designed to be easy and simple. TFTP leaves out many authentication features of FTP and it runs on UDP port 69. As it is very lightweight, it is still used for different purposes.

<!--more--> 

To install the TFTP server on the Linux distribution that supports yum, such as Fedora and CentOS, run the following command:
```sh
# yum install xinetd tftp-server tftp
```

on Ubuntu/Debian based systems you may need to run the following command
```sh
# sudo apt-get install xinetd tftpd tftp
```

After the installation, you will need to configure the TFTP server. This server runs from the super-server xinetd and has a service configuration file in the /etc/xinetd.d directory.
The file in the /etc/xinetd.d directory is usually installed with a TFTP server. But if the file in /etc/xinetd.d is missing, you can create the file or record using your favorite text editor.
An example of a file (named /etc/xinetd.d/tftp) is provided below:

```
# default: off
# description: The tftp server serves files using the trivial file transfer \
#	protocol.  The tftp protocol is often used to boot diskless \
#	workstations, download configuration files to network-aware printers, \
#	and to start the installation process for some operating systems.
service tftp
{
	socket_type		= dgram
	protocol		= udp
	bind			= 10.0.0.1
	wait			= yes
	user			= nobody
	server			= /usr/sbin/in.tftpd
	server_args		= /tftpboot
	disable			= true
	per_source		= 11
	cps			    = 100 2
	flags			= IPv4
}
```


In the event the tftpboot folder is missing, we need to create it with the proper permissions.
```sh
# sudo mkdir /tftpboot
# sudo chmod -R 775 /tftpboot
# sudo chown -R nobody:nobody /tftpboot
```

By default, the TFTP server is disabled and this line looks like disable = yes. To enable it, change the line to disable = no (highlighted in red). After saving the changes in the file, restart xinetd with the following command:
```sh
# /etc/init.d/xinetd restart
```
or
```sh
# systemctl restart xinetd
```

To test the TFTP server, you can create a dummy text file ussing the following command `touch /tftpboot/test`. Using a computer with Linux, open shell and execute the following command:
```sh
# tftp  -c get ls
```
If the TFTP server works, the command will not return any output and the file `test` should appear in the current directory.

