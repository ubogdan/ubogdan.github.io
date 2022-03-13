---
title: "Fixed: Windows 2019 stuck on boot menu"
description: ""
date: "2021-11-23T22:39:07+02:00"
thumbnail: ""
categories:
- "Windows"
tags:
- "windows"
widgets:
- "categories"
- "taglist"
---

We have a couple of issues with Windows 2019 refusing to boot after installing Hyper-V role and performing Windows updates.

It looks like it's stuck on the boot menu waiting for someone to hit enter.

<!--more--> 

![Windows Bootloader](/images/win2k9-bootloader.png 'Windows bootloader')

The bootloader is a program that runs before Windows starts. It is responsible for loading the operating system and initializing the hardware.

In the beginning, we suspected the issue was caused by some Windows feature update.

We tried different things like the System File Checker tool to repair missing or corrupted system files, but it didn't work.
```cmd
sfc /scannow
```

Finally, we figured out a way to enable and disable the bootloader prompt by using the bcdedit command.

Run the following command under using Administrator privileges:
```cmd
bcdedit /set {bootmgr} displaybootmenu no
```
