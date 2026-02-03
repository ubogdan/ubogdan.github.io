---
title: "HTTP Panic Recover Middleware"
date: 2022-02-23T21:46:46+02:00
lastmod: 2026-02-03
description: "No matter if you are creating a simple rest service or a complex one, you will need to handle panics in order to provide good resiliency."
categories:
  - "Programming"
tags:
  - "golang"
  - "http"
  - "middleware"
  - "programming"
---

No matter if you are creating a simple REST service or a complex one, you will need to handle panics to provide good resiliency and stability. Without panic recovery mechanisms in place, an uncaught panic in your HTTP handler will crash your entire server, leaving your clients without service and no meaningful error response.

<!--more-->

## Why Panic Recovery Matters

In production systems, panics can occur due to unexpected edge cases, race conditions, or programming errors that slip through testing. Without recovery middleware, a single panic in one request handler will bring down your entire application server, affecting all users. By implementing a recovery middleware, you can gracefully handle these situations, log errors with full context, and return appropriate error responses to clients.

## Understanding Go's Panic Recovery Mechanism

The Go runtime provides a built-in mechanism for recovering from panics through the `defer` statement and `recover()` function. This concept is similar to try-catch blocks in other languages, but implemented using Go's unique control flow. When combined with middleware patterns, this becomes a powerful tool for building resilient APIs.

Here's the basic principle from the go.dev [blog](https://go.dev/blog/defer-panic-and-recover):

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

If the function panics, the deferred function will always be called and the `recover()` function will return the runtime error. This allows you to execute cleanup code and prevent the panic from propagating further up the call stack.

## Common Panic Scenarios

For example, if your code tries to access the 3rd position of an empty slice, it will return: `"runtime error: index out of range [3] with length 0"`. 

However, just knowing the error message isn't always sufficient for debugging in production. You also need to know exactly where in your codebase the panic occurred—which function called which function, and so on. This is where stack traces become invaluable for rapid diagnosis and monitoring.

## Capturing the Stack Trace

To properly diagnose issues in production, we need to capture the full stack trace using the `runtime.Stack()` function. This gives you the complete call chain that led to the panic, making it exponentially easier to identify and fix the underlying issue. Stack traces should be logged in your monitoring system for later analysis.

## Implementation: Building the Recovery Middleware

Below is a production-ready implementation of panic recovery middleware that captures the full stack trace and logs it along with the panic message:

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
				
				// Send internal server error to the client
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusInternalServerError)
				w.Write([]byte(`{"error": "There was an internal server error"}`))
			}
		}()

		next.ServeHTTP(w, r)
	})
}
```

### How the Middleware Works

1. **Defer Setup**: The `defer` statement ensures the recovery block executes when the handler function exits, whether normally or via panic
2. **Stack Capture**: `runtime.Stack()` captures all goroutine stacks with full file paths and line numbers
3. **Logging**: The panic message and stack trace are logged for debugging and monitoring
4. **Client Response**: Instead of crashing, we return a clean JSON error response with an appropriate HTTP status code

## Integration with Your Router

Example using the middleware with gorilla/mux router and standard http server:

```golang
package main

import (
	"net/http"
	"github.com/some-user/some-project/pkg/http/middleware"
	"github.com/gorilla/mux"
)

func main() {
	r := mux.NewRouter()

	// Apply recovery middleware to all routes
	r.Use(
		middleware.Recover,
	)

	// Add your route handlers here
	r.HandleFunc("/api/users", handleGetUsers).Methods("GET")
	r.HandleFunc("/api/data", handleGetData).Methods("GET")

	http.ListenAndServe(":8080", r)
}
```

## Best Practices for Production

- **Always log the full stack trace** for debugging purposes in your monitoring system
- **Return consistent error responses** to clients to avoid exposing internal implementation details
- **Consider using structured logging** (like logrus or zap) for better log aggregation and searchability
- **Monitor panic occurrences** in your logging system to catch recurring issues before they escalate
- **Keep stack trace size reasonable** (4KB is sufficient for most cases and prevents memory issues)
- **Don't ignore recovered panics** - they indicate bugs that need fixing, not just hiding
- **Test your panic recovery** by intentionally triggering panics in your test suite

## Conclusion

This recovery middleware is essential for building robust Go web services that can handle unexpected errors gracefully. By combining defer/recover mechanics with proper logging and error handling, you can ensure that your application stays running and provides visibility into production issues. The combination of captured stack traces and proper error responses gives you the best of both worlds: server stability and diagnostic capability.
