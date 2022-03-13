---
title: "Connect to remote website using socks5 proxy"
description: ""
date: "2021-10-13T23:57:09+03:00"
thumbnail: ""
categories:
- "Programing"
tags:
- "programming"
- "golang"
widgets:
- "categories"
- "taglist"
---

Businesses use the SOCKS5 proxy all of the time, mostly for security purposes. Since security is a major point of any data-driven organization, including a SOCKS5 proxy could significantly ramp up the digital security of the company’s data.

Besides securing their data, it can restrict access to particular digital services through advanced authentication, which is completely optional and comes as a courtesy of SOCKS5.

<!--more--> 

What is a SOCKS5 Proxy?
----------------------
The SOCKS5 proxy is a proxy that works to exchange network packets between the user that is requesting information from a server and the server itself. 

SOCKS5 provides optional authentication features that ensure that the person requesting the information from the server is an actual person rather than a bot looking to harvest, roam, or overload the server. Another thing that makes SOCKS5 stand out is its unmatched adaptability, as it’s able to work with other protocols such as HTTP, SMTP, and FTP.

How They Work
-------------
SOCKS5 proxies work in a surprisingly simple-to-comprehend way. When a client makes a request, the SOCKS5 proxy will create a TCP (Transmission Control Protocol) to another server locked behind a firewall and then exchange network packets between the client and the server.

The whole process is secure, simple, and swift – allowing the user to seamlessly browse and surf while the SOCKS5 proxy works behind closed doors.

In more technical terms, a SOCKS5 proxy is tasked with relaying the UDP and TCP of the client over a firewall to exchange data network packets between the two parties. This means that the client never has any direct connection to the server.


SOCKS5 is also one of the fastest proxies on the market because it uses smaller data packets, meaning that it allows large-scale businesses to do their deeds at a much quicker rate, which is crucial for augmenting things such as download speeds.

Using it programmatically
-------------------------
Recent versions of Go also have SOCKS5 proxy support via the HTTP_PROXY/HTTPS_PROXY environment variable.
You would write your http.Client code as usual, then just set the environment variable at runtime, for example:
```shell
HTTPs_PROXY="socks5://user:pass@127.0.0.1:1080/" ./goApplication
```

The standard http client usage is straight forward:
```go
package main

import (
	"io/ioutil"
	"log"
	"net/http"
)

func main() {
	var client http.Client

	res, err := client.Get("https://ifconfig.co/ip")
	if err != nil {
		log.Fatalf("http.GET failed:%s", err)
	}
	defer res.Body.Close()

	ip, err := ioutil.ReadAll(res.Body)
	if err != nil {
		log.Fatalf("ioutil.Read failed %s", err)
	}

	log.Printf("IP %s", ip)
}

```

This approach may be handy because it doesn't require an application rewrite but may become inconvenient if you need to change the proxy address at runtime.

Additionally to the code below, we need to add an HTTP transport implementation. For this we will use the SOCKS5 implementation from `golang.org/x/net/proxy` package.

The dialer definition looks like this:
```go
func SOCKS5(network, addr string, auth *Auth, forward Dialer) (Dialer, error)
```

A working example of using socks5 client proxy with auth:
```go
package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"

	"golang.org/x/net/proxy"
)

func main() {
	auth := proxy.Auth{
		User:     os.Getenv("PROXY_USERNAME"),
		Password: os.Getenv("PROXY_PASSWORD"),
	}

	dialer, err := proxy.SOCKS5("tcp", os.Getenv("PROXY_ADDRESS"), &auth, proxy.Direct)
	if err != nil {
		fmt.Fprintln(os.Stderr, "can't connect to the proxy:", err)
	}

	var client http.Client

	client.Transport = http.Transport{
		Dial: dialer.Dial,
	}

	res, err := client.Get("https://ifconfig.co/ip")
	if err != nil {
		log.Fatalf("http.GET failed:%s", err)
	}
	defer res.Body.Close()

	ip, err := ioutil.ReadAll(res.Body)
	if err != nil {
		log.Fatalf("ioutil.Read failed %s", err)
	}

	log.Printf("IP %s", ip)
}

```