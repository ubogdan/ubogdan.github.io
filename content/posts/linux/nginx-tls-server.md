---
title: "Static website hosting with NGINX and LetsEncrypt"
description: ""
date: "2021-09-15T16:50:53+03:00"
thumbnail: ""
categories:
- "Linux"
tags:
- "linux"
- "nginx"
widgets:
- "categories"
- "taglist"
---
Static site generators are a fantastic way to manage a website. Static sites are faster and safer than dynamic sites. 
Nginx is an ideal web server for serving these static files. 

<!--more--> 

The NGINX package is not apart of standard installation packages and we need to enable epel repository.

```sh
# yum install epel-release
```

To install the NGINX server and LetsEncrypt client on the Linux distribution that supports yum, such as Fedora and CentOS, run the following command:

```sh
# yum install nginx certbot python2-certbot-nginx
```

on Ubuntu/Debian based systems you may need to run the following command
```sh
# sudo apt-get install nginx certbot python-certbot-nginx
```

Certbot can automatically configure NGINX for SSL/TLS.
It looks for and modifies the server block in your NGINX configuration that contains a server_name directive with the domain name you’re requesting a certificate for.
In our example, the domain is www.domain.ro.

```
server {
    listen 80 ;
    listen [::]:80;
    root /home/domain.ro/public_html;
    server_name example.ro www.example.ro;
}
```

The NGINX server needs to be restarted to use the web validation method.
```sh
# nginx -t && nginx -s reload
```

We are going to retrieve the first manual certificate by running the following:
```sh
# letsencrypt run -d domain.ro -d www.domain.ro
```

Adding a new record into crontab will enable automatic certificate renewals.
```sh
# crontab -e
30 3 * * *  /usr/bin/letsencrypt renew --cert-name domain.ro --post-hook "/bin/systemctl restart nginx" --quiet
```