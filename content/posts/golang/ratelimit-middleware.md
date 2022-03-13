---
title: "IP Based rate-limit middleware using go.uber.org/ratelimit"
description: ""
date: "2021-09-04T02:06:57+03:00"
thumbnail: ""
categories:
- "Programing"
tags:
- "golang"
- "middleware"
- "programming"
widgets:
- "categories"
- "taglist"
---

If you're running a HTTP server and want to rate limit user requests, and most of the frameworks are providing their own middleware.

But if you want something simple and lightweight – or just want to learn – it's not too difficult to roll your own middleware to handle rate limiting.

<!--more--> 

In this post I'll run through the essentials of how to do that by using the go.uber.org/ratelimit package, which provides a leaky bucket rate-limiter algorithm.

A straightforward way to do this is to create a map of rate limiters, using the remote address as the map key. But we are going to play arround sync.Map implementation.

The map key is represented by the host value extracted from the request.RemoteAddr is shown below.
```golang
host, _, err := net.SplitHostPort(r.RemoteAddr)
if err != nil {
    http.Error(w, fmt.Sprintf("invalid RemoteAddr: %s", err), http.StatusInternalServerError)
}
```

After that, we will try to retrieve the rate limit instance from the map. If there is no key for the remote IP, we will create a new rate-limit instance.
```golang
lif, ok := lmap.Load(host)
if !ok {
    lif = ratelimit.New(rate)
}
```

The sync.Map returns an interface{} so we need to do a typecast in order to have access to the methods provided by rate-limit implementation.
```golang
lm , ok := lif.(ratelimit.Limiter)
```

The final step is to consume one unit from the bucket and store it back into the map. We will save it back on the map first because we want to make it available for future HTTP requests asap.
```golang
lmap.Store(host, lm)
lm.Take()
```

The `lm.Take` function will block until the request rate does conform to the rates setup on the bucket.

The full implementation of the middleware.
```golang
package middleware

import (
	"fmt"
	"net"
	"net/http"
	"sync"

	"go.uber.org/ratelimit"
)

// RateLimit middleware.
func RateLimit(rate int) func(next http.Handler) http.Handler {
	var lmap sync.Map

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			host, _, err := net.SplitHostPort(r.RemoteAddr)
			if err != nil {
				http.Error(w, fmt.Sprintf("invalid RemoteAddr: %s", err), http.StatusInternalServerError)

				return
			}

			lif, ok := lmap.Load(host)
			if !ok {
				lif = ratelimit.New(rate)
			}

			lm , ok := lif.(ratelimit.Limiter)
			if !ok {
			    http.Error(w, "internal middleware error: typecast failed", http.StatusInternalServerError)

			    return
			}

			lm.Take()
			lmap.Store(host, lm)

			next.ServeHTTP(w, r)
		})
	}
}
```

Example using the middleware with mux router and standard http package.

```golang
package main

import (
	"net/http"
	"github.com/some-user/some-project/pkg/http/middleware"
	"github.com/gorilla/mux"
)

func main() {
	r := mux.NewRouter()
	r.Use(
		middleware.RateLimit(10), // 10 requests/second
	)

	http.ListenAndServe(":8080",r)
}
```

