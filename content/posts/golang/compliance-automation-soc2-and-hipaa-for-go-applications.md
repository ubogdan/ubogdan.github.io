---
title: "Compliance Automation: SOC2 and HIPAA for Go Applications"
date: 2025-10-22T14:46:33+03:00
tags: ["security", "golang"]
categories: ["SecOps", "Programming"]
description: "Automate compliance requirements and audit trails for Go applications meeting SOC2 and HIPAA standards."
series: "Security Operations"
draft: true
---

# Compliance Automation: SOC2 and HIPAA for Go Applications

In today's regulatory landscape, compliance isn't just a checkbox—it's a critical business requirement that can make or break your organization. Whether you're handling sensitive customer data or protected health information, meeting standards like **SOC2** and **HIPAA** is essential for maintaining trust and avoiding costly penalties. For Go applications, implementing compliance automation can streamline audits, reduce human error, and ensure continuous adherence to regulatory requirements.

This comprehensive guide will walk you through building robust compliance automation systems in Go, covering everything from audit logging to automated policy enforcement. We'll explore practical implementations that not only meet regulatory requirements but also integrate seamlessly into your existing DevOps workflows.

## Prerequisites

Before diving into compliance automation, you should have:

- **Intermediate to advanced Go programming skills**
- **Understanding of web application security principles**
- **Familiarity with logging and monitoring concepts**
- **Basic knowledge of database design and transactions**
- **Understanding of SOC2 Type II and HIPAA requirements**
- **Experience with Docker and containerization**
- **Knowledge of CI/CD pipelines**

You'll also need:
- Go 1.19 or later
- PostgreSQL or similar database
- Redis for caching and session management
- Docker for containerization

## Understanding SOC2 and HIPAA Requirements

### SOC2 Trust Service Criteria

SOC2 focuses on five trust service criteria:

- **Security**: Protection against unauthorized access
- **Availability**: System operational availability
- **Processing Integrity**: Complete, valid, accurate processing
- **Confidentiality**: Information designated as confidential
- **Privacy**: Personal information collection, use, retention, and disposal

### HIPAA Key Requirements

HIPAA compliance centers on:

- **Administrative Safeguards**: Policies and procedures
- **Physical Safeguards**: Physical access controls
- **Technical Safeguards**: Access controls, audit controls, integrity, transmission security

## Building a Compliance Framework in Go

### Core Compliance Package Structure

Let's start by creating a comprehensive compliance framework:

```go
// pkg/compliance/types.go
package compliance

import (
    "context"
    "time"
)

// ComplianceEvent represents any action that needs to be audited
type ComplianceEvent struct {
    ID          string                 `json:"id" db:"id"`
    Timestamp   time.Time              `json:"timestamp" db:"timestamp"`
    EventType   EventType              `json:"event_type" db:"event_type"`
    UserID      string                 `json:"user_id" db:"user_id"`
    ResourceID  string                 `json:"resource_id" db:"resource_id"`
    Action      string                 `json:"action" db:"action"`
    Result      ActionResult           `json:"result" db:"result"`
    IPAddress   string                 `json:"ip_address" db:"ip_address"`
    UserAgent   string                 `json:"user_agent" db:"user_agent"`
    Metadata    map[string]interface{} `json:"metadata" db:"metadata"`
    Severity    SeverityLevel          `json:"severity" db:"severity"`
    Compliance  ComplianceStandard     `json:"compliance" db:"compliance"`
}

type EventType string

const (
    EventTypeAuthentication EventType = "authentication"
    EventTypeAuthorization  EventType = "authorization"
    EventTypeDataAccess     EventType = "data_access"
    EventTypeDataModify     EventType = "data_modify"
    EventTypeSystemAccess   EventType = "system_access"
    EventTypeConfiguration  EventType = "configuration"
    EventTypeBackup         EventType = "backup"
    EventTypeRestore        EventType = "restore"
)

type ActionResult string

const (
    ResultSuccess ActionResult = "success"
    ResultFailure ActionResult = "failure"
    ResultDenied  ActionResult = "denied"
)

type SeverityLevel string

const (
    SeverityLow      SeverityLevel = "low"
    SeverityMedium   SeverityLevel = "medium"
    SeverityHigh     SeverityLevel = "high"
    SeverityCritical SeverityLevel = "critical"
)

type ComplianceStandard string

const (
    StandardSOC2  ComplianceStandard = "soc2"
    StandardHIPAA ComplianceStandard = "hipaa"
    StandardBoth  ComplianceStandard = "both"
)
```

### Audit Logger Implementation

```go
// pkg/compliance/audit.go
package compliance

import (
    "context"
    "crypto/sha256"
    "database/sql"
    "encoding/hex"
    "encoding/json"
    "fmt"
    "log/slog"
    "time"

    "github.com/google/uuid"
    "github.com/lib/pq"
)

type AuditLogger struct {
    db     *sql.DB
    logger *slog.Logger
    config AuditConfig
}

type AuditConfig struct {
    RetentionDays   int
    EncryptMetadata bool
    AsyncLogging    bool
    BatchSize       int
    FlushInterval   time.Duration
}

func NewAuditLogger(db *sql.DB, logger *slog.Logger, config AuditConfig) *AuditLogger {
    return &AuditLogger{
        db:     db,
        logger: logger,
        config: config,
    }
}

// LogEvent records a compliance event with full audit trail
func (al *AuditLogger) LogEvent(ctx context.Context, event ComplianceEvent) error {
    // Generate unique event ID
    event.ID = uuid.New().String()
    event.Timestamp = time.Now().UTC()

    // Validate required fields
    if err := al.validateEvent(event); err != nil {
        return fmt.Errorf("event validation failed: %w", err)
    }

    // Encrypt sensitive metadata if required
    if al.config.EncryptMetadata {
        if err := al.encryptMetadata(&event); err != nil {
            al.logger.Error("Failed to encrypt metadata", 
                "event_id", event.ID, 
                "error", err)
            return fmt.Errorf("metadata encryption failed: %w", err)
        }
    }

    // Store event
    if al.config.AsyncLogging {
        return al.logEventAsync(ctx, event)
    }
    return al.logEventSync(ctx, event)
}

func (al *AuditLogger) logEventSync(ctx context.Context, event ComplianceEvent) error {
    query := `
        INSERT INTO compliance_events (
            id, timestamp, event_type, user_id, resource_id, action, 
            result, ip_address, user_agent, metadata, severity, compliance
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`

    metadataJSON, err := json.Marshal(event.Metadata)
    if err != nil {
        return fmt.Errorf("failed to marshal metadata: %w", err)
    }

    _, err = al.db.ExecContext(ctx, query,
        event.ID, event.Timestamp, event.EventType, event.UserID,
        event.ResourceID, event.Action, event.Result, event.IPAddress,
        event.UserAgent, metadataJSON, event.Severity, event.Compliance)

    if err != nil {
        al.logger.Error("Failed to insert compliance event",
            "event_id", event.ID,
            "error", err)
        return fmt.Errorf("database insert failed: %w", err)
    }

    al.logger.Info("Compliance event logged",
        "event_id", event.ID,
        "event_type", event.EventType,
        "user_id", event.UserID,
        "action", event.Action,
        "result", event.Result)

    return nil
}

func (al *AuditLogger) validateEvent(event ComplianceEvent) error {
    if event.EventType == "" {
        return fmt.Errorf("event_type is required")
    }
    if event.Action == "" {
        return fmt.Errorf("action is required")
    }
    if event.Result == "" {
        return fmt.Errorf("result is required")
    }
    if event.Compliance == "" {
        return fmt.Errorf("compliance standard is required")
    }
    return nil
}

func (al *AuditLogger) encryptMetadata(event *ComplianceEvent) error {
    if event.Metadata == nil || len(event.Metadata) == 0 {
        return nil
    }

    // Simple hash-based encryption for demo (use proper encryption in production)
    metadataJSON, err := json.Marshal(event.Metadata)
    if err != nil {
        return err
    }

    hash := sha256.Sum256(metadataJSON)
    event.Metadata = map[string]interface{}{
        "encrypted": true,
        "hash":      hex.EncodeToString(hash[:]),
        "data":      hex.EncodeToString(metadataJSON),
    }

    return nil
}
```

### Access Control and Authorization

```go
// pkg/compliance/access.go
package compliance

import (
    "context"
    "fmt"
    "net/http"
    "strings"
    "time"
)

type AccessController struct {
    auditLogger *AuditLogger
    policies    map[string]AccessPolicy
}

type AccessPolicy struct {
    Resource    string            `json:"resource"`
    Actions     []string          `json:"actions"`
    Conditions  map[string]string `json:"conditions"`
    Compliance  ComplianceStandard `json:"compliance"`
    RequiresMFA bool              `json:"requires_mfa"`
}

type AccessRequest struct {
    UserID      string            `json:"user_id"`
    Resource    string            `json:"resource"`
    Action      string            `json:"action"`
    Context     map[string]string `json:"context"`
    IPAddress   string            `json:"ip_address"`
    UserAgent   string            `json:"user_agent"`
    SessionID   string            `json:"session_id"`
}

func NewAccessController(auditLogger *AuditLogger) *AccessController {
    return &AccessController{
        auditLogger: auditLogger,
        policies:    make(map[string]AccessPolicy),
    }
}

// CheckAccess validates access request against compliance policies
func (ac *AccessController) CheckAccess(ctx context.Context, req AccessRequest) (bool, error) {
    startTime := time.Now()

    // Log access attempt
    event := ComplianceEvent{
        EventType:   EventTypeAuthorization,
        UserID:      req.UserID,
        ResourceID:  req.Resource,
        Action:      req.Action,
        IPAddress:   req.IPAddress,
        UserAgent:   req.UserAgent,
        Metadata: map[string]interface{}{
            "session_id": req.SessionID,
            "context":    req.Context,
        },
        Severity:   SeverityMedium,
        Compliance: StandardBoth,
    }

    // Find applicable policy
    policy, exists := ac.policies[req.Resource]
    if !exists {
        event.Result = ResultDenied
        event.Metadata["reason"] = "no_policy_found"
        ac.auditLogger.LogEvent(ctx, event)
        return false, fmt.Errorf("no access policy found for resource: %s", req.Resource)
    }

    // Check if action is allowed
    if !ac.isActionAllowed(policy.Actions, req.Action) {
        event.Result = ResultDenied
        event.Metadata["reason"] = "action_not_allowed"
        ac.auditLogger.LogEvent(ctx, event)
        return false, nil
    }

    // Evaluate conditions
    if !ac.evaluateConditions(policy.Conditions, req.Context) {
        event.Result = ResultDenied
        event.Metadata["reason"] = "conditions_not_met"
        ac.auditLogger.LogEvent(ctx, event)
        return false, nil
    }

    // Check MFA requirement for HIPAA compliance
    if policy.RequiresMFA && policy.Compliance == StandardHIPAA {
        if !ac.verifyMFA(req.SessionID) {
            event.Result = ResultDenied
            event.Metadata["reason"] = "mfa_required"
            event.Severity = SeverityHigh
            ac.auditLogger.LogEvent(ctx, event)
            return false, nil
        }
    }

    // Access granted
    event.Result = ResultSuccess
    event.Metadata["policy_matched"] = policy.Resource
    event.Metadata["duration_ms"] = time.Since(startTime).Milliseconds()
    ac.auditLogger.LogEvent(ctx, event)

    return true, nil
}

func (ac *AccessController) isActionAllowed(allowedActions []string, requestedAction string) bool {
    for _, action := range allowedActions {
        if action == "*" || action == requestedAction {
            return true
        }
    }
    return false
}

func (ac *AccessController) evaluateConditions(conditions map[string]string, context map[string]string) bool {
    for key, expectedValue := range conditions {
        if actualValue, exists := context[key]; !exists || actualValue != expectedValue {
            return false
        }
    }
    return true
}

func (ac *AccessController) verifyMFA(sessionID string) bool {
    // Implement MFA verification logic
    // This is a simplified version
    return strings.Contains(sessionID, "mfa_verified")
}

// RegisterPolicy adds a new access policy
func (ac *AccessController) RegisterPolicy(policy AccessPolicy) {
    ac.policies[policy.Resource] = policy
}
```

### HTTP Middleware for Compliance

```go
// pkg/compliance/middleware.go
package compliance

import (
    "context"
    "net/http"
    "time"
)

type ComplianceMiddleware struct {
    auditLogger      *AuditLogger
    accessController *AccessController
}

func NewComplianceMiddleware(auditLogger *AuditLogger, accessController *AccessController) *ComplianceMiddleware {
    return &ComplianceMiddleware{
        auditLogger:      auditLogger,
        accessController: accessController,
    }
}

// AuditMiddleware logs all HTTP requests for compliance
func (cm *ComplianceMiddleware) AuditMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        startTime := time.Now()
        
        // Create response writer wrapper to capture status code
        wrappedWriter := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}
        
        // Process request
        next.ServeHTTP(wrappedWriter, r)
        
        // Log the request
        event := ComplianceEvent{
            EventType:  EventTypeSystemAccess,
            UserID:     getUserID(r),
            ResourceID: r.URL.Path,
            Action:     r.Method,
            Result:     getResultFromStatus(wrappedWriter.statusCode),
            IPAddress:  getClientIP(r),
            UserAgent:  r.UserAgent(),
            Metadata: map[string]interface{}{
                "status_code":   wrappedWriter.statusCode,
                "duration_ms":   time.Since(startTime).Milliseconds(),
                "content_length": wrappedWriter.bytesWritten,
                "query_params":  r.URL.RawQuery,
            },
            Severity:   getSeverityFromStatus(wrappedWriter.statusCode),
            Compliance: StandardBoth,
        }
        
        cm.auditLogger.LogEvent(r.Context(), event)
    })
}

// AuthorizationMiddleware enforces access control
func (cm *ComplianceMiddleware) AuthorizationMiddleware(resource string) func(http