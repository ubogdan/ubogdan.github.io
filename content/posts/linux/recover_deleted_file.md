---
title: "How to recover a deleted file when a process keeps it open."
description: ""
date: "2021-07-22T20:44:10+03:00"
thumbnail: ""
categories:
- "Linux"
tags:
- "linux"
- "recovery"
widgets:
- "categories"
- "taglist"
---

We all make small mistakes every day. Unfortunately, some of these mistakes are unforgivable because we end up destroying or losing data for various reasons.

<!--more--> 

The most common mistake is when we intend to select a few files for deletion even by using the keyboard in a GUI environment or even better by using a wildcard pattern match.

A few days ago, I went through a similar experience when I accidentally deleted an SQLite database used by a running Linux process.

In normal circumstances, the recovery of the deleted files requires bringing the server offline to have exclusive access to the file system.

Today I will like to share a simple way to recover deleted files that are kept open by any Linux process.

First, we need to identify the PID of the running process by using the ps command
```shell
# ps -ax | grep webapp
45783 ?        Ssl    0:09 webapp
48992 pts/0    S+     0:00 grep --color=auto net
```

After that we need to check if the file is still in use.
```shell
# ls -al /proc/`pidof webapp`/fd
total 0
dr-x------ 2 webuser webuser  0 Jul 22 21:23 .
dr-xr-xr-x 9 webuser webuser  0 Jul 21 14:47 ..
lrwx------ 1 webuser webuser 64 Jul 22 21:23 0 -> /opt/webapp/var/logs/webapp.log
lrwx------ 1 webuser webuser 64 Jul 22 21:23 1 -> socket:[63385037]
lrwx------ 1 webuser webuser 64 Jul 22 21:23 2 -> socket:[63385037]
lrwx------ 1 webuser webuser 64 Jul 22 21:23 3 -> anon_inode:[eventpoll]
lr-x------ 1 webuser webuser 64 Jul 22 21:23 4 -> pipe:[63385046]
l-wx------ 1 webuser webuser 64 Jul 22 21:23 5 -> pipe:[63385046]
lrwx------ 1 webuser webuser 64 Jul 22 21:23 6 -> /opt/webapp/var/logs/access.log
lrwx------ 1 webuser webuser 64 Jul 22 21:23 7 -> /opt/webapp/var/database.sqlite (deleted)
lrwx------ 1 webuser webuser 64 Jul 22 21:23 8 -> socket:[63385378]
lrwx------ 1 webuser webuser 64 Jul 22 21:23 9 -> socket:[63384126]
``` 
As you may see proc file system confirms that file database.sqlite file is still open and deleted from the disk.

To recover the file, we need the inode where the file was stored, which can be retrieved using the lsoff command.
```shell
# lsof -p `pidof webapp` | grep database.sqlite
webapp 49057 webuser    7u      REG                8,3   237568  3674442 /opt/webapp/var/database.sqlite
```

In our case, the inode is `3674442,` and we will use this to recover the file using debugfs.  In the current scenario, the opt folder is part of the `/` (root) partition, the second partition.
```shell
# debugfs -w /dev/sda2
debugfs: cd /opt/webapp/var

debugfs: ln <3674442> database.backup

debugfs: mi database.backup
  Mode    [0100600]
  User ID    [0]
  Group ID    [0]
  Size    [3181271]
  Creation time    [1375916400]
  Modification time    [1375916322]
  Access time    [1375939901]
  Deletion time    [9601027] 0
  Link count    [0] 1
  Block count    [6232]
  File flags    [0x0]
...snip...

debugfs:  q
```

Before using this file we want to ensure we can that the recovered file is not corrupt so we can run an integrity check or even a `.dump` to check its content.
```shell
# sqlite3 /opt/webapp/var/database.backup 
SQLite version 3.7.17 2013-05-20 00:56:22
Enter ".help" for instructions
Enter SQL statements terminated with a ";"
sqlite> pragma integrity_check;
ok
sqlite> .q
```

And the final step is to rename the file to it's original name and to set the right file perms before restarting the running proccess.
```shell
# cp /opt/webapp/var/database.backup /opt/webapp/var/database.sqlite 
# chown webuser:webuser /opt/webapp/var/database.sqlite 
# systemctl restart webapp
```

I hope you won't need to use this procedure in a real-life scenario, and you are reading this article out of pure curiosity.

