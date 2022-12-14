---
title: "Improve ssh session performance by reusing an existing connection to a remote SSH server"
description: ""
date: "2022-12-12T23:50:00+03:00"
thumbnail: ""
categories:
- "Linux"
tags:
- "ssh"
widgets:
- "categories"
- "taglist"
---

When working on a remote server, it is often necessary to establish multiple Secure Shell (SSH) connections to the same host. This can be time-consuming and resource-intensive, especially if you are working on a slow or congested network. 

<!--more--> 

Fortunately, there is a way to speed up the process and reduce the load on the network by reusing an existing SSH connection. This technique is known as ControlMaster, and it allows you to use a single SSH connection for multiple terminal sessions.

To use ControlMaster, you need to have the ssh client installed on your local machine. This is typically included with most Linux and Unix-like operating systems. Once you have the ssh client installed, you can enable ControlMaster by adding the following lines to your `~/.ssh/config` file:

```shell
Host *
    ControlMaster auto
    ControlPath ~/.ssh/mux-%h_%p_%r.sock
```

If you open the first connection with -M:
```shell
ssh -M user@server
``` 
subsequent connections to remove host will "piggyback" on the connection established by the master ssh. Most noticeably, further authentication is not required. See man ssh_config under "ControlMaster" for more details.


Once you have enabled ControlMaster, you can open a new terminal session to the remote server by running the ssh command again. 
```shell
ssh user@server
``` 

In addition to the options mentioned above, there are several other options that you can use to configure the behavior of ControlMaster. For example, you can use the ControlMax option to specify the maximum number of SSH connections that can be reused by ControlMaster. 

In conclusion, ControlMaster is a useful feature of the ssh client that allows you to reuse an existing SSH connection for multiple terminal sessions. This can save time and reduce the load on the network, making it an essential tool for anyone who works on remote servers. 

By enabling ControlMaster and using the appropriate options, you can configure the ssh client to automatically reuse an existing SSH connection, and improve your productivity on the remote server.

