---
title: "Building Production-Ready HTTP Logging Middleware for Go's Mux Router"
description: ""
date: "2025-02-21T22:49:20+03:00"
thumbnail: ""
categories: ["Programming"]
tags: ["golang", "middleware", "programming"]
---

Observability is the cornerstone of modern web applications. When your API starts experiencing issues at 3 AM, comprehensive logging can mean the difference between a quick fix and hours of frustrated debugging. In this guide, we'll build a production-grade HTTP logging middleware for Gorilla Mux that goes beyond simple request logging to provide actionable insights into your application's behavior.

## Why HTTP Logging Middleware Matters

Every HTTP request tells a story. It carries information about who's accessing your system, what they're requesting, how long it takes, and whether it succeeds or fails. Without proper logging, these stories are lost, leaving you blind when problems arise.

**Effective logging middleware provides several critical benefits:**

**Debugging and Troubleshooting:** When users report issues, logs help you reconstruct exactly what happened. You can trace requests through your system, identify where failures occur, and understand the context around errors.

**Performance Monitoring:** Response time patterns reveal bottlenecks. By logging request duration, you can identify slow endpoints that need optimization before they impact user experience.

**Security and Compliance:** Logging request metadata helps detect suspicious activity patterns, meet regulatory requirements, and maintain audit trails for sensitive operations.

**Business Intelligence:** Request patterns provide insights into how users interact with your API, which features are most popular, and where users encounter friction.

The challenge lies in implementing logging that's informative without being overwhelming, performant without sacrificing detail, and flexible enough to adapt as your needs evolve.

## Prerequisites

Before diving into implementation, you should be familiar with:

- **Go basics:** Understanding of functions, interfaces, and error handling
- **HTTP fundamentals:** Knowledge of request/response cycles and status codes
- **Middleware concepts:** How middleware chains work in web frameworks
- **Gorilla Mux:** Basic familiarity with the router (though we'll cover what's necessary)

**Required packages:**

```go
go get github.com/gorilla/mux
go get github.com/google/uuid  // For request ID generation
```

This guide uses Go 1.21+, though most code works with earlier versions.

## Understanding HTTP Middleware Architecture

Before writing code, let's understand how middleware works in Go's HTTP ecosystem.

Middleware in Go follows a simple but powerful pattern: a function that takes an `http.Handler` and returns a new `http.Handler` that wraps the original. This creates a chain where each middleware can execute code before and after calling the next handler.

```go
type Middleware func(http.Handler) http.Handler
```

When a request arrives, it flows through the middleware chain like this:

1. Request enters first middleware
2. First middleware performs pre-processing
3. First middleware calls next handler
4. Request flows through remaining middleware
5. Final handler processes request
6. Response flows back through middleware in reverse
7. Each middleware can perform post-processing

This architecture allows middleware to inspect, modify, or augment both requests and responses without handlers knowing about it.

## Building a Basic Logging Middleware

Let's start with a foundational implementation that logs essential request information.

```go
package middleware

import (
    "log"
    "net/http"
    "time"
)

// LoggingMiddleware creates a middleware that logs HTTP requests
func LoggingMiddleware(logger *log.Logger) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            start := time.Now()
            
            // Log request details
            logger.Printf("[%s] %s %s from %s",
                time.Now().Format(time.RFC3339),
                r.Method,
                r.URL.Path,
                r.RemoteAddr,
            )
            
            // Call the next handler
            next.ServeHTTP(w, r)
            
            // Log completion
            duration := time.Since(start)
            logger.Printf("Completed in %v", duration)
        })
    }
}
```

This basic implementation logs when requests arrive and how long they take. However, it has limitations: we can't see response status codes, we lose context between the start and end logs, and there's no structured way to correlate related log entries.

## Capturing Response Information

To log status codes and response sizes, we need to intercept the `http.ResponseWriter`. The standard `ResponseWriter` doesn't expose what was written, so we'll create a wrapper that tracks this information.

```go
package middleware

import (
    "net/http"
)

// responseWriter wraps http.ResponseWriter to capture status code and size
type responseWriter struct {
    http.ResponseWriter
    status      int
    size        int
    wroteHeader bool
}

// newResponseWriter creates a wrapped response writer
func newResponseWriter(w http.ResponseWriter) *responseWriter {
    return &responseWriter{
        ResponseWriter: w,
        status:        http.StatusOK, // Default status
    }
}

// WriteHeader captures the status code
func (rw *responseWriter) WriteHeader(statusCode int) {
    if !rw.wroteHeader {
        rw.status = statusCode
        rw.wroteHeader = true
        rw.ResponseWriter.WriteHeader(statusCode)
    }
}

// Write captures the response size
func (rw *responseWriter) Write(b []byte) (int, error) {
    if !rw.wroteHeader {
        rw.WriteHeader(http.StatusOK)
    }
    size, err := rw.ResponseWriter.Write(b)
    rw.size += size
    return size, err
}

// Status returns the HTTP status code
func (rw *responseWriter) Status() int {
    return rw.status
}

// Size returns the response size in bytes
func (rw *responseWriter) Size() int {
    return rw.size
}
```

This wrapper implements the `http.ResponseWriter` interface while recording metadata. The `wroteHeader` flag ensures we only write headers once, following HTTP protocol requirements.

## Implementing Request ID Tracking

Request IDs are crucial for correlating log entries across distributed systems. Each request gets a unique identifier that appears in every related log entry.

```go
package middleware

import (
    "context"
    "net/http"
    
    "github.com/google/uuid"
)

type contextKey string

const requestIDKey contextKey = "requestID"

// RequestIDMiddleware adds a unique ID to each request
func RequestIDMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        // Check if request ID exists in header (for distributed tracing)
        requestID := r.Header.Get("X-Request-ID")
        if requestID == "" {
            requestID = uuid.New().String()
        }
        
        // Add request ID to response header
        w.Header().Set("X-Request-ID", requestID)
        
        // Add request ID to context
        ctx := context.WithValue(r.Context(), requestIDKey, requestID)
        
        // Call next handler with updated context
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}

// GetRequestID retrieves the request ID from context
func GetRequestID(ctx context.Context) string {
    if id, ok := ctx.Value(requestIDKey).(string); ok {
        return id
    }
    return "unknown"
}
```

This middleware checks for existing request IDs (useful in microservices), generates new ones when needed, and stores them in the request context for easy access throughout the request lifecycle.

## Creating a Production-Ready Logging Middleware

Now let's combine everything into a comprehensive, production-grade logging middleware with structured output and rich metadata.

```go
package middleware

import (
    "log"
    "net/http"
    "time"
)

// LogEntry contains structured request information
type LogEntry struct {
    RequestID  string
    Method     string
    Path       string
    Query      string
    RemoteAddr string
    UserAgent  string
    Status     int
    Size       int
    Duration   time.Duration
    Timestamp  time.Time
}

// Logger defines the interface for custom loggers
type Logger interface {
    LogRequest(entry LogEntry)
}

// DefaultLogger implements Logger using standard log package
type DefaultLogger struct {
    logger *log.Logger
}

func NewDefaultLogger(logger *log.Logger) *DefaultLogger {
    return &DefaultLogger{logger: logger}
}

func (l *DefaultLogger) LogRequest(entry LogEntry) {
    l.logger.Printf(
        "[%s] %s | %d | %s %s%s | %s | %s | %d bytes | %v",
        entry.Timestamp.Format(time.RFC3339),
        entry.RequestID,
        entry.Status,
        entry.Method,
        entry.Path,
        formatQuery(entry.Query),
        entry.RemoteAddr,
        entry.UserAgent,
        entry.Size,
        entry.Duration,
    )
}

func formatQuery(query string) string {
    if query == "" {
        return ""
    }
    return "?" + query
}

// LoggingMiddleware creates a comprehensive logging middleware
func LoggingMiddleware(logger Logger) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            start := time.Now()
            
            // Wrap the response writer to capture status and size
            wrapped := newResponseWriter(w)
            
            // Process the request
            next.ServeHTTP(wrapped, r)
            
            // Calculate duration
            duration := time.Since(start)
            
            // Create log entry
            entry := LogEntry{
                RequestID:  GetRequestID(r.Context()),
                Method:     r.Method,
                Path:       r.URL.Path,
                Query:      r.URL.RawQuery,
                RemoteAddr: r.RemoteAddr,
                UserAgent:  r.UserAgent(),
                Status:     wrapped.Status(),
                Size:       wrapped.Size(),
                Duration:   duration,
                Timestamp:  start,
            }
            
            // Log the request
            logger.LogRequest(entry)
        })
    }
}
```

This implementation provides structured logging with all essential metadata while remaining flexible through the `Logger` interface.

## Integrating with Gorilla Mux

Here's how to wire everything together in a real application:

```go
package main

import (
    "log"
    "net/http"
    "os"
    
    "github.com/gorilla/mux"
    "yourproject/middleware"
)

func main() {
    // Create logger
    logger := log.New(os.Stdout, "", log.LstdFlags)
    defaultLogger := middleware.NewDefaultLogger(logger)
    
    // Create router
    r := mux.NewRouter()
    
    // Apply middleware in order (important!)
    r.Use(middleware.RequestIDMiddleware)
    r.Use(middleware.LoggingMiddleware(defaultLogger))
    
    // Define routes
    r.HandleFunc("/api/health", healthHandler).Methods("GET")
    r.HandleFunc("/api/users", getUsersHandler).Methods("GET")
    r.HandleFunc("/api/users/{id}", getUserHandler).Methods("GET")
    r.HandleFunc("/api/users", createUserHandler).Methods("POST")
    
    // Start server
    logger.Println("Starting server on :8080")
    if err := http.ListenAndServe(":8080", r); err != nil {
        logger.Fatal("Server failed to start:", err)
    }
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte(`{"status":"healthy"}`))
}

func getUsersHandler(w http.ResponseWriter, r *http.Request) {
    // Simulate some processing time
    // In production, this would query a database
    w.Header().Set("Content-Type", "application/json")
    w.Write([]byte(`{"users":[]}`))
}

func getUserHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    userID := vars["id"]
    
    // Simulate user lookup
    w.Header().Set("Content-Type", "application/json")
    w.Write([]byte(`{"id":"` + userID + `","name":"John Doe"}`))
}

func createUserHandler(w http.ResponseWriter, r *http.Request) {
    // Validate and create user
    w.WriteHeader(http.StatusCreated)
    w.Header().Set("Content-Type", "application/json")
    w.Write([]byte(`{"id":"123","name":"Jane Doe"}`))
}
```

Notice the middleware order: `RequestIDMiddleware` runs first to establish the request ID before logging occurs.

## Best Practices

Following these practices ensures your logging middleware remains effective and maintainable:

**Use Structured Logging:** Structured logs are machine-parseable, enabling automated analysis, alerting, and searching. Consider using JSON formatting for production:

```go
import (
    "encoding/json"
    "log"
)

type JSONLogger struct {
    logger *log.Logger
}

func (l *JSONLogger) LogRequest(entry middleware.LogEntry) {
    data, _ := json.Marshal(map[string]interface{}{
        "timestamp":   entry.Timestamp,
        "request_id":  entry.RequestID,
        "method":      entry.Method,
        "path":        entry.Path,
        "status":      entry.Status,
        "duration_ms": entry.Duration.Milliseconds(),
        "size":        entry.Size,
        "remote_addr": entry.RemoteAddr,
    })
    l.logger.Println(string(data))
}
```

**Implement Log Levels:** Different environments need different verbosity. Add log levels to control what gets logged:

```go
type LogLevel int

const (
    LogLevelDebug LogLevel = iota
    LogLevelInfo
    LogLevelWarn
    LogLevelError
)

type ConfigurableLogger struct {
    logger *log.Logger
    level  LogLevel
}

func (l *ConfigurableLogger) LogRequest(entry middleware.LogEntry) {
    // Only log if status indicates an error and level permits
    if entry.Status >= 500 && l.level <= LogLevelError {
        l.logger.Printf("ERROR: %s failed with status %d", entry.Path, entry.Status)
    } else if l.level <= LogLevelInfo {
        // Log all requests at info level
        l.logger.Printf("INFO: %s completed with status %d", entry.Path, entry.Status)
    }
}
```

**Sanitize Sensitive Data:** Never log passwords, tokens, or personally identifiable information. Implement filtering:

```go
func sanitizePath(path string) string {
    // Remove tokens from paths like /api/reset-password?token=secret
    // Use regular expressions for more complex patterns
    if strings.Contains(path, "token=") {
        return strings.Split(path, "token=")[0] + "token=[REDACTED]"
    }
    return path
}

func sanitizeHeaders(headers http.Header) http.Header {
    cleaned := headers.Clone()
    sensitiveHeaders := []string{"Authorization", "Cookie", "X-API-Key"}
    for _, header := range sensitiveHeaders {
        if cleaned.Get(header) != "" {
            cleaned.Set(header, "[REDACTED]")
        }
    }
    return cleaned
}
```

**Handle Request Bodies Carefully:** Logging request bodies can be useful but risky. If you must log bodies, limit size and sanitize content:

```go
func logRequestBody(r *http.Request, maxSize int64) string {
    if r.Body == nil {
        return ""
    }
    
    // Read limited amount
    body := io.LimitReader(r.Body, maxSize)
    bytes, err := io.ReadAll(body)
    if err != nil {
        return "[error reading body]"
    }
    
    // Replace body so handler can read it
    r.Body = io.NopCloser(io.MultiReader(
        bytes.NewReader(bytes),
        r.Body,
    ))
    
    // Sanitize sensitive fields
    return sanitizeJSON(string(bytes))
}
```

**Use Context for Metadata:** Store request-scoped data in context, not global variables:

```go
func enrichContext(ctx context.Context, userID string) context.Context {
    return context.WithValue(ctx, "userID", userID)
}

// Later in logging
func (l *EnhancedLogger) LogRequest(entry middleware.LogEntry, ctx context.Context) {
    if userID, ok := ctx.Value("userID").(string); ok {
        l.logger.Printf("Request by user %s", userID)
    }
}
```

## Common Pitfalls and How to Avoid Them

**Pitfall: Logging Before Response Completion**

Logging too early misses critical information like actual status codes and response sizes.

**Solution:** Always use `defer` or log after calling `next.ServeHTTP()` to capture complete information.

**Pitfall: Not Handling Panics**

Panics in handlers can prevent logging middleware from executing.

**Solution:** Add panic recovery:

```go
func LoggingMiddleware(logger Logger) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            start := time.Now()
            wrapped := newResponseWriter(w)
            
            // Recover from panics
            defer func() {
                if err := recover(); err != nil {
                    wrapped.WriteHeader(http.StatusInternalServerError)
                    logger.LogPanic(entry, err)
                }
                
                // Log request regardless
                duration := time.Since(start)
                entry := LogEntry{
                    // ... populate entry
                }
                logger.LogRequest(entry)
            }()
            
            next.ServeHTTP(wrapped, r)
        })
    }
}
```

**Pitfall: Excessive Logging Impact on Performance**

Synchronous logging can slow down request processing, especially under high load.

**Solution:** Use asynchronous logging with buffered channels:

```go
type AsyncLogger struct {
    logChan chan LogEntry
    done    chan struct{}
    logger  *log.Logger
}

func NewAsyncLogger(logger *log.Logger, bufferSize int) *AsyncLogger {
    al := &AsyncLogger{
        logChan: make(chan LogEntry, bufferSize),
        done:    make(chan struct{}),
        logger:  logger,
    }
    go al.processLogs()
    return al
}

func (al *AsyncLogger) processLogs() {
    for {
        select {
        case entry := <-al.logChan:
            // Process log entry
            al.logger.Printf("...")
        case <-al.done:
            return
        }
    }
}

func (al *AsyncLogger) LogRequest(entry LogEntry) {
    select {
    case al.logChan <- entry:
        // Entry queued successfully
    default:
        // Buffer full, log warning
        log.Println("Warning: log buffer full, dropping entry")
    }
}

func (al *AsyncLogger) Close() {
    close(al.done)
}
```

**Pitfall: Incorrect Middleware Ordering**

Placing logging middleware in the wrong position can miss requests or log incorrect information.

**Solution:** Apply request ID middleware first, then logging, then authentication, then business logic:

```go
r.Use(middleware.RequestIDMiddleware)        // First: establish ID
r.Use(middleware.LoggingMiddleware(logger))  // Second: log all requests
r.Use(middleware.AuthMiddleware)             // Third: authenticate
r.Use(middleware.RateLimitMiddleware)        // Fourth: rate limiting
// Business routes follow
```

**Pitfall: Memory Leaks from Context**

Storing large objects in context can prevent garbage collection.

**Solution:** Store only references or small values in context:

```go
// Bad: storing entire user object
ctx = context.WithValue(ctx, "user", largeUserObject)

// Good: storing only user ID
ctx = context.WithValue(ctx, "userID", user.ID)
```

## Real-World Use Cases

**Use Case 1: Debugging Production Issues**

A customer reports intermittent 500 errors. With comprehensive logging:

```go
type DetailedLogger struct {
    logger *log.Logger
}

func (l *DetailedLogger) LogRequest(entry middleware.LogEntry) {
    // Log all 5xx errors with full details
    if entry.Status >= 500 {
        l.logger.Printf(
            "ERROR: Request %s failed | %s %s | Status: %d | Duration: %v | "+
            "RemoteAddr: %s | UserAgent: %s | Referrer: %s",
            entry.RequestID,
            entry.Method,
            entry.Path,
            entry.Status,
            entry.Duration,
            entry.RemoteAddr,
            entry.UserAgent,
            entry.Referrer,
        )
    }
}
```

You can grep logs by request ID to see the entire request lifecycle and identify the failure point.

**Use Case 2: API Rate Limiting Analysis**

Track which endpoints receive the most traffic to inform rate limiting decisions:

```go
type MetricsLogger struct {
    logger  *log.Logger
    metrics map[string]*EndpointMetrics
    mu      sync.RWMutex
}

type EndpointMetrics struct {
    Count      int64
    TotalTime  time.Duration
    ErrorCount int64
}

func (l *MetricsLogger) LogRequest(entry middleware.LogEntry) {
    l.mu.Lock()
    defer l.mu.Unlock()
    
    key := entry.Method + " " + entry.Path
    if l.metrics[key] == nil {
        l.metrics[key] = &EndpointMetrics{}
    }
    
    m := l.metrics[key]
    m.Count++
    m.TotalTime += entry.Duration
    if entry.Status >= 400 {
        m.ErrorCount++
    }
    
    // Regular logging
    l.logger.LogRequest(entry)
}

func (l *MetricsLogger) GetMetrics() map[string]*EndpointMetrics {
    l.mu.RLock()
    defer l.mu.RUnlock()
    
    // Return copy to prevent concurrent access issues
    copy := make(map[string]*EndpointMetrics)
    for k, v := range l.metrics {
        copy[k] = v
    }
    return copy
}
```

**Use Case 3: Security Monitoring**

Detect suspicious patterns like repeated authentication failures:

```go
type SecurityLogger struct {
    logger        *log.Logger
    failedLogins  map[string]int
    mu            sync.RWMutex
    alertThreshold int
}

func (l *SecurityLogger) LogRequest(entry middleware.LogEntry) {
    // Monitor authentication endpoints
    if strings.Contains(entry.Path, "/auth/login") && entry.Status == 401 {
        l.mu.Lock()
        l.failedLogins[entry.RemoteAddr]++
        count := l.failedLogins[entry.RemoteAddr]
        l.mu.Unlock()
        
        if count > l.alertThreshold {
            l.logger.Printf(
                "SECURITY ALERT: Multiple failed login attempts from %s (count: %d)",
                entry.RemoteAddr,
                count,
            )
        }
    }
    
    // Reset counter on successful login
    if strings.Contains(entry.Path, "/auth/login") && entry.Status == 200 {
        l.mu.Lock()
        delete(l.failedLogins, entry.RemoteAddr)
        l.mu.Unlock()
    }
}
```

**Use Case 4: Performance Profiling**

Identify slow endpoints that need optimization:

```go
func (l *PerformanceLogger) LogRequest(entry middleware.LogEntry) {
    threshold := 1 * time.Second
    
    if entry.Duration > threshold {
        l.logger.Printf(
            "SLOW REQUEST: %s %s took %v (threshold: %v) | RequestID: %s",
            entry.Method,
            entry.Path,
            entry.Duration,
            threshold,
            entry.RequestID,
        )
    }
}
```

## Performance Considerations

Logging adds overhead to every request. Here's how to minimize impact:

**Benchmark Your Middleware**

Always measure performance impact:

```go
func BenchmarkLoggingMiddleware(b *testing.B) {
    logger := NewDefaultLogger(log.New(io.Discard, "", 0))
    middleware := LoggingMiddleware(logger)
    
    handler := middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
    }))
    
    req := httptest.NewRequest("GET", "/test", nil)
    w := httptest.NewRecorder()
    
    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        handler.ServeHTTP(w, req)
    }
}
```

**Use Efficient Loggers**

Different logging libraries have different performance characteristics:

```go
// Standard library - simple but slower
standardLogger := log.New(os.Stdout, "", log.LstdFlags)

// zerolog - very fast structured logging
import "github.com/rs/zerolog"
zerologger := zerolog.New(os.Stdout)

// zap - also very fast
import "go.uber.org/zap"
zapLogger, _ := zap.NewProduction()
```

**Minimize String Operations**

String concatenation and formatting are expensive in hot paths:

```go
// Slower: multiple string operations
message := fmt.Sprintf("[%s] %s %s %s", time.Now(), method, path, status)

// Faster: use logger formatting
logger.Printf("[%s] %s %s %s", time.Now(), method, path, status)

// Fastest: structured logging with zero allocations
zerologger.Info().
    Str("method", method).
    Str("path", path).
    Int("status", status).
    Msg("request completed")
```

**Implement Sampling**

For extremely high-traffic APIs, log only a percentage of successful requests:

```go
type SamplingLogger struct {
    logger     Logger
    sampleRate float64 // 0.0 to 1.0
}

func (l *SamplingLogger) LogRequest(entry middleware.LogEntry) {
    // Always log errors
    if entry.Status >= 400 {
        l.logger.LogRequest(entry)
        return
    }
    
    // Sample successful requests
    if rand.Float64() < l.sampleRate {
        l.logger.LogRequest(entry)
    }
}
```

**Use Buffered Writers**

Reduce I/O operations by buffering log output:

```go
import "bufio"

func NewBufferedLogger(w io.Writer) *log.Logger {
    bufWriter := bufio.NewWriterSize(w, 32*1024) // 32KB buffer
    
    // Flush periodically
    go func() {
        ticker := time.NewTicker(5 * time.Second)
        for range ticker.C {
            bufWriter.Flush()
        }
    }()
    
    return log.New(bufWriter, "", log.LstdFlags)
}
```

## Testing Approach

Comprehensive tests ensure your middleware works correctly across scenarios:

**Unit Tests for Response Writer**

```go
package middleware

import (
    "net/http"
    "net/http/httptest"
    "testing"
)

func TestResponseWriter_Status(t *testing.T) {
    w := httptest.NewRecorder()
    wrapped := newResponseWriter(w)
    
    wrapped.WriteHeader(http.StatusNotFound)
    
    if wrapped.Status() != http.StatusNotFound {
        t.Errorf("Expected status %d, got %d", http.StatusNotFound, wrapped.Status())
    }
}

func TestResponseWriter_Size(t *testing.T) {
    w := httptest.NewRecorder()
    wrapped := newResponseWriter(w)
    
    data := []byte("Hello, World!")
    wrapped.Write(data)
    
    if wrapped.Size() != len(data) {
        t.Errorf("Expected size %d, got %d", len(data), wrapped.Size())
    }
}

func TestResponseWriter_DefaultStatus(t *testing.T) {
    w := httptest.NewRecorder()
    wrapped := newResponseWriter(w)
    
    // Writing without explicit WriteHeader should default to 200
    wrapped.Write([]byte("data"))
    
    if wrapped.Status() != http.StatusOK {
        t.Errorf("Expected default status %d, got %d", http.StatusOK, wrapped.Status())
    }
}
```

**Integration Tests for Middleware**

```go
func TestLoggingMiddleware(t *testing.T) {
    var loggedEntry LogEntry
    
    // Mock logger that captures log entries
    mockLogger := &MockLogger{
        logFunc: func(entry LogEntry) {
            loggedEntry = entry
        },
    }
    
    // Create middleware
    middleware := LoggingMiddleware(mockLogger)
    
    // Create test handler
    handler := middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusCreated)
        w.Write([]byte("Created"))
    }))
    
    // Create test request
    req := httptest.NewRequest("POST", "/api/users?name=test", nil)
    req.Header.Set("User-Agent", "Test-Agent")
    ctx := context.WithValue(req.Context(), requestIDKey, "test-123")
    req = req.WithContext(ctx)
    
    w := httptest.NewRecorder()
    
    // Execute request
    handler.ServeHTTP(w, req)
    
    // Verify logged entry
    if loggedEntry.RequestID != "test-123" {
        t.Errorf("Expected request ID %s, got %s", "test-123", loggedEntry.RequestID)
    }
    
    if loggedEntry.Method != "POST" {
        t.Errorf("Expected method POST, got %s", loggedEntry.Method)
    }
    
    if loggedEntry.Status != http.StatusCreated {
        t.Errorf("Expected status %d, got %d", http.StatusCreated, loggedEntry.Status)
    }
    
    if loggedEntry.Size != 7 { // len("Created")
        t.Errorf("Expected size 7, got %d", loggedEntry.Size)
    }
    
    if loggedEntry.Path != "/api/users" {
        t.Errorf("Expected path /api/users, got %s", loggedEntry.Path)
    }
    
    if loggedEntry.Query != "name=test" {
        t.Errorf("Expected query name=test, got %s", loggedEntry.Query)
    }
}

type MockLogger struct {
    logFunc func(LogEntry)
}

func (m *MockLogger) LogRequest(entry LogEntry) {
    if m.logFunc != nil {
        m.logFunc(entry)
    }
}
```

**Testing Middleware Chain Order**

```go
func TestMiddlewareOrder(t *testing.T) {
    var executionOrder []string
    
    // Create tracking middleware
    trackingMiddleware := func(name string) func(http.Handler) http.Handler {
        return func(next http.Handler) http.Handler {
            return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                executionOrder = append(executionOrder, name+"-before")
                next.ServeHTTP(w, r)
                executionOrder = append(executionOrder, name+"-after")
            })
        }
    }
    
    // Create router with middleware
    r := mux.NewRouter()
    r.Use(trackingMiddleware("first"))
    r.Use(trackingMiddleware("second"))
    r.HandleFunc("/test", func(w http.ResponseWriter, r *http.Request) {
        executionOrder = append(executionOrder, "handler")
        w.WriteHeader(http.StatusOK)
    })
    
    // Execute request
    req := httptest.NewRequest("GET", "/test", nil)
    w := httptest.NewRecorder()
    r.ServeHTTP(w, req)
    
    // Verify order
    expected := []string{
        "first-before",
        "second-before",
        "handler",
        "second-after",
        "first-after",
    }
    
    if !reflect.DeepEqual(executionOrder, expected) {
        t.Errorf("Expected order %v, got %v", expected, executionOrder)
    }
}
```

**Performance Tests**

```go
func TestLoggingMiddleware_Performance(t *testing.T) {
    logger := NewDefaultLogger(log.New(io.Discard, "", 0))
    middleware := LoggingMiddleware(logger)
    
    handler := middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        w.Write([]byte("OK"))
    }))
    
    req := httptest.NewRequest("GET", "/test", nil)
    
    // Warm up
    for i := 0; i < 100; i++ {
        w := httptest.NewRecorder()
        handler.ServeHTTP(w, req)
    }
    
    // Measure
    start := time.Now()
    iterations := 10000
    for i := 0; i < iterations; i++ {
        w := httptest.NewRecorder()
        handler.ServeHTTP(w, req)
    }
    duration := time.Since(start)
    
    avgDuration := duration / time.Duration(iterations)
    
    // Assert reasonable performance (adjust threshold as needed)
    maxAllowedDuration := 100 * time.Microsecond
    if avgDuration > maxAllowedDuration {
        t.Errorf("Average request duration %v exceeds maximum %v", avgDuration, maxAllowedDuration)
    }
    
    t.Logf("Average duration per request: %v", avgDuration)
}
```

## Conclusion

HTTP logging middleware is a fundamental building block of observable web applications. We've built a production-ready solution that goes beyond basic request logging to provide comprehensive insights into application behavior.

**Key takeaways:**

- **Structure matters:** Use consistent, parseable log formats that support automated analysis
- **Context is crucial:** Request IDs enable tracing requests across distributed systems
- **Capture complete information:** Wrap response writers to log status codes and sizes
- **Performance counts:** Use asynchronous logging and sampling for high-traffic applications
- **Security first:** Never log sensitive data, always sanitize before recording
- **Test thoroughly:** Unit and integration tests ensure middleware works correctly
- **Monitor continuously:** Use logs to detect issues, track performance, and understand usage

The middleware patterns shown here extend beyond logging. You can apply these techniques to authentication, rate limiting, request tracing, and more. Each middleware wraps handlers to add cross-cutting concerns without cluttering business logic.

As your application grows, consider moving to specialized observability platforms like Prometheus, Grafana, or DataDog, but the foundation we've built here will serve you well regardless of which tools you adopt later.

## Additional Resources

**Libraries and Tools:**

- [Gorilla Mux Documentation](https://github.com/gorilla/mux) - Official router documentation
- [zerolog](https://github.com/rs/zerolog) - High-performance structured logging
- [zap](https://github.com/uber-go/zap) - Uber's fast, structured logging library
- [httptest](https://pkg.go.dev/net/http/httptest) - Testing utilities for HTTP handlers

**Further Reading:**

- [Effective Go](https://go.dev/doc/effective_go) - Go programming best practices
- [The Twelve-Factor App](https://12factor.net/) - Logging and observability principles
- [Go Proverbs](https://go-proverbs.github.io/) - Including "Don't just check errors, handle them gracefully"
- [HTTP RFC 2616](https://www.rfc-editor.org/rfc/rfc2616) - HTTP protocol specification

**Advanced Topics:**

- Distributed tracing with OpenTelemetry
- Log aggregation with ELK stack (Elasticsearch, Logstash, Kibana)
- Structured logging best practices
- Production debugging techniques
- Building observable microservices

**Community Resources:**

- [r/golang](https://reddit.com/r/golang) - Active Go community
- [Gophers Slack](https://gophers.slack.com/) - Real-time Go discussions
- [Go Forum](https://forum.golangbridge.org/) - Question and answer community

## Read More

This article is an expanded and enhanced version of the original guide. For more information about production-ready HTTP middleware patterns in Go, check out:

**[Writing a Logger Middleware for Use with Mux Router](https://ubogdan.com/2023/01/writing-a-logger-middleware-for-use-with-mux-router/)** - The original article that inspired this comprehensive guide, providing a concise introduction to logging middleware fundamentals with Gorilla Mux.