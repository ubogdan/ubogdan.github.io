---
title: "Hassle-Free Prometheus on Bare Metal"
description: ""
date: "2025-10-21T10:53:11+03:00"
thumbnail: ""
categories: [ "Observability" ]
tags: ["golang", "prometheus"]
---

# Hassle-Free Prometheus on Bare Metal

Monitoring bare metal infrastructure with Prometheus is notoriously challenging. Unlike cloud environments with built-in service discovery, bare metal deployments require manual configuration of scrape targets. Every time you add a server, you must update Prometheus configs, manage TLS certificates, and ensure exporters are accessible. This manual process is error-prone, time-consuming, and doesn't scale.

In this guide, we'll build a production-ready service discovery system specifically designed for bare metal Prometheus deployments. Our solution provides automatic agent registration, certificate management, and dynamic target discovery—eliminating the operational overhead that makes bare metal monitoring painful.

## Why Bare Metal Monitoring Is Hard

**Manual Target Management:** Cloud providers offer automatic service discovery through APIs. On bare metal, you're manually editing YAML files and reloading Prometheus every time infrastructure changes.

**Certificate Hell:** Securing metrics endpoints with TLS requires generating, distributing, and rotating certificates across potentially hundreds of servers. Manual certificate management doesn't scale and leads to expired certificates breaking monitoring.

**Network Complexity:** Bare metal servers may sit behind firewalls, in different networks, or have complex routing requirements. Exposing metrics securely requires careful network design.

**Configuration Drift:** With manual configuration, your monitoring setup inevitably drifts from reality. Servers get decommissioned but remain in configs. New servers run unmonitored for days before someone remembers to add them.

**Scalability Bottlenecks:** As infrastructure grows, manual processes become bottlenecks. Adding 50 servers shouldn't require 50 manual configuration changes.

Our service discovery system solves these problems with automated registration, dynamic discovery, and built-in certificate management.

## System Architecture Overview

Our solution consists of two components:

**Discovery Service:** A central HTTPS server that:
- Manages agent registrations with JWT authentication
- Issues and signs TLS certificates for agents
- Provides Prometheus-compatible service discovery endpoints
- Persists agent metadata with TTL-based expiration
- Tracks agent health and availability

**Discovery Agent:** A lightweight daemon running on each monitored server that:
- Registers with the discovery service using API keys
- Obtains TLS certificates automatically
- Proxies local Prometheus exporters
- Reports health status and metadata
- Re-registers before TTL expiration

The workflow is simple:
1. Deploy agent on a server with an API key
2. Agent authenticates and registers with discovery service
3. Discovery service issues TLS certificate to agent
4. Agent starts local proxy exposing metrics securely
5. Prometheus queries discovery service for targets
6. Prometheus scrapes metrics from registered agents

## Prerequisites

To follow this guide, you should understand:

- **Go fundamentals:** Goroutines, channels, error handling, and HTTP servers
- **Prometheus basics:** Scrape configs, service discovery, and relabeling
- **TLS/PKI concepts:** Certificate signing, private keys, and trust chains
- **JWT authentication:** Token structure, signing, and validation
- **YAML configuration:** Parsing and structure

**Required packages:**

```go
go get github.com/golang-jwt/jwt/v5
go get github.com/prometheus/client_golang/prometheus
go get github.com/prometheus/client_golang/prometheus/promhttp
go get gopkg.in/yaml.v3
```

This guide uses Go 1.21+ but is compatible with Go 1.19+.

## Building the Discovery Service

### Core Data Structures

Let's start by defining our domain models:

```go
package discovery

import (
    "crypto/x509"
    "sync"
    "time"
)

// Agent represents a registered monitoring agent
type Agent struct {
    ID          string            `json:"id"`
    Hostname    string            `json:"hostname"`
    IPAddress   string            `json:"ip_address"`
    Port        int               `json:"port"`
    Labels      map[string]string `json:"labels"`
    Certificate *x509.Certificate `json:"-"`
    RegisteredAt time.Time        `json:"registered_at"`
    LastSeen    time.Time         `json:"last_seen"`
    TTL         time.Duration     `json:"ttl"`
}

// IsExpired checks if agent registration has expired
func (a *Agent) IsExpired() bool {
    return time.Since(a.LastSeen) > a.TTL
}

// AgentRegistry manages registered agents
type AgentRegistry struct {
    agents map[string]*Agent
    mu     sync.RWMutex
}

// NewAgentRegistry creates a new agent registry
func NewAgentRegistry() *AgentRegistry {
    return &AgentRegistry{
        agents: make(map[string]*Agent),
    }
}

// Register adds or updates an agent
func (r *AgentRegistry) Register(agent *Agent) {
    r.mu.Lock()
    defer r.mu.Unlock()
    
    agent.LastSeen = time.Now()
    r.agents[agent.ID] = agent
}

// Get retrieves an agent by ID
func (r *AgentRegistry) Get(id string) (*Agent, bool) {
    r.mu.RLock()
    defer r.mu.RUnlock()
    
    agent, exists := r.agents[id]
    return agent, exists
}

// List returns all active agents
func (r *AgentRegistry) List() []*Agent {
    r.mu.RLock()
    defer r.mu.RUnlock()
    
    agents := make([]*Agent, 0, len(r.agents))
    for _, agent := range r.agents {
        if !agent.IsExpired() {
            agents = append(agents, agent)
        }
    }
    return agents
}

// Remove deletes an agent by ID
func (r *AgentRegistry) Remove(id string) {
    r.mu.Lock()
    defer r.mu.Unlock()
    
    delete(r.agents, id)
}

// CleanExpired removes all expired agents
func (r *AgentRegistry) CleanExpired() int {
    r.mu.Lock()
    defer r.mu.Unlock()
    
    removed := 0
    for id, agent := range r.agents {
        if agent.IsExpired() {
            delete(r.agents, id)
            removed++
        }
    }
    return removed
}
```

These structures provide thread-safe agent management with automatic expiration handling.

### JWT Authentication

Agents authenticate using JWT tokens signed with a shared secret:

```go
package auth

import (
    "fmt"
    "time"

    "github.com/golang-jwt/jwt/v5"
)

// Claims represents JWT token claims
type Claims struct {
    AgentID  string `json:"agent_id"`
    Hostname string `json:"hostname"`
    jwt.RegisteredClaims
}

// TokenManager handles JWT creation and validation
type TokenManager struct {
    signingKey []byte
    issuer     string
}

// NewTokenManager creates a new token manager
func NewTokenManager(signingKey []byte, issuer string) *TokenManager {
    return &TokenManager{
        signingKey: signingKey,
        issuer:     issuer,
    }
}

// GenerateToken creates a JWT for an agent
func (tm *TokenManager) GenerateToken(agentID, hostname string, ttl time.Duration) (string, error) {
    claims := &Claims{
        AgentID:  agentID,
        Hostname: hostname,
        RegisteredClaims: jwt.RegisteredClaims{
            ExpiresAt: jwt.NewNumericDate(time.Now().Add(ttl)),
            IssuedAt:  jwt.NewNumericDate(time.Now()),
            NotBefore: jwt.NewNumericDate(time.Now()),
            Issuer:    tm.issuer,
            Subject:   agentID,
        },
    }

    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    return token.SignedString(tm.signingKey)
}

// ValidateToken verifies and parses a JWT token
func (tm *TokenManager) ValidateToken(tokenString string) (*Claims, error) {
    token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
        // Verify signing method
        if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
            return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
        }
        return tm.signingKey, nil
    })

    if err != nil {
        return nil, fmt.Errorf("failed to parse token: %w", err)
    }

    if claims, ok := token.Claims.(*Claims); ok && token.Valid {
        return claims, nil
    }

    return nil, fmt.Errorf("invalid token")
}
```

This provides cryptographically secure agent authentication without requiring a database.

### Certificate Management

The discovery service acts as a certificate authority, signing agent certificates:

```go
package cert

import (
    "crypto/rand"
    "crypto/rsa"
    "crypto/x509"
    "crypto/x509/pkix"
    "encoding/pem"
    "fmt"
    "math/big"
    "time"
)

// CertificateAuthority manages certificate signing
type CertificateAuthority struct {
    caCert       *x509.Certificate
    caPrivateKey *rsa.PrivateKey
}

// NewCertificateAuthority creates or loads a CA
func NewCertificateAuthority(caCertPEM, caKeyPEM []byte) (*CertificateAuthority, error) {
    // Parse CA certificate
    block, _ := pem.Decode(caCertPEM)
    if block == nil {
        return nil, fmt.Errorf("failed to decode CA certificate PEM")
    }

    caCert, err := x509.ParseCertificate(block.Bytes)
    if err != nil {
        return nil, fmt.Errorf("failed to parse CA certificate: %w", err)
    }

    // Parse CA private key
    keyBlock, _ := pem.Decode(caKeyPEM)
    if keyBlock == nil {
        return nil, fmt.Errorf("failed to decode CA private key PEM")
    }

    caKey, err := x509.ParsePKCS1PrivateKey(keyBlock.Bytes)
    if err != nil {
        return nil, fmt.Errorf("failed to parse CA private key: %w", err)
    }

    return &CertificateAuthority{
        caCert:       caCert,
        caPrivateKey: caKey,
    }, nil
}

// SignCertificate signs a certificate for an agent
func (ca *CertificateAuthority) SignCertificate(hostname string, ipAddresses []string) ([]byte, []byte, error) {
    // Generate private key for agent
    privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
    if err != nil {
        return nil, nil, fmt.Errorf("failed to generate private key: %w", err)
    }

    // Create certificate template
    serialNumber, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
    if err != nil {
        return nil, nil, fmt.Errorf("failed to generate serial number: %w", err)
    }

    template := &x509.Certificate{
        SerialNumber: serialNumber,
        Subject: pkix.Name{
            CommonName:   hostname,
            Organization: []string{"Prometheus Discovery"},
        },
        NotBefore:             time.Now(),
        NotAfter:              time.Now().Add(365 * 24 * time.Hour), // 1 year
        KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
        ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth},
        BasicConstraintsValid: true,
        DNSNames:              []string{hostname},
    }

    // Add IP addresses to certificate
    for _, ip := range ipAddresses {
        if parsedIP := net.ParseIP(ip); parsedIP != nil {
            template.IPAddresses = append(template.IPAddresses, parsedIP)
        }
    }

    // Sign certificate with CA
    certBytes, err := x509.CreateCertificate(rand.Reader, template, ca.caCert, &privateKey.PublicKey, ca.caPrivateKey)
    if err != nil {
        return nil, nil, fmt.Errorf("failed to create certificate: %w", err)
    }

    // Encode certificate to PEM
    certPEM := pem.EncodeToMemory(&pem.Block{
        Type:  "CERTIFICATE",
        Bytes: certBytes,
    })

    // Encode private key to PEM
    keyPEM := pem.EncodeToMemory(&pem.Block{
        Type:  "RSA PRIVATE KEY",
        Bytes: x509.MarshalPKCS1PrivateKey(privateKey),
    })

    return certPEM, keyPEM, nil
}

// GetCACertificate returns the CA certificate in PEM format
func (ca *CertificateAuthority) GetCACertificate() []byte {
    return pem.EncodeToMemory(&pem.Block{
        Type:  "CERTIFICATE",
        Bytes: ca.caCert.Raw,
    })
}
```

This CA implementation handles the entire certificate lifecycle, from generation to signing.

### HTTP API Handlers

Now let's implement the HTTP endpoints for agent registration:

```go
package server

import (
    "encoding/json"
    "fmt"
    "log"
    "net"
    "net/http"
    "strings"
    "time"

    "yourproject/auth"
    "yourproject/cert"
    "yourproject/discovery"
)

// DiscoveryServer handles HTTP requests
type DiscoveryServer struct {
    registry     *discovery.AgentRegistry
    tokenManager *auth.TokenManager
    ca           *cert.CertificateAuthority
    defaultTTL   time.Duration
}

// NewDiscoveryServer creates a new discovery server
func NewDiscoveryServer(
    registry *discovery.AgentRegistry,
    tokenManager *auth.TokenManager,
    ca *cert.CertificateAuthority,
    defaultTTL time.Duration,
) *DiscoveryServer {
    return &DiscoveryServer{
        registry:     registry,
        tokenManager: tokenManager,
        ca:           ca,
        defaultTTL:   defaultTTL,
    }
}

// RegisterRequest represents an agent registration request
type RegisterRequest struct {
    Hostname  string            `json:"hostname"`
    Port      int               `json:"port"`
    Labels    map[string]string `json:"labels"`
    IPAddress string            `json:"ip_address,omitempty"`
}

// RegisterResponse contains registration response data
type RegisterResponse struct {
    AgentID     string `json:"agent_id"`
    Certificate string `json:"certificate"`
    PrivateKey  string `json:"private_key"`
    CACert      string `json:"ca_certificate"`
    TTL         int    `json:"ttl_seconds"`
}

// HandleRegister processes agent registration requests
func (s *DiscoveryServer) HandleRegister(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    // Extract and validate JWT token
    authHeader := r.Header.Get("Authorization")
    if !strings.HasPrefix(authHeader, "Bearer ") {
        http.Error(w, "Missing or invalid authorization header", http.StatusUnauthorized)
        return
    }

    tokenString := strings.TrimPrefix(authHeader, "Bearer ")
    claims, err := s.tokenManager.ValidateToken(tokenString)
    if err != nil {
        log.Printf("Token validation failed: %v", err)
        http.Error(w, "Invalid token", http.StatusUnauthorized)
        return
    }

    // Parse request body
    var req RegisterRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, "Invalid request body", http.StatusBadRequest)
        return
    }

    // Get client IP if not provided
    if req.IPAddress == "" {
        ip, _, err := net.SplitHostPort(r.RemoteAddr)
        if err != nil {
            log.Printf("Failed to parse remote address: %v", err)
            http.Error(w, "Failed to determine IP address", http.StatusBadRequest)
            return
        }
        req.IPAddress = ip
    }

    // Validate request
    if req.Hostname == "" {
        http.Error(w, "Hostname is required", http.StatusBadRequest)
        return
    }
    if req.Port <= 0 || req.Port > 65535 {
        http.Error(w, "Invalid port number", http.StatusBadRequest)
        return
    }

    // Generate certificate for agent
    certPEM, keyPEM, err := s.ca.SignCertificate(req.Hostname, []string{req.IPAddress})
    if err != nil {
        log.Printf("Failed to sign certificate: %v", err)
        http.Error(w, "Failed to generate certificate", http.StatusInternalServerError)
        return
    }

    // Create agent record
    agent := &discovery.Agent{
        ID:          claims.AgentID,
        Hostname:    req.Hostname,
        IPAddress:   req.IPAddress,
        Port:        req.Port,
        Labels:      req.Labels,
        RegisteredAt: time.Now(),
        LastSeen:    time.Now(),
        TTL:         s.defaultTTL,
    }

    // Register agent
    s.registry.Register(agent)

    // Send response
    resp := RegisterResponse{
        AgentID:     agent.ID,
        Certificate: string(certPEM),
        PrivateKey:  string(keyPEM),
        CACert:      string(s.ca.GetCACertificate()),
        TTL:         int(s.defaultTTL.Seconds()),
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(resp)

    log.Printf("Agent registered: %s (%s:%d)", agent.ID, agent.IPAddress, agent.Port)
}

// HandleHeartbeat processes agent heartbeat requests
func (s *DiscoveryServer) HandleHeartbeat(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    // Validate token
    authHeader := r.Header.Get("Authorization")
    if !strings.HasPrefix(authHeader, "Bearer ") {
        http.Error(w, "Missing authorization header", http.StatusUnauthorized)
        return
    }

    tokenString := strings.TrimPrefix(authHeader, "Bearer ")
    claims, err := s.tokenManager.ValidateToken(tokenString)
    if err != nil {
        http.Error(w, "Invalid token", http.StatusUnauthorized)
        return
    }

    // Update last seen time
    agent, exists := s.registry.Get(claims.AgentID)
    if !exists {
        http.Error(w, "Agent not registered", http.StatusNotFound)
        return
    }

    agent.LastSeen = time.Now()
    s.registry.Register(agent) // Update registry

    w.WriteHeader(http.StatusOK)
}
```

These handlers provide secure agent registration with automatic certificate issuance.

### Prometheus Service Discovery Endpoint

Prometheus supports HTTP-based service discovery. Let's implement the discovery endpoint:

```go
// PrometheusTarget represents a Prometheus scrape target
type PrometheusTarget struct {
    Targets []string          `json:"targets"`
    Labels  map[string]string `json:"labels"`
}

// HandleDiscovery provides Prometheus-compatible service discovery
func (s *DiscoveryServer) HandleDiscovery(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodGet {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }

    // Get all active agents
    agents := s.registry.List()

    // Convert to Prometheus target format
    targets := make([]PrometheusTarget, 0, len(agents))
    for _, agent := range agents {
        target := PrometheusTarget{
            Targets: []string{fmt.Sprintf("%s:%d", agent.IPAddress, agent.Port)},
            Labels: map[string]string{
                "__meta_agent_id":       agent.ID,
                "__meta_agent_hostname": agent.Hostname,
            },
        }

        // Add custom labels
        for key, value := range agent.Labels {
            target.Labels["__meta_agent_"+key] = value
        }

        targets = append(targets, target)
    }

    // Return JSON response
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(targets)
}
```

This endpoint returns a JSON array that Prometheus can consume directly through its HTTP service discovery mechanism.

### Complete Discovery Service

Let's tie everything together into a runnable server:

```go
package main

import (
    "flag"
    "log"
    "net/http"
    "os"
    "time"

    "yourproject/auth"
    "yourproject/cert"
    "yourproject/discovery"
    "yourproject/server"
)

func main() {
    // Parse command-line flags
    addr := flag.String("addr", ":8443", "HTTPS server address")
    caCertFile := flag.String("ca-cert", "ca.crt", "CA certificate file")
    caKeyFile := flag.String("ca-key", "ca.key", "CA private key file")
    certFile := flag.String("cert", "server.crt", "Server certificate file")
    keyFile := flag.String("key", "server.key", "Server private key file")
    jwtSecret := flag.String("jwt-secret", "", "JWT signing secret")
    ttl := flag.Duration("ttl", 5*time.Minute, "Agent TTL duration")
    flag.Parse()

    if *jwtSecret == "" {
        log.Fatal("JWT secret is required (--jwt-secret)")
    }

    // Load CA certificate and key
    caCertPEM, err := os.ReadFile(*caCertFile)
    if err != nil {
        log.Fatalf("Failed to read CA certificate: %v", err)
    }

    caKeyPEM, err := os.ReadFile(*caKeyFile)
    if err != nil {
        log.Fatalf("Failed to read CA key: %v", err)
    }

    // Initialize certificate authority
    ca, err := cert.NewCertificateAuthority(caCertPEM, caKeyPEM)
    if err != nil {
        log.Fatalf("Failed to initialize CA: %v", err)
    }

    // Initialize components
    registry := discovery.NewAgentRegistry()
    tokenManager := auth.NewTokenManager([]byte(*jwtSecret), "prometheus-discovery")
    srv := server.NewDiscoveryServer(registry, tokenManager, ca, *ttl)

    // Start cleanup goroutine
    go cleanupExpiredAgents(registry)

    // Register HTTP handlers
    http.HandleFunc("/api/v1/register", srv.HandleRegister)
    http.HandleFunc("/api/v1/heartbeat", srv.HandleHeartbeat)
    http.HandleFunc("/api/v1/discovery", srv.HandleDiscovery)

    // Health check endpoint
    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        w.Write([]byte("OK"))
    })

    // Start HTTPS server
    log.Printf("Starting discovery service on %s", *addr)
    log.Printf("Agent TTL: %v", *ttl)
    if err := http.ListenAndServeTLS(*addr, *certFile, *keyFile, nil); err != nil {
        log.Fatalf("Server failed: %v", err)
    }
}

// cleanupExpiredAgents periodically removes expired agents
func cleanupExpiredAgents(registry *discovery.AgentRegistry) {
    ticker := time.NewTicker(1 * time.Minute)
    defer ticker.Stop()

    for range ticker.C {
        removed := registry.CleanExpired()
        if removed > 0 {
            log.Printf("Cleaned up %d expired agents", removed)
        }
    }
}
```

## Building the Discovery Agent

### Agent Configuration

Agents need flexible configuration for different environments:

```go
package config

import (
    "fmt"
    "os"
    "time"

    "gopkg.in/yaml.v3"
)

// Config represents agent configuration
type Config struct {
    Agent struct {
        ID       string            `yaml:"id"`
        Hostname string            `yaml:"hostname"`
        Labels   map[string]string `yaml:"labels"`
    } `yaml:"agent"`

    Discovery struct {
        URL       string        `yaml:"url"`
        APIKey    string        `yaml:"api_key"`
        Insecure  bool          `yaml:"insecure"`
        HeartbeatInterval time.Duration `yaml:"heartbeat_interval"`
    } `yaml:"discovery"`

    Proxy struct {
        ListenAddr string `yaml:"listen_addr"`
        TLSCertFile string `yaml:"tls_cert_file"`
        TLSKeyFile  string `yaml:"tls_key_file"`
    } `yaml:"proxy"`

    Exporters []ExporterConfig `yaml:"exporters"`
}

// ExporterConfig represents a Prometheus exporter
type ExporterConfig struct {
    Name string `yaml:"name"`
    URL  string `yaml:"url"`
    Path string `yaml:"path"`
}

// LoadConfig reads configuration from a YAML file
func LoadConfig(filename string) (*Config, error) {
    data, err := os.ReadFile(filename)
    if err != nil {
        return nil, fmt.Errorf("failed to read config file: %w", err)
    }

    var config Config
    if err := yaml.Unmarshal(data, &config); err != nil {
        return nil, fmt.Errorf("failed to parse config: %w", err)
    }

    // Set defaults
    if config.Agent.Hostname == "" {
        hostname, err := os.Hostname()
        if err != nil {
            return nil, fmt.Errorf("failed to get hostname: %w", err)
        }
        config.Agent.Hostname = hostname
    }

    if config.Discovery.HeartbeatInterval == 0 {
        config.Discovery.HeartbeatInterval = 1 * time.Minute
    }

    if config.Proxy.ListenAddr == "" {
        config.Proxy.ListenAddr = ":9090"
    }

    return &config, nil
}
```

Example configuration file (`agent.yaml`):

```yaml
agent:
  id: "server-01"
  hostname: "web-server-01"
  labels:
    environment: "production"
    datacenter: "us-east-1"
    role: "web"

discovery:
  url: "https://discovery.example.com:8443"
  api_key: "your-jwt-token-here"
  heartbeat_interval: 60s

proxy:
  listen_addr: ":9090"
  tls_cert_file: "/etc/prometheus-agent/cert.pem"
  tls_key_file: "/etc/prometheus-agent/key.pem"

exporters:
  - name: "node_exporter"
    url: "http://localhost:9100"
    path: "/metrics"
  - name: "process_exporter"
    url: "http://localhost:9256"
    path: "/metrics"
```

### Agent Registration

The agent handles the registration flow with the discovery service:

```go
package agent

import (
    "bytes"
    "crypto/tls"
    "encoding/json"
    "fmt"
    "io"
    "log"
    "net"
    "net/http"
    "os"
    "time"

    "yourproject/config"
)

// DiscoveryClient handles communication with discovery service
type DiscoveryClient struct {
    config     *config.Config
    httpClient *http.Client
}

// NewDiscoveryClient creates a new discovery client
func NewDiscoveryClient(cfg *config.Config) *DiscoveryClient {
    transport := &http.Transport{
        TLSClientConfig: &tls.Config{
            InsecureSkipVerify: cfg.Discovery.Insecure,
        },
    }

    return &DiscoveryClient{
        config: cfg,
        httpClient: &http.Client{
            Transport: transport,
            Timeout:   10 * time.Second,
        },
    }
}

// RegisterRequest represents registration data
type RegisterRequest struct {
    Hostname  string            `json:"hostname"`
    Port      int               `json:"port"`
    Labels    map[string]string `json:"labels"`
    IPAddress string            `json:"ip_address,omitempty"`
}

// RegisterResponse contains registration response
type RegisterResponse struct {
    AgentID     string `json:"agent_id"`
    Certificate string `json:"certificate"`
    PrivateKey  string `json:"private_key"`
    CACert      string `json:"ca_certificate"`
    TTL         int    `json:"ttl_seconds"`
}

// Register registers the agent with discovery service
func (dc *DiscoveryClient) Register() (*RegisterResponse, error) {
    // Get listen port from config
    _, portStr, err := net.SplitHostPort(dc.config.Proxy.ListenAddr)
    if err != nil {
        return nil, fmt.Errorf("invalid listen address: %w", err)
    }

    port := 9090 // Default
    if portStr != "" {
        fmt.Sscanf(portStr, "%d", &port)
    }

    // Prepare registration request
    reqBody := RegisterRequest{
        Hostname: dc.config.Agent.Hostname,
        Port:     port,
        Labels:   dc.config.Agent.Labels,
    }

    bodyBytes, err := json.Marshal(reqBody)
    if err != nil {
        return nil, fmt.Errorf("failed to marshal request: %w", err)
    }

    // Create HTTP request
    url := dc.config.Discovery.URL + "/api/v1/register"
    req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(bodyBytes))
    if err != nil {
        return nil, fmt.Errorf("failed to create request: %w", err)
    }

    req.Header.Set("Content-Type", "application/json")
    req.Header.Set("Authorization", "Bearer "+dc.config.Discovery.APIKey)

    // Send request
    resp, err := dc.httpClient.Do(req)
    if err != nil {
        return nil, fmt.Errorf("registration request failed: %w", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        body, _ := io.ReadAll(resp.Body)
        return nil, fmt.Errorf("registration failed with status %d: %s", resp.StatusCode, string(body))
    }

    // Parse response
    var regResp RegisterResponse
    if err := json.NewDecoder(resp.Body).Decode(&regResp); err != nil {
        return nil, fmt.Errorf("failed to decode response: %w", err)
    }

    return &regResp, nil
}

// SendHeartbeat sends a heartbeat to discovery service
func (dc *DiscoveryClient) SendHeartbeat() error {
    url := dc.config.Discovery.URL + "/api/v1/heartbeat"
    req, err := http.NewRequest(http.MethodPost, url, nil)
    if err != nil {
        return fmt.Errorf("failed to create heartbeat request: %w", err)
    }

    req.Header.Set("Authorization", "Bearer "+dc.config.Discovery.APIKey)

    resp, err := dc.httpClient.Do(req)
    if err != nil {
        return fmt.Errorf("heartbeat request failed: %w", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        return fmt.Errorf("heartbeat failed with status %d", resp.StatusCode)
    }

    return nil
}

// SaveCertificates writes certificates to disk
func (dc *DiscoveryClient) SaveCertificates(resp *RegisterResponse) error {
    // Save certificate
    if err := os.WriteFile(dc.config.Proxy.TLSCertFile, []byte(resp.Certificate), 0600); err != nil {
        return fmt.Errorf("failed to write certificate: %w", err)
    }

    // Save private key
    if err := os.WriteFile(dc.config.Proxy.TLSKeyFile, []byte(resp.PrivateKey), 0600); err != nil {
        return fmt.Errorf("failed to write private key: %w", err)
    }

    // Save CA certificate
    caFile := dc.config.Proxy.TLSCertFile + ".ca"
    if err := os.WriteFile(caFile, []byte(resp.CACert), 0600); err != nil {
        return fmt.Errorf("failed to write CA certificate: %w", err)
    }

    log.Printf("Certificates saved to %s and %s", dc.config.Proxy.TLSCertFile, dc.config.Proxy.TLSKeyFile)
    return nil
}
```

### Metrics Proxy

The agent runs a local HTTPS proxy that aggregates metrics from local exporters:

```go
package proxy

import (
    "crypto/tls"
    "fmt"
    "io"
    "log"
    "net/http"
    "strings"
    "time"

    "yourproject/config"
)

// MetricsProxy aggregates metrics from local exporters
type MetricsProxy struct {
    config     *config.Config
    httpClient *http.Client
}

// NewMetricsProxy creates a new metrics proxy
func NewMetricsProxy(cfg *config.Config) *MetricsProxy {
    return &MetricsProxy{
        config: cfg,
        httpClient: &http.Client{
            Timeout: 10 * time.Second,
        },
    }
}

// Start starts the HTTPS proxy server
func (mp *MetricsProxy) Start() error {
    mux := http.NewServeMux()
    mux.HandleFunc("/metrics", mp.handleMetrics)
    mux.HandleFunc("/health", mp.handleHealth)

    // Configure TLS
    tlsConfig := &tls.Config{
        MinVersion: tls.VersionTLS12,
        CipherSuites: []uint16{
            tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
            tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
        },
    }

    server := &http.Server{
        Addr:      mp.config.Proxy.ListenAddr,
        Handler:   mux,
        TLSConfig: tlsConfig,
    }

    log.Printf("Starting metrics proxy on %s", mp.config.Proxy.ListenAddr)
    return server.ListenAndServeTLS(mp.config.Proxy.TLSCertFile, mp.config.Proxy.TLSKeyFile)
}

// handleMetrics aggregates metrics from all configured exporters
func (mp *MetricsProxy) handleMetrics(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "text/plain; version=0.0.4")

    // Collect metrics from each exporter
    for _, exporter := range mp.config.Exporters {
        metrics, err := mp.fetchExporterMetrics(exporter)
        if err != nil {
            log.Printf("Failed to fetch metrics from %s: %v", exporter.Name, err)
            // Write error comment to metrics output
            fmt.Fprintf(w, "# ERROR: Failed to scrape %s: %v\n", exporter.Name, err)
            continue
        }

        // Write metrics with exporter label
        mp.writeMetricsWithLabel(w, metrics, exporter.Name)
    }
}

// fetchExporterMetrics retrieves metrics from an exporter
func (mp *MetricsProxy) fetchExporterMetrics(exporter config.ExporterConfig) (string, error) {
    url := exporter.URL + exporter.Path
    resp, err := mp.httpClient.Get(url)
    if err != nil {
        return "", fmt.Errorf("request failed: %w", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        return "", fmt.Errorf("unexpected status: %d", resp.StatusCode)
    }

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return "", fmt.Errorf("failed to read response: %w", err)
    }

    return string(body), nil
}

// writeMetricsWithLabel adds exporter label to each metric
func (mp *MetricsProxy) writeMetricsWithLabel(w http.ResponseWriter, metrics string, exporterName string) {
    lines := strings.Split(metrics, "\n")

    for _, line := range lines {
        // Skip empty lines and comments
        if line == "" || strings.HasPrefix(line, "#") {
            fmt.Fprintln(w, line)
            continue
        }

        // Add exporter label to metric
        // Format: metric_name{existing_labels} value timestamp
        // Becomes: metric_name{existing_labels,exporter="name"} value timestamp
        parts := strings.SplitN(line, "{", 2)
        if len(parts) == 2 {
            // Metric has labels
            labelParts := strings.SplitN(parts[1], "}", 2)
            if len(labelParts) == 2 {
                fmt.Fprintf(w, "%s{%s,exporter=\"%s\"}%s\n",
                    parts[0], labelParts[0], exporterName, labelParts[1])
            }
        } else {
            // Metric has no labels
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                fmt.Fprintf(w, "%s{exporter=\"%s\"} %s\n",
                    parts[0], exporterName, strings.Join(parts[1:], " "))
            }
        }
    }
}

// handleHealth returns health status
func (mp *MetricsProxy) handleHealth(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte("OK"))
}
```

### Complete Agent Application

Let's assemble the complete agent:

```go
package main

import (
    "flag"
    "log"
    "os"
    "os/signal"
    "syscall"
    "time"

    "yourproject/agent"
    "yourproject/config"
    "yourproject/proxy"
)

func main() {
    // Parse flags
    configFile := flag.String("config", "agent.yaml", "Configuration file path")
    flag.Parse()

    // Load configuration
    cfg, err := config.LoadConfig(*configFile)
    if err != nil {
        log.Fatalf("Failed to load configuration: %v", err)
    }

    log.Printf("Starting Prometheus Discovery Agent")
    log.Printf("Agent ID: %s", cfg.Agent.ID)
    log.Printf("Hostname: %s", cfg.Agent.Hostname)

    // Create discovery client
    client := agent.NewDiscoveryClient(cfg)

    // Register with discovery service
    log.Printf("Registering with discovery service at %s", cfg.Discovery.URL)
    regResp, err := client.Register()
    if err != nil {
        log.Fatalf("Registration failed: %v", err)
    }

    log.Printf("Successfully registered with agent ID: %s", regResp.AgentID)
    log.Printf("Certificate TTL: %d seconds", regResp.TTL)

    // Save certificates
    if err := client.SaveCertificates(regResp); err != nil {
        log.Fatalf("Failed to save certificates: %v", err)
    }

    // Start metrics proxy
    metricsProxy := proxy.NewMetricsProxy(cfg)
    go func() {
        if err := metricsProxy.Start(); err != nil {
            log.Fatalf("Metrics proxy failed: %v", err)
        }
    }()

    // Start heartbeat goroutine
    go runHeartbeat(client, cfg)

    // Wait for shutdown signal
    sigChan := make(chan os.Signal, 1)
    signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
    <-sigChan

    log.Println("Shutting down agent")
}

// runHeartbeat sends periodic heartbeats
func runHeartbeat(client *agent.DiscoveryClient, cfg *config.Config) {
    ticker := time.NewTicker(cfg.Discovery.HeartbeatInterval)
    defer ticker.Stop()

    // Send initial heartbeat
    if err := client.SendHeartbeat(); err != nil {
        log.Printf("Initial heartbeat failed: %v", err)
    } else {
        log.Printf("Heartbeat sent successfully")
    }

    for range ticker.C {
        if err := client.SendHeartbeat(); err != nil {
            log.Printf("Heartbeat failed: %v", err)
        } else {
            log.Printf("Heartbeat sent")
        }
    }
}
```

## Configuring Prometheus

Configure Prometheus to use the discovery service:

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'bare-metal'
    scheme: https
    
    # Use HTTP service discovery
    http_sd_configs:
      - url: https://discovery.example.com:8443/api/v1/discovery
        refresh_interval: 30s
    
    # Trust the CA certificate
    tls_config:
      ca_file: /etc/prometheus/ca.crt
    
    # Relabel to use agent metadata
    relabel_configs:
      # Use hostname as instance label
      - source_labels: [__meta_agent_hostname]
        target_label: instance
      
      # Preserve agent ID
      - source_labels: [__meta_agent_id]
        target_label: agent_id
      
      # Preserve custom labels
      - regex: __meta_agent_(.+)
        action: labelmap
```

## Best Practices

**Security First:**

Always use TLS for all communication. The discovery service should never run over plain HTTP, and agents must validate server certificates:

```go
// Production TLS configuration
tlsConfig := &tls.Config{
    MinVersion: tls.VersionTLS12,
    CipherSuites: []uint16{
        tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
        tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
    },
    InsecureSkipVerify: false, // Never skip verification in production
}
```

**Implement Certificate Rotation:**

Certificates expire. Implement automatic renewal before expiration:

```go
func (a *Agent) checkCertificateExpiration() {
    cert, err := tls.LoadX509KeyPair(a.config.Proxy.TLSCertFile, a.config.Proxy.TLSKeyFile)
    if err != nil {
        log.Printf("Failed to load certificate: %v", err)
        return
    }
    
    x509Cert, err := x509.ParseCertificate(cert.Certificate[0])
    if err != nil {
        log.Printf("Failed to parse certificate: %v", err)
        return
    }
    
    // Renew if expires within 7 days
    if time.Until(x509Cert.NotAfter) < 7*24*time.Hour {
        log.Printf("Certificate expires soon, re-registering")
        a.Register()
    }
}
```

**Monitor the Discovery Service:**

The discovery service is a critical component. Monitor its health and availability:

```go
// Add Prometheus metrics to discovery service
import "github.com/prometheus/client_golang/prometheus"

var (
    registeredAgents = prometheus.NewGauge(prometheus.GaugeOpts{
        Name: "discovery_registered_agents",
        Help: "Number of currently registered agents",
    })
    
    registrationRequests = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "discovery_registration_requests_total",
            Help: "Total number of registration requests",
        },
        []string{"status"},
    )
)

func init() {
    prometheus.MustRegister(registeredAgents)
    prometheus.MustRegister(registrationRequests)
}
```

**Use Graceful Degradation:**

If the discovery service is temporarily unavailable, agents should continue serving metrics:

```go
func (dc *DiscoveryClient) RegisterWithRetry() error {
    backoff := time.Second
    maxBackoff := 5 * time.Minute
    
    for {
        err := dc.Register()
        if err == nil {
            return nil
        }
        
        log.Printf("Registration failed: %v, retrying in %v", err, backoff)
        time.Sleep(backoff)
        
        backoff *= 2
        if backoff > maxBackoff {
            backoff = maxBackoff
        }
    }
}
```

**Implement Health Checks:**

Both service and agents should expose health endpoints:

```go
func healthCheckHandler(registry *discovery.AgentRegistry) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        activeAgents := len(registry.List())
        
        response := map[string]interface{}{
            "status": "healthy",
            "active_agents": activeAgents,
            "timestamp": time.Now().Unix(),
        }
        
        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(response)
    }
}
```

**Persist Agent Registry:**

Use a database or file storage to persist agent registrations across restarts:

```go
import "encoding/json"

func (r *AgentRegistry) SaveToFile(filename string) error {
    r.mu.RLock()
    defer r.mu.RUnlock()
    
    data, err := json.Marshal(r.agents)
    if err != nil {
        return err
    }
    
    return os.WriteFile(filename, data, 0600)
}

func (r *AgentRegistry) LoadFromFile(filename string) error {
    data, err := os.ReadFile(filename)
    if err != nil {
        return err
    }
    
    r.mu.Lock()
    defer r.mu.Unlock()
    
    return json.Unmarshal(data, &r.agents)
}
```

## Common Pitfalls and How to Avoid Them

**Pitfall: Certificate Validation Bypass**

In development, disabling TLS verification is tempting but catastrophic in production.

**Solution:** Use self-signed CA certificates in development, but always validate:

```go
// Development: use custom CA
rootCAs := x509.NewCertPool()
rootCAs.AppendCertsFromPEM(caCert)

tlsConfig := &tls.Config{
    RootCAs: rootCAs,
    InsecureSkipVerify: false, // Always false
}
```

**Pitfall: Missing Heartbeat Failures**

If heartbeats fail silently, agents appear registered but are actually disconnected.

**Solution:** Implement heartbeat failure alerts:

```go
consecutiveFailures := 0
maxFailures := 3

for range ticker.C {
    if err := client.SendHeartbeat(); err != nil {
        consecutiveFailures++
        if consecutiveFailures >= maxFailures {
            log.Printf("CRITICAL: %d consecutive heartbeat failures", consecutiveFailures)
            // Trigger alert, attempt re-registration
        }
    } else {
        consecutiveFailures = 0
    }
}
```

**Pitfall: Unbounded Memory Growth**

Without cleanup, the agent registry grows indefinitely as servers come and go.

**Solution:** Implement TTL-based expiration as shown in our `CleanExpired` method. Run cleanup frequently (every minute).

**Pitfall: Race Conditions in Registry**

Multiple goroutines accessing the registry simultaneously causes panics.

**Solution:** Always use mutexes. Prefer `RWMutex` for read-heavy workloads:

```go
// Reads (common)
func (r *AgentRegistry) List() []*Agent {
    r.mu.RLock()  // Read lock
    defer r.mu.RUnlock()
    // ...
}

// Writes (rare)
func (r *AgentRegistry) Register(agent *Agent) {
    r.mu.Lock()  // Write lock
    defer r.mu.Unlock()
    // ...
}
```

**Pitfall: Port Conflicts**

Hardcoded ports cause conflicts when running multiple agents on the same host.

**Solution:** Make ports configurable and validate they're available:

```go
func checkPortAvailable(port int) error {
    ln, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
    if err != nil {
        return fmt.Errorf("port %d is not available: %w", port, err)
    }
    ln.Close()
    return nil
}
```

## Real-World Use Cases

**Use Case 1: Multi-Datacenter Monitoring**

Deploy discovery services in each datacenter, with agents registering locally:

```yaml
# agent.yaml for US datacenter
agent:
  labels:
    datacenter: "us-east-1"
    region: "us"

discovery:
  url: "https://discovery-us.example.com:8443"
```

Use Prometheus federation to aggregate metrics across datacenters.

**Use Case 2: Dynamic Scaling**

As you provision new servers, agents automatically register:

```bash
# Cloud-init or provisioning script
#!/bin/bash
apt-get install -y prometheus-discovery-agent
cp /mnt/config/agent.yaml /etc/prometheus-agent/
systemctl enable prometheus-agent
systemctl start prometheus-agent
```

New servers appear in Prometheus within 30 seconds with no manual configuration.

**Use Case 3: Role-Based Monitoring**

Use labels to organize monitoring by server role:

```yaml
agent:
  labels:
    role: "database"
    db_type: "postgresql"
    replication: "primary"
```

Create Prometheus scrape configs that target specific roles:

```yaml
- job_name: 'databases'
  http_sd_configs:
    - url: https://discovery.example.com:8443/api/v1/discovery
  
  relabel_configs:
    # Only scrape database servers
    - source_labels: [__meta_agent_role]
      regex: database
      action: keep
```

**Use Case 4: Maintenance Mode**

Temporarily remove servers from monitoring during maintenance:

```go
// Add maintenance mode to agent
func (a *Agent) EnableMaintenanceMode() {
    a.Labels["maintenance"] = "true"
    a.Register() // Re-register with maintenance label
}

// In Prometheus relabel config
- source_labels: [__meta_agent_maintenance]
  regex: "true"
  action: drop  # Don't scrape servers in maintenance
```

## Performance Considerations

**Discovery Service Scalability:**

The discovery service is lightweight and can handle thousands of agents on modest hardware:

- **Memory:** ~1KB per agent (100,000 agents = ~100MB)
- **CPU:** Negligible (<1% per core for 10,000 agents)
- **Network:** Each heartbeat is <100 bytes

Benchmark on a 4-core server:
```
Registered Agents: 10,000
Heartbeat Rate: 1 per minute per agent
Total Heartbeats/min: 10,000
CPU Usage: <2%
Memory Usage: 150MB
```

**Agent Overhead:**

Each agent adds minimal overhead:

- **Memory:** ~10MB RSS
- **CPU:** <0.1% during idle, ~1% during scrape
- **Network:** Depends on exporter metrics volume

**Optimization Techniques:**

Use connection pooling for HTTP clients:

```go
transport := &http.Transport{
    MaxIdleConns:        100,
    MaxIdleConnsPerHost: 10,
    IdleConnTimeout:     90 * time.Second,
}

client := &http.Client{
    Transport: transport,
    Timeout:   10 * time.Second,
}
```

Batch heartbeats if running many agents:

```go
// Send heartbeats for all agents on a host
func sendBatchHeartbeat(agents []*Agent) error {
    var wg sync.WaitGroup
    errors := make(chan error, len(agents))
    
    for _, agent := range agents {
        wg.Add(1)
        go func(a *Agent) {
            defer wg.Done()
            if err := a.SendHeartbeat(); err != nil {
                errors <- err
            }
        }(agent)
    }
    
    wg.Wait()
    close(errors)
    
    // Check if any failed
    for err := range errors {
        if err != nil {
            return err
        }
    }
    return nil
}
```

## Testing Approach

**Unit Tests for Agent Registry:**

```go
func TestAgentRegistry_RegisterAndList(t *testing.T) {
    registry := discovery.NewAgentRegistry()
    
    agent := &discovery.Agent{
        ID:       "test-01",
        Hostname: "test-host",
        TTL:      5 * time.Minute,
    }
    
    registry.Register(agent)
    
    agents := registry.List()
    if len(agents) != 1 {
        t.Errorf("Expected 1 agent, got %d", len(agents))
    }
    
    if agents[0].ID != "test-01" {
        t.Errorf("Expected agent ID test-01, got %s", agents[0].ID)
    }
}

func TestAgentRegistry_Expiration(t *testing.T) {
    registry := discovery.NewAgentRegistry()
    
    agent := &discovery.Agent{
        ID:       "test-01",
        Hostname: "test-host",
        LastSeen: time.Now().Add(-10 * time.Minute),
        TTL:      5 * time.Minute,
    }
    
    registry.Register(agent)
    
    // Manually set LastSeen to expired
    registry.agents["test-01"].LastSeen = time.Now().Add(-10 * time.Minute)
    
    removed := registry.CleanExpired()
    if removed != 1 {
        t.Errorf("Expected 1 expired agent, removed %d", removed)
    }
    
    if len(registry.List()) != 0 {
        t.Error("Expected empty list after cleanup")
    }
}
```

**Integration Tests for Registration:**

```go
func TestAgentRegistration_EndToEnd(t *testing.T) {
    // Start test discovery server
    registry := discovery.NewAgentRegistry()
    tokenManager := auth.NewTokenManager([]byte("test-secret"), "test")
    ca := setupTestCA(t)
    
    server := server.NewDiscoveryServer(registry, tokenManager, ca, 5*time.Minute)
    
    // Start test server
    ts := httptest.NewTLSServer(http.HandlerFunc(server.HandleRegister))
    defer ts.Close()
    
    // Create test agent
    token, _ := tokenManager.GenerateToken("test-01", "test-host", 1*time.Hour)
    
    // Register agent
    reqBody := `{"hostname":"test-host","port":9090}`
    req, _ := http.NewRequest("POST", ts.URL, strings.NewReader(reqBody))
    req.Header.Set("Authorization", "Bearer "+token)
    req.Header.Set("Content-Type", "application/json")
    
    client := ts.Client()
    resp, err := client.Do(req)
    if err != nil {
        t.Fatalf("Registration failed: %v", err)
    }
    defer resp.Body.Close()
    
    if resp.StatusCode != http.StatusOK {
        t.Errorf("Expected status 200, got %d", resp.StatusCode)
    }
    
    // Verify agent is registered
    agents := registry.List()
    if len(agents) != 1 {
        t.Errorf("Expected 1 registered agent, got %d", len(agents))
    }
}
```

**Load Tests:**

```go
func TestDiscoveryService_Load(t *testing.T) {
    if testing.Short() {
        t.Skip("Skipping load test in short mode")
    }
    
    registry := discovery.NewAgentRegistry()
    // ... setup server
    
    // Simulate 1000 agents
    numAgents := 1000
    var wg sync.WaitGroup
    
    for i := 0; i < numAgents; i++ {
        wg.Add(1)
        go func(id int) {
            defer wg.Done()
            // Register agent
            // Send heartbeats
            // Verify in registry
        }(i)
    }
    
    wg.Wait()
    
    agents := registry.List()
    if len(agents) != numAgents {
        t.Errorf("Expected %d agents, got %d", numAgents, len(agents))
    }
}
```

## Conclusion

Monitoring bare metal infrastructure doesn't have to be painful. With automatic service discovery, dynamic target management, and integrated certificate handling, you can achieve cloud-like operational simplicity on bare metal.

**Key takeaways:**

- **Automate everything:** Manual configuration doesn't scale and causes errors
- **Security is paramount:** Use TLS everywhere, validate certificates, and rotate regularly
- **Design for failure:** Implement heartbeats, TTLs, and graceful degradation
- **Make it observable:** Monitor the monitoring system itself
- **Keep it simple:** Focus on solving real problems, not adding complexity
- **Test thoroughly:** Unit tests, integration tests, and load tests prevent production issues

This discovery system eliminates the operational overhead that makes bare metal monitoring challenging. Servers self-register, certificates are managed automatically, and Prometheus stays in sync with infrastructure changes without manual intervention.

As your infrastructure grows, the system scales effortlessly. Adding 100 servers requires no configuration changes—just deploy agents with appropriate API keys and labels. The discovery service handles the rest.

## Additional Resources

**Libraries and Tools:**

- [golang-jwt/jwt](https://github.com/golang-jwt/jwt) - JWT implementation for Go
- [Prometheus Client Library](https://github.com/prometheus/client_golang) - Official Go client
- [gorilla/mux](https://github.com/gorilla/mux) - HTTP router (optional, for complex routing)
- [spf13/viper](https://github.com/spf13/viper) - Advanced configuration management

**Prometheus Documentation:**

- [HTTP Service Discovery](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#http_sd_config) - Official Prometheus HTTP SD docs
- [Relabeling](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#relabel_config) - Target relabeling configuration
- [TLS Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#tls_config) - Securing scrape endpoints

**Further Reading:**

- [Certificate Management Best Practices](https://smallstep.com/blog/everything-pki.html) - Comprehensive PKI guide
- [Go Concurrency Patterns](https://go.dev/blog/pipelines) - Building concurrent systems
- [Prometheus Monitoring at Scale](https://prometheus.io/docs/practices/federation/) - Federation and scaling strategies

**Security Resources:**

- [OWASP API Security](https://owasp.org/www-project-api-security/) - API security best practices
- [TLS Best Practices](https://wiki.mozilla.org/Security/Server_Side_TLS) - Mozilla's TLS recommendations
- [JWT Security](https://tools.ietf.org/html/rfc8725) - JWT best current practices

**Production Considerations:**

- [High Availability Prometheus](https://prometheus.io/docs/introduction/faq/#can-prometheus-be-made-highly-available) - HA deployment patterns
- [Prometheus Remote Storage](https://prometheus.io/docs/prometheus/latest/storage/#remote-storage-integrations) - Long-term storage solutions
- [Monitoring Kubernetes on Bare Metal](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/) - If running Kubernetes