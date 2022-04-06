---
title: "Cheat-Utility"
description: ""
date: "2022-04-01T20:33:39+03:00"
thumbnail: ""
categories:
- "linux"
tags:
- "cheatsheet"
widgets:
- "categories"
- "taglist"
---

It is often helpful to have a quick reference to a set of commands in a development environment.
Some of them are hard to remember because they are not very common.

<!--more--> 

Fortunately, some guy identified this need and created a cheat-sheet utility for Linux commands called [cheat](https://github.com/cheat/cheat).

Installing the utility

```bash
wget -c https://github.com/cheat/cheat/releases/download/4.2.3/cheat-linux-amd64.gz -O - | gunzip -d > /tmp/cheat
sudo mv /tmp/cheat /usr/local/bin/cheat
sudo chmod +x /usr/local/bin/cheat
```

Initializing the application

```bash
```shell
$ cheat
A config file was not found. Would you like to create one now? [Y/n]: y
Would you like to download the community cheatsheets? [Y/n]: y
Cloning into '/home/user/.config/cheat/cheatsheets/community'...
remote: Enumerating objects: 1118, done.
remote: Counting objects: 100% (278/278), done.
remote: Compressing objects: 100% (33/33), done.
remote: Total 1118 (delta 256), reused 245 (delta 245), pack-reused 840
Receiving objects: 100% (1118/1118), 284.04 KiB | 2.45 MiB/s, done.
Resolving deltas: 100% (491/491), done.
Created config file: /home/user/.config/cheat/conf.yml
Please read this file for advanced configuration information.
```

Using the utility

```bash
$ cheat curl
# To download a file:
curl <url>

# To download and rename a file:
curl <url> -o <outfile>

--- truncated output ---
 
```shell