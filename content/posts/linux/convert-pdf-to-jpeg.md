---
title: "Convert PDF to JPEG"
description: ""
date: "2023-04-03T13:30:00+03:00"
thumbnail: ""
categories:
- "Linux"
tags:
- "linux"
- "tools"
widgets:
- "categories"
- "taglist"
---

I know there are allot of online tools that allows you to convert PDF to JPG. For confidential reasons I prefer to do it locally on my machine. 

<!--more--> 

In this case you can use the pdftoppm command line tool.
```sh
$ pdftoppm -jpeg -r 300 document.pdf document
```
The -jpeg sets the output image format to JPG, -r 300 sets the output image resolution to 300 DPI, and the word output will be the prefix to all pages of images, which will be numbered and placed into your current directory you are working in.

![DHCP Communication](/images/pdftoppm.png 'pdf to ppm output')
