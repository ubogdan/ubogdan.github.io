---
title: "HTTP Panic Recover Middleware"
description: ""
date: "2022-02-23T21:46:46+02:00"
thumbnail: ""
categories:
- "Programing"
tags:
- "golang"
- "middleware"
- "programming"
---

No mater if you are creating a simple rest service or a complex one, you will need to handle panics in order to provide a good resiliency.

<!--more--> 

The middleware has a similar behavior to the panic recovery mechanism example from the go.dev [blog](https://go.dev/blog/defer-panic-and-recover).
```go
func main() {
    defer func() {
        if err := recover(); err != nil {
            log.Println("Recovered from panic:", err)
        }
    }()
    panic("Something went wrong")
}
```

If the function panics, the defer function will be called and the recover function will return the runtime error. 

As example, if your code is trying to access the 3'rd position of an empty slice will return the following error: "runtime error: index out of range [3] with length 0".

For sure this information is not enough, and we may want to know where in the code the panic has been triggered.

For this we will have to call the stack function to get the stack trace.

```go
package middlewares

import (
	"log"
	"net/http"
	"runtime"
)

func Recover(next http.Handler) http.Handler {
	const StackSize = 4 << 10 // 4 KB
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				// Capture the stack trace
				stack := make([]byte, StackSize)
				length := runtime.Stack(stack, true)
				stack = stack[:length]
				log.Printf("[PANIC RECOVER] %v %s\n", err, stack[:length])
				
				//	Send internal server error to the client
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusInternalServerError)
				w.Write([]byte(`{"error": "There was an internal server error"}`))
			}
		}()

		next.ServeHTTP(w, r)
	})
}
```

Example using the middleware with mux router and standard http server.
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
		middleware.Recover,
	)

	http.ListenAndServe(":8080",r)
}
```