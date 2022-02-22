---
title: "HTTP request tracing middleware"
description: ""
date: "2021-09-28T20:21:33+03:00"
thumbnail: ""
categories:
- "Programing"
tags:
- "golang"
- "middleware"
- "programming"
---

Request-based tracing provides a way to determine what exactly is happening with your requests and why.

It is handy when you want to reproduce and understand the problem that you are experiencing.

<!--more--> 

```golang
package middleware

import (
	"context"
	"net/http"
)
const RequestIDKey = "requestID"

func Tracing(nextRequestID func() string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			requestID := r.Header.Get("X-Request-Id")
			if requestID == "" {
				requestID = nextRequestID()
			}

			ctx := context.WithValue(r.Context(), RequestIDKey, requestID)
			w.Header().Set("X-Request-Id", requestID)

			next.ServeHTTP(w, r.WithContext(ctx))
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
	"github.com/google/uuid"
)

func main() {
	r := mux.NewRouter()

	nextIDfn := func() string {
	    return uuid.New().String()
	}

	r.Use(
		middleware.Tracing(nextIDfn),
	)

	http.ListenAndServe(":8080",r)
}
```