---
title: "API Security in Go: Rate Limiting, JWT Authentication, and RBAC"
date: 2025-11-02T08:52:09+02:00
tags: ["api-security", "golang", "jwt", "rbac", "authentication", "authorization"]
categories: ["SecOps"]
description: "Build production-ready API security with practical examples of rate limiting, JWT authentication, and role-based access control in Go."
series: "Security Operations"
---

## Introduction

API security isn't optional—it's fundamental. According to the 2023 State of API Security Report, 94% of organizations experienced API security incidents, with exposed APIs becoming the primary attack vector for data breaches. As APIs power everything from mobile apps to microservices architectures, a single vulnerability can cascade into system-wide failures, data leaks, or complete service disruption.

Go's combination of simplicity, performance, and robust concurrency makes it ideal for building secure APIs. Unlike heavyweight frameworks that hide security behind abstraction layers, Go empowers developers to implement security measures explicitly, providing complete control and deep understanding of every protection mechanism.

This comprehensive guide walks you through implementing three critical security layers: rate limiting to prevent abuse, JWT-based authentication for stateless identity verification, and role-based authorization for granular access control. You'll build production-ready implementations with complete, working examples that you can deploy immediately.

## What You'll Learn

By the end of this guide, you'll be able to:

- Implement token bucket rate limiting with concurrent request handling
- Build a complete JWT authentication system with refresh tokens
- Create flexible RBAC systems with hierarchical permissions
- Test security implementations effectively
- Optimize performance while maintaining security
- Avoid common security pitfalls and vulnerabilities

## Prerequisites

Before diving in, ensure you have:

- **Go 1.19+** installed on your system
- **Solid Go fundamentals**: goroutines, channels, interfaces, and HTTP handling
- **HTTP/REST knowledge**: methods, status codes, headers, and middleware patterns
- **Security basics**: understanding of tokens, hashing, encryption, and access control
- **Database familiarity**: SQL concepts and Go's `database/sql` package

We'll use popular packages like `gorilla/mux` for routing, `golang-jwt/jwt` for tokens, and `golang.org/x/crypto` for secure hashing.

## Understanding API Security Fundamentals

### The Security Triad

Think of API security as a three-layered defense system:

**Rate Limiting** is your perimeter defense. It prevents both accidental overuse and deliberate attacks like DDoS or brute force credential stuffing. Without rate limiting, a single malicious actor can overwhelm your infrastructure, causing service degradation or complete outages for all users.

**Authentication** is your identity checkpoint. It verifies that users are who they claim to be by validating credentials and issuing cryptographically signed tokens. Modern APIs use JWT (JSON Web Tokens) for stateless, scalable authentication that works seamlessly across distributed systems.

**Authorization** is your access control gate. Even authenticated users shouldn't access everything. RBAC (Role-Based Access Control) ensures users can only perform actions appropriate to their role—whether they're administrators, managers, or regular users—and can only access resources they own or have explicit permission to view.

### Common Attack Vectors

Understanding threats helps build better defenses:

**Brute Force Attacks** attempt thousands of login combinations to guess credentials. Rate limiting combined with account lockout mechanisms provide primary defense.

**DDoS Attacks** flood servers with requests to cause service disruption. Distributed rate limiting and traffic analysis help identify and mitigate these attacks.

**Token Hijacking** occurs when attackers steal JWT tokens from compromised clients. Short token lifespans, secure storage, and refresh token rotation limit exposure.

**Privilege Escalation** happens when users manipulate requests to access unauthorized resources. Proper RBAC implementation with server-side validation prevents this.

**API Enumeration** involves discovering hidden endpoints through systematic probing. Rate limiting and proper error handling make enumeration impractical.

## Implementing Production-Ready Rate Limiting

Rate limiting protects your API from abuse while ensuring fair resource allocation. We'll implement a token bucket algorithm—one of the most effective rate limiting strategies.

### Token Bucket Algorithm Explained

The token bucket algorithm allows burst traffic while maintaining average rate limits. Imagine a bucket that:
- Holds tokens up to a maximum capacity
- Refills at a steady rate
- Requires consuming a token for each request
- Rejects requests when empty

This provides smooth rate limiting with burst tolerance—perfect for real-world API usage patterns.

### Complete Implementation

```go
package ratelimit

import (
    "fmt"
    "net/http"
    "sync"
    "time"
)

// TokenBucket implements the token bucket rate limiting algorithm
type TokenBucket struct {
    tokens         float64
    capacity       float64
    refillRate     float64 // tokens per second
    lastRefillTime time.Time
    mutex          sync.Mutex
}

// NewTokenBucket creates a token bucket with specified capacity and refill rate
// capacity: maximum number of tokens (burst size)
// refillRate: tokens added per second (sustained rate)
func NewTokenBucket(capacity, refillRate float64) *TokenBucket {
    return &TokenBucket{
        tokens:         capacity,
        capacity:       capacity,
        refillRate:     refillRate,
        lastRefillTime: time.Now(),
    }
}

// TryConsume attempts to consume tokens from the bucket
func (tb *TokenBucket) TryConsume(tokens float64) bool {
    tb.mutex.Lock()
    defer tb.mutex.Unlock()

    // Refill tokens based on elapsed time
    now := time.Now()
    elapsed := now.Sub(tb.lastRefillTime).Seconds()
    tokensToAdd := elapsed * tb.refillRate

    if tokensToAdd > 0 {
        tb.tokens = min(tb.capacity, tb.tokens+tokensToAdd)
        tb.lastRefillTime = now
    }

    // Check if we have enough tokens
    if tb.tokens >= tokens {
        tb.tokens -= tokens
        return true
    }

    return false
}

// GetRemainingTokens returns the current number of available tokens
func (tb *TokenBucket) GetRemainingTokens() float64 {
    tb.mutex.Lock()
    defer tb.mutex.Unlock()
    return tb.tokens
}

// RateLimiter manages rate limiting for multiple clients
type RateLimiter struct {
    buckets         map[string]*TokenBucket
    mutex           sync.RWMutex
    capacity        float64
    refillRate      float64
    cleanupInterval time.Duration
}

// NewRateLimiter creates a rate limiter with cleanup goroutine
func NewRateLimiter(capacity, refillRate float64, cleanupInterval time.Duration) *RateLimiter {
    rl := &RateLimiter{
        buckets:         make(map[string]*TokenBucket),
        capacity:        capacity,
        refillRate:      refillRate,
        cleanupInterval: cleanupInterval,
    }

    // Start cleanup goroutine to prevent memory leaks
    go rl.cleanupInactiveBuckets()

    return rl
}

// IsAllowed checks if a request is allowed for the given identifier
func (rl *RateLimiter) IsAllowed(identifier string) (bool, float64) {
    rl.mutex.RLock()
    bucket, exists := rl.buckets[identifier]
    rl.mutex.RUnlock()

    if !exists {
        rl.mutex.Lock()
        // Double-check locking pattern
        bucket, exists = rl.buckets[identifier]
        if !exists {
            bucket = NewTokenBucket(rl.capacity, rl.refillRate)
            rl.buckets[identifier] = bucket
        }
        rl.mutex.Unlock()
    }

    allowed := bucket.TryConsume(1)
    remaining := bucket.GetRemainingTokens()
    return allowed, remaining
}

// cleanupInactiveBuckets removes old buckets to prevent memory leaks
func (rl *RateLimiter) cleanupInactiveBuckets() {
    ticker := time.NewTicker(rl.cleanupInterval)
    defer ticker.Stop()

    for range ticker.C {
        rl.mutex.Lock()
        for key, bucket := range rl.buckets {
            // Remove buckets that are full (inactive for a while)
            if bucket.GetRemainingTokens() >= rl.capacity {
                delete(rl.buckets, key)
            }
        }
        rl.mutex.Unlock()
    }
}

// RateLimitMiddleware creates HTTP middleware for rate limiting
func (rl *RateLimiter) RateLimitMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        // Get client identifier (IP address or user ID from context)
        clientIP := getClientIP(r)

        allowed, remaining := rl.IsAllowed(clientIP)

        // Add rate limit headers
        w.Header().Set("X-RateLimit-Limit", fmt.Sprintf("%.0f", rl.capacity))
        w.Header().Set("X-RateLimit-Remaining", fmt.Sprintf("%.0f", remaining))
        w.Header().Set("X-RateLimit-Reset", fmt.Sprintf("%d", time.Now().Add(time.Minute).Unix()))

        if !allowed {
            w.Header().Set("Content-Type", "application/json")
            w.Header().Set("Retry-After", "60")
            w.WriteHeader(http.StatusTooManyRequests)
            fmt.Fprintf(w, `{
                "error": "rate_limit_exceeded",
                "message": "Too many requests. Please try again later.",
                "retry_after_seconds": 60
            }`)
            return
        }

        next.ServeHTTP(w, r)
    })
}

// getClientIP extracts the client IP from the request
func getClientIP(r *http.Request) string {
    // Check X-Forwarded-For header first (for proxies)
    if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
        return forwarded
    }

    // Check X-Real-IP header
    if realIP := r.Header.Get("X-Real-IP"); realIP != "" {
        return realIP
    }

    // Fall back to RemoteAddr
    return r.RemoteAddr
}

func min(a, b float64) float64 {
    if a < b {
        return a
    }
    return b
}
```

**Key Features:**
- Thread-safe concurrent access using mutexes
- Automatic token refill based on elapsed time
- Memory leak prevention with cleanup goroutine
- HTTP headers showing rate limit status
- Configurable burst capacity and sustained rate

**Usage Example:**

```go
// Create rate limiter: 100 requests per minute with burst of 20
rateLimiter := NewRateLimiter(
    20,              // burst capacity
    100.0/60.0,      // ~1.67 tokens/second = 100/minute
    5*time.Minute,   // cleanup interval
)

router := mux.NewRouter()
router.Use(rateLimiter.RateLimitMiddleware)
```

## Complete JWT Authentication System

JWT provides stateless authentication perfect for distributed systems. Let's build a production-ready implementation with security best practices.

### Understanding JWT Structure

A JWT consists of three parts separated by dots:
```
header.payload.signature
```

**Header:** Contains token type and signing algorithm
**Payload:** Contains claims (user data, expiration, etc.)
**Signature:** Cryptographic signature ensuring integrity

### Full Implementation with Refresh Tokens

```go
package auth

import (
    "context"
    "crypto/rand"
    "encoding/base64"
    "errors"
    "fmt"
    "net/http"
    "strings"
    "time"

    "github.com/golang-jwt/jwt/v5"
    "golang.org/x/crypto/bcrypt"
)

var (
    ErrInvalidCredentials = errors.New("invalid username or password")
    ErrInvalidToken       = errors.New("invalid or expired token")
    ErrUserAlreadyExists  = errors.New("user already exists")
)

// User represents a user in the system
type User struct {
    ID           int       `json:"id"`
    Username     string    `json:"username"`
    Email        string    `json:"email"`
    PasswordHash string    `json:"-"` // never expose in JSON
    Role         string    `json:"role"`
    CreatedAt    time.Time `json:"created_at"`
    UpdatedAt    time.Time `json:"updated_at"`
}

// Claims represents the JWT claims structure
type Claims struct {
    UserID   int    `json:"user_id"`
    Username string `json:"username"`
    Email    string `json:"email"`
    Role     string `json:"role"`
    jwt.RegisteredClaims
}

// RefreshTokenClaims represents refresh token claims
type RefreshTokenClaims struct {
    UserID   int    `json:"user_id"`
    TokenID  string `json:"token_id"` // unique identifier for token rotation
    jwt.RegisteredClaims
}

// TokenPair represents access and refresh tokens
type TokenPair struct {
    AccessToken  string    `json:"access_token"`
    RefreshToken string    `json:"refresh_token"`
    TokenType    string    `json:"token_type"`
    ExpiresIn    int       `json:"expires_in"` // seconds
    ExpiresAt    time.Time `json:"expires_at"`
}

// AuthService handles all authentication operations
type AuthService struct {
    jwtSecret            []byte
    accessTokenDuration  time.Duration
    refreshTokenDuration time.Duration
    users                map[string]*User // In production, use a database
    refreshTokens        map[string]bool  // Track valid refresh tokens
    tokenMutex           sync.RWMutex
}

// NewAuthService creates a new authentication service
func NewAuthService(secret string, accessDuration, refreshDuration time.Duration) *AuthService {
    return &AuthService{
        jwtSecret:            []byte(secret),
        accessTokenDuration:  accessDuration,
        refreshTokenDuration: refreshDuration,
        users:                make(map[string]*User),
        refreshTokens:        make(map[string]bool),
    }
}

// RegisterUser creates a new user account
func (as *AuthService) RegisterUser(username, email, password, role string) (*User, error) {
    // Check if user exists
    if _, exists := as.users[username]; exists {
        return nil, ErrUserAlreadyExists
    }

    // Validate password strength
    if len(password) < 8 {
        return nil, errors.New("password must be at least 8 characters")
    }

    // Hash password with bcrypt (cost factor 12)
    hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), 12)
    if err != nil {
        return nil, fmt.Errorf("failed to hash password: %w", err)
    }

    // Create user
    user := &User{
        ID:           len(as.users) + 1,
        Username:     username,
        Email:        email,
        PasswordHash: string(hashedPassword),
        Role:         role,
        CreatedAt:    time.Now(),
        UpdatedAt:    time.Now(),
    }

    as.users[username] = user
    return user, nil
}

// Login authenticates user and returns token pair
func (as *AuthService) Login(username, password string) (*TokenPair, error) {
    // Find user
    user, exists := as.users[username]
    if !exists {
        return nil, ErrInvalidCredentials
    }

    // Verify password using constant-time comparison
    err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password))
    if err != nil {
        return nil, ErrInvalidCredentials
    }

    // Generate token pair
    return as.generateTokenPair(user)
}

// generateTokenPair creates access and refresh tokens
func (as *AuthService) generateTokenPair(user *User) (*TokenPair, error) {
    now := time.Now()

    // Create access token claims
    accessClaims := &Claims{
        UserID:   user.ID,
        Username: user.Username,
        Email:    user.Email,
        Role:     user.Role,
        RegisteredClaims: jwt.RegisteredClaims{
            ExpiresAt: jwt.NewNumericDate(now.Add(as.accessTokenDuration)),
            IssuedAt:  jwt.NewNumericDate(now),
            NotBefore: jwt.NewNumericDate(now),
            Issuer:    "api-security-service",
            Subject:   fmt.Sprintf("user:%d", user.ID),
            ID:        generateTokenID(),
        },
    }

    // Generate access token
    accessToken := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims)
    accessTokenString, err := accessToken.SignedString(as.jwtSecret)
    if err != nil {
        return nil, fmt.Errorf("failed to sign access token: %w", err)
    }

    // Create refresh token claims
    refreshTokenID := generateTokenID()
    refreshClaims := &RefreshTokenClaims{
        UserID:  user.ID,
        TokenID: refreshTokenID,
        RegisteredClaims: jwt.RegisteredClaims{
            ExpiresAt: jwt.NewNumericDate(now.Add(as.refreshTokenDuration)),
            IssuedAt:  jwt.NewNumericDate(now),
            Issuer:    "api-security-service",
            Subject:   fmt.Sprintf("user:%d", user.ID),
            ID:        refreshTokenID,
        },
    }

    // Generate refresh token
    refreshToken := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims)
    refreshTokenString, err := refreshToken.SignedString(as.jwtSecret)
    if err != nil {
        return nil, fmt.Errorf("failed to sign refresh token: %w", err)
    }

    // Store refresh token ID for validation
    as.tokenMutex.Lock()
    as.refreshTokens[refreshTokenID] = true
    as.tokenMutex.Unlock()

    return &TokenPair{
        AccessToken:  accessTokenString,
        RefreshToken: refreshTokenString,
        TokenType:    "Bearer",
        ExpiresIn:    int(as.accessTokenDuration.Seconds()),
        ExpiresAt:    now.Add(as.accessTokenDuration),
    }, nil
}

// ValidateAccessToken validates and parses an access token
func (as *AuthService) ValidateAccessToken(tokenString string) (*Claims, error) {
    token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
        // Validate signing method
        if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
            return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
        }
        return as.jwtSecret, nil
    })

    if err != nil {
        return nil, ErrInvalidToken
    }

    claims, ok := token.Claims.(*Claims)
    if !ok || !token.Valid {
        return nil, ErrInvalidToken
    }

    return claims, nil
}

// RefreshAccessToken generates a new access token using a refresh token
func (as *AuthService) RefreshAccessToken(refreshTokenString string) (*TokenPair, error) {
    // Parse refresh token
    token, err := jwt.ParseWithClaims(refreshTokenString, &RefreshTokenClaims{}, func(token *jwt.Token) (interface{}, error) {
        if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
            return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
        }
        return as.jwtSecret, nil
    })

    if err != nil {
        return nil, ErrInvalidToken
    }

    claims, ok := token.Claims.(*RefreshTokenClaims)
    if !ok || !token.Valid {
        return nil, ErrInvalidToken
    }

    // Check if refresh token is still valid (not revoked)
    as.tokenMutex.RLock()
    valid, exists := as.refreshTokens[claims.TokenID]
    as.tokenMutex.RUnlock()

    if !exists || !valid {
        return nil, errors.New("refresh token has been revoked")
    }

    // Find user
    var user *User
    for _, u := range as.users {
        if u.ID == claims.UserID {
            user = u
            break
        }
    }

    if user == nil {
        return nil, errors.New("user not found")
    }

    // Revoke old refresh token (token rotation)
    as.tokenMutex.Lock()
    delete(as.refreshTokens, claims.TokenID)
    as.tokenMutex.Unlock()

    // Generate new token pair
    return as.generateTokenPair(user)
}

// Logout revokes a refresh token
func (as *AuthService) Logout(refreshTokenString string) error {
    token, err := jwt.ParseWithClaims(refreshTokenString, &RefreshTokenClaims{}, func(token *jwt.Token) (interface{}, error) {
        return as.jwtSecret, nil
    })

    if err != nil {
        return ErrInvalidToken
    }

    claims, ok := token.Claims.(*RefreshTokenClaims)
    if !ok {
        return ErrInvalidToken
    }

    // Revoke refresh token
    as.tokenMutex.Lock()
    delete(as.refreshTokens, claims.TokenID)
    as.tokenMutex.Unlock()

    return nil
}

// AuthMiddleware validates JWT tokens on protected routes
func (as *AuthService) AuthMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        // Extract token from Authorization header
        authHeader := r.Header.Get("Authorization")
        if authHeader == "" {
            http.Error(w, `{"error":"missing_token","message":"Authorization header required"}`, 
                http.StatusUnauthorized)
            return
        }

        // Parse "Bearer <token>" format
        parts := strings.SplitN(authHeader, " ", 2)
        if len(parts) != 2 || parts[0] != "Bearer" {
            http.Error(w, `{"error":"invalid_token_format","message":"Authorization header must be Bearer token"}`, 
                http.StatusUnauthorized)
            return
        }

        // Validate token
        claims, err := as.ValidateAccessToken(parts[1])
        if err != nil {
            http.Error(w, `{"error":"invalid_token","message":"Token is invalid or expired"}`, 
                http.StatusUnauthorized)
            return
        }

        // Add claims to request context
        ctx := context.WithValue(r.Context(), "user_id", claims.UserID)
        ctx = context.WithValue(ctx, "username", claims.Username)
        ctx = context.WithValue(ctx, "email", claims.Email)
        ctx = context.WithValue(ctx, "role", claims.Role)
        ctx = context.WithValue(ctx, "claims", claims)

        next.ServeHTTP(w, r.WithContext(ctx))
    })
}

// generateTokenID creates a cryptographically secure random token ID
func generateTokenID() string {
    b := make([]byte, 32)
    rand.Read(b)
    return base64.URLEncoding.EncodeToString(b)
}

// GetUserFromContext extracts user information from request context
func GetUserFromContext(ctx context.Context) (int, string, string, bool) {
    userID, ok1 := ctx.Value("user_id").(int)
    username, ok2 := ctx.Value("username").(string)
    role, ok3 := ctx.Value("role").(string)
    return userID, username, role, ok1 && ok2 && ok3
}
```

**Security Features:**
- Secure password hashing with bcrypt (cost factor 12)
- Access tokens with short expiration (15-30 minutes recommended)
- Refresh tokens with rotation for enhanced security
- Token revocation capability
- Constant-time password comparison to prevent timing attacks
- Cryptographically secure random token IDs

### JWT Authentication Usage Example

```go
package main

import (
    "encoding/json"
    "fmt"
    "net/http"
    "time"

    "github.com/gorilla/mux"
)

type LoginRequest struct {
    Username string `json:"username"`
    Password string `json:"password"`
}

type RegisterRequest struct {
    Username string `json:"username"`
    Email    string `json:"email"`
    Password string `json:"password"`
    Role     string `json:"role"`
}

func main() {
    // Initialize auth service
    authService := NewAuthService(
        "your-super-secret-jwt-key-min-256-bits",
        15*time.Minute,  // access token expires in 15 minutes
        7*24*time.Hour,  // refresh token expires in 7 days
    )

    router := mux.NewRouter()

    // Public routes
    router.HandleFunc("/api/auth/register", registerHandler(authService)).Methods("POST")
    router.HandleFunc("/api/auth/login", loginHandler(authService)).Methods("POST")
    router.HandleFunc("/api/auth/refresh", refreshHandler(authService)).Methods("POST")

    // Protected routes
    protected := router.PathPrefix("/api").Subrouter()
    protected.Use(authService.AuthMiddleware)
    protected.HandleFunc("/profile", profileHandler).Methods("GET")
    protected.HandleFunc("/auth/logout", logoutHandler(authService)).Methods("POST")

    fmt.Println("Server starting on :8080")
    http.ListenAndServe(":8080", router)
}

func registerHandler(as *AuthService) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        var req RegisterRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            http.Error(w, `{"error":"invalid_request"}`, http.StatusBadRequest)
            return
        }

        user, err := as.RegisterUser(req.Username, req.Email, req.Password, req.Role)
        if err != nil {
            http.Error(w, fmt.Sprintf(`{"error":"%s"}`, err.Error()), http.StatusBadRequest)
            return
        }

        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(map[string]interface{}{
            "message": "User registered successfully",
            "user":    user,
        })
    }
}

func loginHandler(as *AuthService) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        var req LoginRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            http.Error(w, `{"error":"invalid_request"}`, http.StatusBadRequest)
            return
        }

        tokenPair, err := as.Login(req.Username, req.Password)
        if err != nil {
            http.Error(w, `{"error":"invalid_credentials"}`, http.StatusUnauthorized)
            return
        }

        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(tokenPair)
    }
}

func refreshHandler(as *AuthService) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        var req struct {
            RefreshToken string `json:"refresh_token"`
        }
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            http.Error(w, `{"error":"invalid_request"}`, http.StatusBadRequest)
            return
        }

        tokenPair, err := as.RefreshAccessToken(req.RefreshToken)
        if err != nil {
            http.Error(w, `{"error":"invalid_refresh_token"}`, http.StatusUnauthorized)
            return
        }

        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(tokenPair)
    }
}

func logoutHandler(as *AuthService) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        var req struct {
            RefreshToken string `json:"refresh_token"`
        }
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            http.Error(w, `{"error":"invalid_request"}`, http.StatusBadRequest)
            return
        }

        if err := as.Logout(req.RefreshToken); err != nil {
            http.Error(w, `{"error":"logout_failed"}`, http.StatusBadRequest)
            return
        }

        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(map[string]string{"message": "Logged out successfully"})
    }
}

func profileHandler(w http.ResponseWriter, r *http.Request) {
    userID, username, role, ok := GetUserFromContext(r.Context())
    if !ok {
        http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "user_id":  userID,
        "username": username,
        "role":     role,
    })
}
```

## Advanced Role-Based Authorization (RBAC)

RBAC provides granular access control by defining what actions users can perform based on their roles. Let's build a comprehensive, flexible system.

### RBAC Concepts

**Roles:** Named collections of permissions (e.g., admin, manager, user)
**Permissions:** Specific actions on resources (e.g., users:read, orders:write)
**Resources:** API endpoints or data entities (e.g., users, orders, reports)
**Actions:** Operations performed (e.g., read, write, delete, update)

### Complete RBAC Implementation

```go
package rbac

import (
    "context"
    "encoding/json"
    "fmt"
    "net/http"
    "strings"
    "sync"
)

// Permission represents a specific action on a resource
type Permission struct {
    Resource string `json:"resource"` // e.g., "users", "orders", "reports"
    Action   string `json:"action"`   // e.g., "read", "write", "delete", "update"
}

// String returns a string representation of the permission
func (p Permission) String() string {
    return fmt.Sprintf("%s:%s", p.Resource, p.Action)
}

// Role defines a user role with associated permissions
type Role struct {
    Name        string       `json:"name"`
    Description string       `json:"description"`
    Permissions []Permission `json:"permissions"`
    Inherits    []string     `json:"inherits"` // Support role inheritance
}

// RBAC manages role-based access control
type RBAC struct {
    roles map[string]*Role
    mutex sync.RWMutex
}

// NewRBAC creates a new RBAC system with default roles
func NewRBAC() *RBAC {
    rbac := &RBAC{
        roles: make(map[string]*Role),
    }
    rbac.initializeDefaultRoles()
    return rbac
}

// initializeDefaultRoles sets up standard role hierarchy
func (r *RBAC) initializeDefaultRoles() {
    // User role - basic read access
    r.AddRole(&Role{
        Name:        "user",
        Description: "Standard user with basic read permissions",
        Permissions: []Permission{
            {"profile", "read"},
            {"profile", "update"},
            {"orders", "read"},
            {"orders", "create"},
        },
    })

    // Manager role - inherits user permissions plus management capabilities
    r.AddRole(&Role{
        Name:        "manager",
        Description: "Manager with user permissions plus team management",
        Inherits:    []string{"user"},
        Permissions: []Permission{
            {"users", "read"},
            {"users", "update"},
            {"orders", "update"},
            {"orders", "delete"},
            {"reports", "read"},
            {"reports", "create"},
        },
    })

    // Admin role - full system access
    r.AddRole(&Role{
        Name:        "admin",
        Description: "Administrator with full system access",
        Inherits:    []string{"manager"},
        Permissions: []Permission{
            {"users", "create"},
            {"users", "delete"},
            {"roles", "read"},
            {"roles", "write"},
            {"roles", "delete"},
            {"reports", "update"},
            {"reports", "delete"},
            {"system", "manage"},
        },
    })
}

// AddRole adds or updates a role in the system
func (r *RBAC) AddRole(role *Role) {
    r.mutex.Lock()
    defer r.mutex.Unlock()
    r.roles[role.Name] = role
}

// GetRole retrieves a role by name
func (r *RBAC) GetRole(name string) (*Role, bool) {
    r.mutex.RLock()
    defer r.mutex.RUnlock()
    role, exists := r.roles[name]
    return role, exists
}

// GetAllPermissions returns all permissions for a role including inherited ones
func (r *RBAC) GetAllPermissions(roleName string) []Permission {
    r.mutex.RLock()
    defer r.mutex.RUnlock()

    return r.getPermissionsRecursive(roleName, make(map[string]bool))
}

// getPermissionsRecursive recursively collects permissions including inherited roles
func (r *RBAC) getPermissionsRecursive(roleName string, visited map[string]bool) []Permission {
    // Prevent infinite loops
    if visited[roleName] {
        return nil
    }
    visited[roleName] = true

    role, exists := r.roles[roleName]
    if !exists {
        return nil
    }

    permissions := make([]Permission, 0)
    permissionSet := make(map[string]bool)

    // Add this role's permissions
    for _, perm := range role.Permissions {
        key := perm.String()
        if !permissionSet[key] {
            permissions = append(permissions, perm)
            permissionSet[key] = true
        }
    }

    // Recursively add inherited permissions
    for _, inheritedRole := range role.Inherits {
        inheritedPerms := r.getPermissionsRecursive(inheritedRole, visited)
        for _, perm := range inheritedPerms {
            key := perm.String()
            if !permissionSet[key] {
                permissions = append(permissions, perm)
                permissionSet[key] = true
            }
        }
    }

    return permissions
}

// HasPermission checks if a role has a specific permission
func (r *RBAC) HasPermission(roleName, resource, action string) bool {
    permissions := r.GetAllPermissions(roleName)
    
    for _, perm := range permissions {
        if perm.Resource == resource && perm.Action == action {
            return true
        }
        // Support wildcard permissions
        if perm.Resource == resource && perm.Action == "*" {
            return true
        }
        if perm.Resource == "*" && perm.Action == action {
            return true
        }
    }
    
    return false
}

// RequirePermission creates middleware that enforces permission requirements
func (r *RBAC) RequirePermission(resource, action string) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
            // Get user role from context (set by auth middleware)
            role, ok := req.Context().Value("role").(string)
            if !ok {
                respondError(w, "missing_role", "User role not found in context", http.StatusForbidden)
                return
            }

            // Check permission
            if !r.HasPermission(role, resource, action) {
                respondError(w, "insufficient_permissions", 
                    fmt.Sprintf("Role '%s' lacks permission '%s:%s'", role, resource, action),
                    http.StatusForbidden)
                return
            }

            next.ServeHTTP(w, req)
        })
    }
}

// RequireAnyPermission requires at least one of the specified permissions
func (r *RBAC) RequireAnyPermission(permissions []Permission) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
            role, ok := req.Context().Value("role").(string)
            if !ok {
                respondError(w, "missing_role", "User role not found", http.StatusForbidden)
                return
            }

            // Check if user has any of the required permissions
            hasPermission := false
            for _, perm := range permissions {
                if r.HasPermission(role, perm.Resource, perm.Action) {
                    hasPermission = true
                    break
                }
            }

            if !hasPermission {
                respondError(w, "insufficient_permissions", 
                    "User lacks required permissions", http.StatusForbidden)
                return
            }

            next.ServeHTTP(w, req)
        })
    }
}

// RequireRole creates middleware that requires a specific role
func (r *RBAC) RequireRole(allowedRoles ...string) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
            userRole, ok := req.Context().Value("role").(string)
            if !ok {
                respondError(w, "missing_role", "User role not found", http.StatusForbidden)
                return
            }

            // Check if user's role is in allowed roles
            allowed := false
            for _, role := range allowedRoles {
                if userRole == role {
                    allowed = true
                    break
                }
            }

            if !allowed {
                respondError(w, "insufficient_role", 
                    fmt.Sprintf("Requires one of these roles: %v", allowedRoles),
                    http.StatusForbidden)
                return
            }

            next.ServeHTTP(w, req)
        })
    }
}

// CheckResourceOwnership verifies user owns the requested resource
type OwnershipChecker func(ctx context.Context, resourceID string) (bool, error)

// RequireOwnership creates middleware that verifies resource ownership
func RequireOwnership(checker OwnershipChecker) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            // Admins bypass ownership checks
            role, _ := r.Context().Value("role").(string)
            if role == "admin" || role == "manager" {
                next.ServeHTTP(w, r)
                return
            }

            // Extract resource ID from URL
            pathParts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
            if len(pathParts) < 3 {
                respondError(w, "invalid_path", "Resource ID not found in path", http.StatusBadRequest)
                return
            }

            resourceID := pathParts[len(pathParts)-1]

            // Check ownership
            isOwner, err := checker(r.Context(), resourceID)
            if err != nil {
                respondError(w, "ownership_check_failed", err.Error(), http.StatusInternalServerError)
                return
            }

            if !isOwner {
                respondError(w, "access_denied", "You can only access your own resources", http.StatusForbidden)
                return
            }

            next.ServeHTTP(w, r)
        })
    }
}

func respondError(w http.ResponseWriter, code, message string, statusCode int) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(statusCode)
    json.NewEncoder(w).Encode(map[string]interface{}{
        "error":   code,
        "message": message,
    })
}
```

### RBAC Usage Examples

```go
package main

import (
    "context"
    "encoding/json"
    "fmt"
    "net/http"
    "strconv"

    "github.com/gorilla/mux"
)

func setupSecureAPI() *mux.Router {
    // Initialize services
    authService := NewAuthService(
        "your-secret-key",
        15*time.Minute,
        7*24*time.Hour,
    )
    
    rbacService := NewRBAC()
    rateLimiter := NewRateLimiter(100, 100.0/60.0, 5*time.Minute)

    router := mux.NewRouter()

    // Apply rate limiting globally
    router.Use(rateLimiter.RateLimitMiddleware)

    // Public routes
    router.HandleFunc("/api/health", healthHandler).Methods("GET")
    router.HandleFunc("/api/auth/login", loginHandler(authService)).Methods("POST")
    router.HandleFunc("/api/auth/register", registerHandler(authService)).Methods("POST")

    // Protected routes requiring authentication
    api := router.PathPrefix("/api").Subrouter()
    api.Use(authService.AuthMiddleware)

    // User profile - users can read/update their own profile
    api.Handle("/users/{id}",
        rbacService.RequirePermission("profile", "read")(
            RequireOwnership(checkUserOwnership)(
                http.HandlerFunc(getUserHandler),
            ),
        ),
    ).Methods("GET")

    api.Handle("/users/{id}",
        rbacService.RequirePermission("profile", "update")(
            RequireOwnership(checkUserOwnership)(
                http.HandlerFunc(updateUserHandler),
            ),
        ),
    ).Methods("PUT")

    // User management - requires manager or admin role
    api.Handle("/users",
        rbacService.RequirePermission("users", "read")(
            http.HandlerFunc(listUsersHandler),
        ),
    ).Methods("GET")

    api.Handle("/users",
        rbacService.RequireRole("admin")(
            http.HandlerFunc(createUserHandler),
        ),
    ).Methods("POST")

    api.Handle("/users/{id}",
        rbacService.RequireRole("admin")(
            http.HandlerFunc(deleteUserHandler),
        ),
    ).Methods("DELETE")

    // Orders - users can read their orders, managers can see all
    api.Handle("/orders",
        rbacService.RequirePermission("orders", "read")(
            http.HandlerFunc(listOrdersHandler),
        ),
    ).Methods("GET")

    api.Handle("/orders",
        rbacService.RequirePermission("orders", "create")(
            http.HandlerFunc(createOrderHandler),
        ),
    ).Methods("POST")

    api.Handle("/orders/{id}",
        rbacService.RequirePermission("orders", "update")(
            http.HandlerFunc(updateOrderHandler),
        ),
    ).Methods("PUT")

    api.Handle("/orders/{id}",
        rbacService.RequireRole("manager", "admin")(
            http.HandlerFunc(deleteOrderHandler),
        ),
    ).Methods("DELETE")

    // Reports - managers can read, admins can modify
    api.Handle("/reports",
        rbacService.RequirePermission("reports", "read")(
            http.HandlerFunc(listReportsHandler),
        ),
    ).Methods("GET")

    api.Handle("/reports",
        rbacService.RequireRole("admin")(
            http.HandlerFunc(createReportHandler),
        ),
    ).Methods("POST")

    // Admin-only: role management
    api.Handle("/roles",
        rbacService.RequireRole("admin")(
            http.HandlerFunc(listRolesHandler(rbacService)),
        ),
    ).Methods("GET")

    return router
}

// Ownership checker function
func checkUserOwnership(ctx context.Context, resourceID string) (bool, error) {
    userID, ok := ctx.Value("user_id").(int)
    if !ok {
        return false, fmt.Errorf("user ID not found in context")
    }

    requestedUserID, err := strconv.Atoi(resourceID)
    if err != nil {
        return false, fmt.Errorf("invalid user ID format")
    }

    return userID == requestedUserID, nil
}

// Example handlers
func getUserHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    userID := vars["id"]
    
    // In production, fetch from database
    response := map[string]interface{}{
        "id":       userID,
        "username": "john_doe",
        "email":    "john@example.com",
        "role":     r.Context().Value("role"),
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
}

func updateUserHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    userID := vars["id"]
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "message": "User updated successfully",
        "user_id": userID,
    })
}

func listUsersHandler(w http.ResponseWriter, r *http.Request) {
    role := r.Context().Value("role").(string)
    
    // Managers see limited info, admins see all
    users := []map[string]interface{}{
        {"id": 1, "username": "john_doe", "role": "user"},
        {"id": 2, "username": "jane_manager", "role": "manager"},
    }
    
    if role == "admin" {
        // Add sensitive fields for admins
        for i := range users {
            users[i]["email"] = fmt.Sprintf("user%d@example.com", i+1)
            users[i]["created_at"] = "2024-01-01"
        }
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(users)
}

func createUserHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{
        "message": "User created successfully",
    })
}

func deleteUserHandler(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    userID := vars["id"]
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "message": "User deleted successfully",
        "user_id": userID,
    })
}

func listOrdersHandler(w http.ResponseWriter, r *http.Request) {
    userID := r.Context().Value("user_id").(int)
    role := r.Context().Value("role").(string)
    
    // Regular users see only their orders
    orders := []map[string]interface{}{}
    
    if role == "user" {
        orders = []map[string]interface{}{
            {"id": 1, "user_id": userID, "total": 99.99, "status": "completed"},
        }
    } else {
        // Managers and admins see all orders
        orders = []map[string]interface{}{
            {"id": 1, "user_id": 1, "total": 99.99, "status": "completed"},
            {"id": 2, "user_id": 2, "total": 149.99, "status": "pending"},
        }
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(orders)
}

func createOrderHandler(w http.ResponseWriter, r *http.Request) {
    userID := r.Context().Value("user_id").(int)
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "message": "Order created successfully",
        "user_id": userID,
        "order_id": 123,
    })
}

func updateOrderHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    json.NewEncoder(w).Encode(map[string]string{
        "message": "Order updated",
    })
}

func deleteOrderHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    json.NewEncoder(w).Encode(map[string]string{
        "message": "Order deleted",
    })
}

func listReportsHandler(w http.ResponseWriter, r *http.Request) {
    reports := []map[string]interface{}{
        {"id": 1, "title": "Sales Report Q4", "created_at": "2024-10-01"},
        {"id": 2, "title": "User Analytics", "created_at": "2024-10-15"},
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(reports)
}

func createReportHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(map[string]string{
        "message": "Report created",
    })
}

func listRolesHandler(rbacService *RBAC) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        roles := []string{"user", "manager", "admin"}
        roleDetails := make([]map[string]interface{}, 0)
        
        for _, roleName := range roles {
            role, exists := rbacService.GetRole(roleName)
            if exists {
                permissions := rbacService.GetAllPermissions(roleName)
                roleDetails = append(roleDetails, map[string]interface{}{
                    "name":        role.Name,
                    "description": role.Description,
                    "permissions": permissions,
                })
            }
        }
        
        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(roleDetails)
    }
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "status": "healthy",
        "timestamp": time.Now().Format(time.RFC3339),
    })
}
```

## Complete Integration Example

Here's a complete working example showing all three security layers working together:

```go
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "time"

    "github.com/gorilla/mux"
)

func main() {
    // Initialize all security services
    authService := NewAuthService(
        "your-256-bit-secret-key-replace-in-production",
        15*time.Minute,   // access token: 15 minutes
        7*24*time.Hour,   // refresh token: 7 days
    )
    
    rbacService := NewRBAC()
    
    rateLimiter := NewRateLimiter(
        20,              // burst: 20 requests
        100.0/60.0,      // rate: 100 requests per minute
        5*time.Minute,   // cleanup interval
    )

    // Register demo users
    authService.RegisterUser("admin_user", "admin@example.com", "SecurePass123!", "admin")
    authService.RegisterUser("manager_user", "manager@example.com", "SecurePass123!", "manager")
    authService.RegisterUser("regular_user", "user@example.com", "SecurePass123!", "user")

    // Setup router
    router := setupSecureAPI(authService, rbacService, rateLimiter)

    // Start server
    log.Println("🔒 Secure API Server starting on :8080")
    log.Println("📝 Demo users created:")
    log.Println("   Admin:   admin_user / SecurePass123!")
    log.Println("   Manager: manager_user / SecurePass123!")
    log.Println("   User:    regular_user / SecurePass123!")
    log.Fatal(http.ListenAndServe(":8080", router))
}

func setupSecureAPI(auth *AuthService, rbac *RBAC, limiter *RateLimiter) *mux.Router {
    router := mux.NewRouter()

    // Global rate limiting
    router.Use(limiter.RateLimitMiddleware)

    // Public endpoints
    router.HandleFunc("/api/health", healthCheckHandler).Methods("GET")
    router.HandleFunc("/api/auth/register", registerHandler(auth)).Methods("POST")
    router.HandleFunc("/api/auth/login", loginHandler(auth)).Methods("POST")
    router.HandleFunc("/api/auth/refresh", refreshHandler(auth)).Methods("POST")

    // Protected API routes
    api := router.PathPrefix("/api").Subrouter()
    api.Use(auth.AuthMiddleware)

    // Profile endpoints
    api.HandleFunc("/profile", getProfileHandler).Methods("GET")
    
    // User management (requires specific permissions)
    api.Handle("/admin/users",
        rbac.RequirePermission("users", "read")(
            http.HandlerFunc(adminListUsersHandler),
        ),
    ).Methods("GET")
    
    api.Handle("/admin/users",
        rbac.RequireRole("admin")(
            http.HandlerFunc(adminCreateUserHandler),
        ),
    ).Methods("POST")

    // Logout
    api.HandleFunc("/auth/logout", logoutHandler(auth)).Methods("POST")

    return router
}

func healthCheckHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "status":    "healthy",
        "timestamp": time.Now().Format(time.RFC3339),
        "version":   "1.0.0",
    })
}

func getProfileHandler(w http.ResponseWriter, r *http.Request) {
    userID, username, role, ok := GetUserFromContext(r.Context())
    if !ok {
        http.Error(w, `{"error":"context_error"}`, http.StatusInternalServerError)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "user_id":  userID,
        "username": username,
        "role":     role,
        "message":  "Profile retrieved successfully",
    })
}

func adminListUsersHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "users": []map[string]interface{}{
            {"id": 1, "username": "admin_user", "role": "admin"},
            {"id": 2, "username": "manager_user", "role": "manager"},
            {"id": 3, "username": "regular_user", "role": "user"},
        },
    })
}

func adminCreateUserHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(map[string]string{
        "message": "User created successfully",
    })
}
```

## Testing Your Security Implementation

Comprehensive testing ensures your security measures work correctly.

### Unit Tests

```go
package auth_test

import (
    "testing"
    "time"

    "github.com/stretchr/testify/assert"
)

func TestUserRegistration(t *testing.T) {
    authService := NewAuthService("test-secret", 15*time.Minute, 24*time.Hour)

    // Test successful registration
    user, err := authService.RegisterUser("testuser", "test@example.com", "password123", "user")
    assert.NoError(t, err)
    assert.Equal(t, "testuser", user.Username)
    assert.Equal(t, "user", user.Role)

    // Test duplicate user
    _, err = authService.RegisterUser("testuser", "test@example.com", "password123", "user")
    assert.Error(t, err)
}

func TestAuthentication(t *testing.T) {
    authService := NewAuthService("test-secret", 15*time.Minute, 24*time.Hour)
    authService.RegisterUser("testuser", "test@example.com", "password123", "user")

    // Test successful login
    tokenPair, err := authService.Login("testuser", "password123")
    assert.NoError(t, err)
    assert.NotEmpty(t, tokenPair.AccessToken)
    assert.NotEmpty(t, tokenPair.RefreshToken)

    // Test invalid credentials
    _, err = authService.Login("testuser", "wrongpassword")
    assert.Error(t, err)
}

func TestTokenValidation(t *testing.T) {
    authService := NewAuthService("test-secret", 15*time.Minute, 24*time.Hour)
    authService.RegisterUser("testuser", "test@example.com", "password123", "user")

    // Generate token
    tokenPair, _ := authService.Login("testuser", "password123")

    // Validate token
    claims, err := authService.ValidateAccessToken(tokenPair.AccessToken)
    assert.NoError(t, err)
    assert.Equal(t, "testuser", claims.Username)
    assert.Equal(t, "user", claims.Role)

    // Test invalid token
    _, err = authService.ValidateAccessToken("invalid-token")
    assert.Error(t, err)
}

func TestRBACPermissions(t *testing.T) {
    rbac := NewRBAC()

    // Test admin permissions
    assert.True(t, rbac.HasPermission("admin", "users", "delete"))
    assert.True(t, rbac.HasPermission("admin", "orders", "read"))

    // Test manager permissions
    assert.True(t, rbac.HasPermission("manager", "users", "read"))
    assert.False(t, rbac.HasPermission("manager", "users", "delete"))

    // Test user permissions
    assert.True(t, rbac.HasPermission("user", "orders", "read"))
    assert.False(t, rbac.HasPermission("user", "users", "read"))
}

func TestRateLimiting(t *testing.T) {
    limiter := NewRateLimiter(5, 1, time.Minute) // 5 burst, 1/sec

    // Should allow burst requests
    for i := 0; i < 5; i++ {
        allowed, _ := limiter.IsAllowed("test-client")
        assert.True(t, allowed, "Request %d should be allowed", i+1)
    }

    // 6th request should be blocked
    allowed, _ := limiter.IsAllowed("test-client")
    assert.False(t, allowed, "6th request should be blocked")

    // Wait for refill
    time.Sleep(1 * time.Second)
    allowed, _ = limiter.IsAllowed("test-client")
    assert.True(t, allowed, "Request after refill should be allowed")
}
```

### Integration Tests

```go
package main_test

import (
    "bytes"
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "testing"

    "github.com/stretchr/testify/assert"
)

func TestCompleteAuthFlow(t *testing.T) {
    // Setup test server
    authService := NewAuthService("test-secret", 15*time.Minute, 24*time.Hour)
    rbac := NewRBAC()
    limiter := NewRateLimiter(100, 10, time.Minute)
    router := setupSecureAPI(authService, rbac, limiter)
    server := httptest.NewServer(router)
    defer server.Close()

    // Register user
    registerBody := map[string]string{
        "username": "testuser",
        "email":    "test@example.com",
        "password": "password123",
        "role":     "user",
    }
    registerJSON, _ := json.Marshal(registerBody)
    resp, err := http.Post(server.URL+"/api/auth/register", "application/json", bytes.NewBuffer(registerJSON))
    assert.NoError(t, err)
    assert.Equal(t, http.StatusOK, resp.StatusCode)

    // Login
    loginBody := map[string]string{
        "username": "testuser",
        "password": "password123",
    }
    loginJSON, _ := json.Marshal(loginBody)
    resp, err = http.Post(server.URL+"/api/auth/login", "application/json", bytes.NewBuffer(loginJSON))
    assert.NoError(t, err)
    assert.Equal(t, http.StatusOK, resp.StatusCode)

    var tokenPair TokenPair
    json.NewDecoder(resp.Body).Decode(&tokenPair)
    assert.NotEmpty(t, tokenPair.AccessToken)

    // Access protected endpoint
    req, _ := http.NewRequest("GET", server.URL+"/api/profile", nil)
    req.Header.Set("Authorization", "Bearer "+tokenPair.AccessToken)
    resp, err = http.DefaultClient.Do(req)
    assert.NoError(t, err)
    assert.Equal(t, http.StatusOK, resp.StatusCode)
}

func TestUnauthorizedAccess(t *testing.T) {
    authService := NewAuthService("test-secret", 15*time.Minute, 24*time.Hour)
    rbac := NewRBAC()
    limiter := NewRateLimiter(100, 10, time.Minute)
    router := setupSecureAPI(authService, rbac, limiter)
    server := httptest.NewServer(router)
    defer server.Close()

    // Try to access protected endpoint without token
    resp, err := http.Get(server.URL + "/api/profile")
    assert.NoError(t, err)
    assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
}

func TestRateLimitingEndToEnd(t *testing.T) {
    authService := NewAuthService("test-secret", 15*time.Minute, 24*time.Hour)
    rbac := NewRBAC()
    limiter := NewRateLimiter(3, 1, time.Minute) // Low limit for testing
    router := setupSecureAPI(authService, rbac, limiter)
    server := httptest.NewServer(router)
    defer server.Close()

    // Make requests until rate limited
    var lastStatus int
    for i := 0; i < 5; i++ {
        resp, _ := http.Get(server.URL + "/api/health")
        lastStatus = resp.StatusCode
    }

    // Should eventually get rate limited
    assert.Equal(t, http.StatusTooManyRequests, lastStatus)
}
```

## Best Practices and Security Guidelines

### 1. Secure JWT Secret Management

**Never hardcode secrets in source code.** Use environment variables or secure key management services:

```go
import "os"

func getJWTSecret() string {
    secret := os.Getenv("JWT_SECRET")
    if secret == "" {
        log.Fatal("JWT_SECRET environment variable not set")
    }
    if len(secret) < 32 {
        log.Fatal("JWT_SECRET must be at least 256 bits (32 bytes)")
    }
    return secret
}
```

### 2. Implement Token Rotation

Refresh tokens should be rotated on each use to prevent replay attacks:

```go
// Our implementation already includes token rotation
// When RefreshAccessToken is called, it:
// 1. Validates the old refresh token
// 2. Revokes it immediately
// 3. Generates a new token pair
```

### 3. Use HTTPS in Production

Never transmit tokens over HTTP:

```go
// Redirect HTTP to HTTPS in production
func redirectToHTTPS(w http.ResponseWriter, r *http.Request) {
    if r.TLS == nil {
        url := "https://" + r.Host + r.RequestURI
        http.Redirect(w, r, url, http.StatusMovedPermanently)
    }
}
```

### 4. Implement Proper Logging

Log security events without exposing sensitive data:

```go
func securityLogger(event string, details map[string]interface{}) {
    // Never log passwords, tokens, or sensitive data
    sanitized := make(map[string]interface{})
    for k, v := range details {
        if k != "password" && k != "token" && k != "secret" {
            sanitized[k] = v
        }
    }
    
    log.Printf("[SECURITY] %s: %+v", event, sanitized)
}
```

### 5. Set Appropriate Token Expiration

Balance security and user experience:

```go
// Recommended token lifespans
const (
    AccessTokenLifespan  = 15 * time.Minute  // Short-lived
    RefreshTokenLifespan = 7 * 24 * time.Hour // 1 week
)
```

### 6. Implement Account Lockout

Prevent brute force attacks:

```go
type LoginAttemptTracker struct {
    attempts map[string]int
    lockouts map[string]time.Time
    mutex    sync.RWMutex
}

func (lat *LoginAttemptTracker) RecordFailedAttempt(username string) bool {
    lat.mutex.Lock()
    defer lat.mutex.Unlock()
    
    lat.attempts[username]++
    if lat.attempts[username] >= 5 {
        lat.lockouts[username] = time.Now().Add(15 * time.Minute)
        return true // Account locked
    }
    return false
}

func (lat *LoginAttemptTracker) IsLocked(username string) bool {
    lat.mutex.RLock()
    defer lat.mutex.RUnlock()
    
    lockoutTime, exists := lat.lockouts[username]
    if !exists {
        return false
    }
    
    if time.Now().After(lockoutTime) {
        delete(lat.lockouts, username)
        delete(lat.attempts, username)
        return false
    }
    
    return true
}
```

### 7. Validate Input Thoroughly

Never trust client input:

```go
func validateRegistrationInput(username, email, password string) error {
    if len(username) < 3 || len(username) > 50 {
        return errors.New("username must be 3-50 characters")
    }
    
    if !isValidEmail(email) {
        return errors.New("invalid email format")
    }
    
    if len(password) < 8 {
        return errors.New("password must be at least 8 characters")
    }
    
    // Check password complexity
    hasUpper := regexp.MustCompile(`[A-Z]`).MatchString(password)
    hasLower := regexp.MustCompile(`[a-z]`).MatchString(password)
    hasDigit := regexp.MustCompile(`[0-9]`).MatchString(password)
    
    if !hasUpper || !hasLower || !hasDigit {
        return errors.New("password must contain uppercase, lowercase, and digit")
    }
    
    return nil
}
```

## Common Security Pitfalls

### 1. Storing Passwords in Plain Text
**Never do this:** `user.Password = password`
**Always hash:** `user.PasswordHash = bcrypt.Generate(password)`

### 2. Not Validating Token Signatures
**Always verify** JWT signatures and signing algorithms to prevent token tampering.

### 3. Exposing Detailed Error Messages
**Bad:** `{"error": "User 'admin' not found in database table 'users'"}`
**Good:** `{"error": "Invalid credentials"}`

### 4. Missing Rate Limit Headers
**Always include** rate limit headers so clients know their limits.

### 5. Inconsistent Authorization Checks
**Always enforce** permissions at the API layer, never rely on client-side checks alone.

## Performance Optimization

### Caching Permission Checks

```go
type PermissionCache struct {
    cache map[string]bool
    mutex sync.RWMutex
    ttl   time.Duration
}

func (pc *PermissionCache) Check(role, resource, action string) (bool, bool) {
    key := fmt.Sprintf("%s:%s:%s", role, resource, action)
    
    pc.mutex.RLock()
    result, exists := pc.cache[key]
    pc.mutex.RUnlock()
    
    return result, exists
}

func (pc *PermissionCache) Set(role, resource, action string, allowed bool) {
    key := fmt.Sprintf("%s:%s:%s", role, resource, action)
    
    pc.mutex.Lock()
    pc.cache[key] = allowed
    pc.mutex.Unlock()
    
    // Clear after TTL
    time.AfterFunc(pc.ttl, func() {
        pc.mutex.Lock()
        delete(pc.cache, key)
        pc.mutex.Unlock()
    })
}
```

### Connection Pooling for Database

```go
import "database/sql"

func setupDatabase() *sql.DB {
    db, err := sql.Open("postgres", connString)
    if err != nil {
        log.Fatal(err)
    }
    
    // Optimize connection pool
    db.SetMaxOpenConns(25)
    db.SetMaxIdleConns(5)
    db.SetConnMaxLifetime(5 * time.Minute)
    
    return db
}
```

## Real-World Deployment Considerations

### Docker Configuration

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY . .
RUN go build -o api-server .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/api-server .
EXPOSE 8080
CMD ["./api-server"]
```

### Environment Variables

```bash
# .env file
JWT_SECRET=your-production-secret-min-256-bits
ACCESS_TOKEN_DURATION=15m
REFRESH_TOKEN_DURATION=168h
RATE_LIMIT_BURST=20
RATE_LIMIT_RATE=100
DATABASE_URL=postgres://user:pass@localhost/db
REDIS_URL=redis://localhost:6379
```

### Health Checks

```go
func healthCheckHandler(w http.ResponseWriter, r *http.Request) {
    checks := map[string]string{
        "api": "healthy",
        "database": checkDatabase(),
        "redis": checkRedis(),
    }
    
    allHealthy := true
    for _, status := range checks {
        if status != "healthy" {
            allHealthy = false
            break
        }
    }
    
    statusCode := http.StatusOK
    if !allHealthy {
        statusCode = http.StatusServiceUnavailable
    }
    
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(statusCode)
    json.NewEncoder(w).Encode(map[string]interface{}{
        "status": checks,
        "timestamp": time.Now(),
    })
}
```

## Conclusion

Building secure APIs in Go requires a multi-layered approach combining rate limiting, JWT authentication, and role-based authorization. This guide provided production-ready implementations of all three security pillars with complete, working examples.

**Key Takeaways:**

- **Rate limiting** prevents abuse and ensures fair resource allocation using token bucket algorithms
- **JWT authentication** provides stateless, scalable identity verification with proper token lifecycle management
- **RBAC** enables fine-grained access control with role inheritance and flexible permission models
- **Defense in depth** requires combining multiple security layers rather than relying on any single mechanism
- **Testing is critical** for validating security implementations under various conditions and attack scenarios
- **Performance optimization** ensures security measures don't significantly impact user experience

By implementing these patterns, you'll build APIs that protect user data, prevent abuse, and scale effectively while maintaining security. Remember that security is an ongoing process—regularly review and update your implementations, monitor for suspicious activity, and stay informed about emerging threats and best practices.

## Additional Resources

- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/) - Comprehensive API security vulnerabilities and mitigations
- [JWT.io](https://jwt.io/) - JWT debugger and library documentation
- [RFC 8725: JWT Best Practices](https://datatracker.ietf.org/doc/html/rfc8725) - Official JWT security guidelines
- [Go Security Documentation](https://golang.org/doc/security) - Official Go security resources
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework) - Enterprise security guidelines
- [Go Web Application Security](https://github.com/OWASP/Go-SCP) - OWASP Secure Coding Practices for Go
- [Rate Limiting Patterns](https://cloud.google.com/architecture/rate-limiting-strategies-techniques) - Advanced rate limiting strategies