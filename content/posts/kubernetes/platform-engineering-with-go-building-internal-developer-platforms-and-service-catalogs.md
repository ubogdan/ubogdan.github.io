---
title: 'Platform Engineering with Go: Building Internal Developer Platforms and Service
  Catalogs'
date: 2026-06-13 10:30:00+02:00
tags:
- golang
- kubernetes
categories:
- DevOps
- Kubernetes
description: Design and implement an internal developer platform in Go with a practical
  service catalog, golden paths, and policy-driven automation for secure self-service
  delivery.
series: Kubernetes Mastery
draft: true
---

Platform engineering has quickly evolved from a niche concept into a practical operating model for modern software teams. As organizations scale to dozens or hundreds of services, traditional DevOps support models often become overloaded with repetitive requests: "create a service repository," "provision a database," "configure CI/CD," "add monitoring," and "set up production access." The result is predictable: slower delivery, inconsistent standards, and burned-out platform teams.

An **Internal Developer Platform (IDP)** solves this by productizing infrastructure and workflows. Instead of ticket-driven operations, developers get secure, self-service capabilities through curated interfaces and automation. The platform team shifts from being a manual service desk to a product team that builds reusable paved roads.

Go is an excellent language for building IDP components. It offers strong concurrency primitives, static binaries, fast startup, and a mature cloud-native ecosystem. Most CNCF tooling already embraces Go, which reduces operational friction and makes integrations with Kubernetes, GitOps, policy engines, and observability stacks straightforward.

In this article, you will learn how to design and implement a production-ready platform engineering approach with Go, including a practical service catalog architecture, API examples, golden path scaffolding, governance controls, and rollout strategies.

## Prerequisites

Before implementing a platform engineering stack, you should have:

- **Kubernetes fundamentals**: Deployments, RBAC, namespaces, ingress, and controllers
- **Go proficiency**: Structs, interfaces, HTTP APIs, testing, and modules
- **GitOps familiarity**: Basic ArgoCD or Flux workflows
- **Cloud and IaC experience**: Terraform and/or Crossplane concepts
- **Security baseline**: IAM, secrets management, and policy-as-code

## Why Platform Engineering Matters

A successful platform engineering initiative solves four recurring delivery problems:

1. **Cognitive overload**: Developers should not need deep expertise in every infrastructure domain.
2. **Inconsistent implementation**: Every service should start with secure, compliant defaults.
3. **Slow onboarding and provisioning**: Teams should ship in hours, not weeks.
4. **Weak governance at scale**: Policy should be automated and embedded in workflows.

The goal is not to hide infrastructure. The goal is to expose it through stable, well-designed abstractions that are safe by default and flexible when needed.

## IDP Reference Architecture

A practical IDP architecture usually includes these layers:

- **Developer interface layer**: CLI, web portal, or chat-based workflows
- **Catalog layer**: Source of truth for services, owners, environments, and dependencies
- **Automation layer**: Template rendering, repo bootstrapping, CI/CD creation, environment provisioning
- **Control layer**: Policy checks, drift detection, compliance rules, approval workflows
- **Runtime layer**: Kubernetes clusters, managed databases, queues, caches, and observability stack

A simplified flow looks like this:

```text
Developer -> Platform API/Portal -> Catalog -> Provisioning Pipeline -> GitOps -> Kubernetes/Cloud
                     |                 |               |
                     +---- Policy -----+---- Audit ----+
```

## Building a Service Catalog in Go

The service catalog is the heart of your platform. It should answer questions like:

- Who owns this service?
- What tier is it (critical, standard, internal)?
- Where is it deployed?
- What SLOs, runbooks, and dependencies exist?
- Is it compliant with platform standards?

### Core Domain Model

Start with a clear domain model that represents services and ownership.

```go
package catalog

import "time"

type Tier string

const (
    Tier0 Tier = "tier-0" // Business-critical
    Tier1 Tier = "tier-1"
    Tier2 Tier = "tier-2"
)

type Service struct {
    ID             string            `json:"id"`
    Name           string            `json:"name"`
    Description    string            `json:"description"`
    OwnerTeam      string            `json:"ownerTeam"`
    Runtime        string            `json:"runtime"`      // go, node, python
    Tier           Tier              `json:"tier"`
    RepositoryURL  string            `json:"repositoryUrl"`
    SlackChannel   string            `json:"slackChannel"`
    OnCallRotation string            `json:"onCallRotation"`
    Dependencies   []string          `json:"dependencies"`
    Environments   []Environment     `json:"environments"`
    Metadata       map[string]string `json:"metadata"`
    CreatedAt      time.Time         `json:"createdAt"`
    UpdatedAt      time.Time         `json:"updatedAt"`
}

type Environment struct {
    Name       string `json:"name"`       // dev, staging, prod
    Namespace  string `json:"namespace"`
    Cluster    string `json:"cluster"`
    IsCritical bool   `json:"isCritical"`
}
```

### API Design for Catalog Operations

Expose the catalog through a stable API. Keep contracts simple and versioned.

```go
package api

import (
    "encoding/json"
    "net/http"

    "github.com/go-chi/chi/v5"
)

type ServiceStore interface {
    Create(service Service) error
    GetByID(id string) (Service, error)
    List() ([]Service, error)
}

type Handler struct {
    store ServiceStore
}

func (h Handler) Routes() http.Handler {
    r := chi.NewRouter()
    r.Post("/api/v1/services", h.createService)
    r.Get("/api/v1/services", h.listServices)
    r.Get("/api/v1/services/{id}", h.getService)
    return r
}

func (h Handler) createService(w http.ResponseWriter, r *http.Request) {
    var s Service
    if err := json.NewDecoder(r.Body).Decode(&s); err != nil {
        http.Error(w, "invalid request body", http.StatusBadRequest)
        return
    }

    // Enforce minimum metadata contract for governance.
    if s.OwnerTeam == "" || s.RepositoryURL == "" || s.Tier == "" {
        http.Error(w, "ownerTeam, repositoryUrl and tier are required", http.StatusBadRequest)
        return
    }

    if err := h.store.Create(s); err != nil {
        http.Error(w, "failed to create service", http.StatusInternalServerError)
        return
    }

    w.WriteHeader(http.StatusCreated)
}
```

**Tip:** Back your catalog with PostgreSQL for transactional consistency, then replicate into OpenSearch or ClickHouse for fast discovery and analytics if needed.

## Golden Paths: Standardized Scaffolding That Teams Actually Use

A platform succeeds when the easiest path is the correct path. Golden paths should include:

- Service templates (API, worker, cron, event consumer)
- Default CI/CD pipeline with security and quality gates
- Standard observability setup (logs, metrics, traces)
- Deployment manifests and autoscaling defaults
- Incident and runbook templates

A common project template structure:

```text
service-template/
├── cmd/api/main.go
├── internal/
│   ├── app/
│   ├── handlers/
│   └── middleware/
├── deploy/
│   ├── base/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── hpa.yaml
│   └── overlays/
│       ├── staging/
│       └── production/
├── .github/workflows/
│   ├── ci.yaml
│   └── cd.yaml
├── Makefile
└── README.md
```

Use Go's templating engine to render scaffold variables safely.

```go
package scaffolder

import (
    "bytes"
    "text/template"
)

type TemplateInput struct {
    ServiceName string
    Team        string
    Port        int
}

func Render(templateText string, in TemplateInput) (string, error) {
    t, err := template.New("scaffold").Parse(templateText)
    if err != nil {
        return "", err
    }

    var out bytes.Buffer
    if err := t.Execute(&out, in); err != nil {
        return "", err
    }

    return out.String(), nil
}
```

## Self-Service Provisioning with Policy-Driven Guardrails

Self-service without guardrails creates chaos. Guardrails without self-service creates bottlenecks. You need both.

### Recommended Control Points

- **Pre-provision checks**: Validate naming, ownership, and environment policies
- **Pipeline gates**: SAST, dependency scanning, unit test thresholds, IaC policies
- **Admission controls**: Enforce runtime policies in Kubernetes (Kyverno or OPA Gatekeeper)
- **Drift detection**: Reconcile desired state continuously via GitOps

A minimal OPA policy for required labels:

```rego
package kubernetes.admission

deny[msg] {
  input.request.kind.kind == "Deployment"
  not input.request.object.metadata.labels["owner-team"]
  msg := "Deployment is missing required label: owner-team"
}

deny[msg] {
  input.request.kind.kind == "Deployment"
  not input.request.object.metadata.labels["service-tier"]
  msg := "Deployment is missing required label: service-tier"
}
```

## Integrating Catalog + GitOps + Kubernetes

A robust delivery pipeline typically follows this sequence:

1. Developer creates service via portal or CLI.
2. Platform API registers service in catalog.
3. Scaffolder creates repository from a golden template.
4. Pipeline provisions required resources (database, queue, secrets, DNS).
5. ArgoCD/Flux syncs manifests to target clusters.
6. Platform updates catalog with deployment and health metadata.

This loop gives you full traceability from ownership metadata to runtime state.

## Service Scorecards: Turning Standards into Measurable Outcomes

Static documentation is not enough. Add scorecards that continuously evaluate service health and compliance.

Example score dimensions:

- **Reliability**: SLO definitions, alert quality, incident MTTR trend
- **Security**: Dependency freshness, image signing, secret hygiene
- **Operability**: Runbook completeness, dashboard coverage, on-call assignment
- **Delivery**: Lead time, change failure rate, deployment frequency

A simple score calculator in Go:

```go
package scorecard

type Input struct {
    HasSLO              bool
    HasRunbook          bool
    ImageSigned         bool
    DependencyFreshness int // 0-100
    AlertCoverage       int // 0-100
}

func Calculate(in Input) int {
    score := 0

    if in.HasSLO {
        score += 20
    }
    if in.HasRunbook {
        score += 20
    }
    if in.ImageSigned {
        score += 20
    }

    score += in.DependencyFreshness / 2 // max 50 -> clipped below
    score += in.AlertCoverage / 2

    if score > 100 {
        return 100
    }
    return score
}
```

Use these scores to guide coaching and platform roadmap priorities instead of creating punitive controls.

## Designing an Effective Developer Experience

Platform engineering is as much product design as infrastructure engineering. Treat developers as customers.

Best practices:

- **Start with top pain points**: Onboarding, environment setup, and production rollout
- **Prefer progressive complexity**: Offer sane defaults first, advanced options second
- **Document through examples**: Working templates beat long theoretical docs
- **Instrument user journeys**: Measure request-to-deploy time and drop-off points
- **Run platform office hours**: Close feedback loops weekly

If adoption is low, the problem is usually usability, not user resistance.

## Common Pitfalls and How to Avoid Them

### 1. Building the platform in isolation
Create a platform guild with representatives from app teams, security, and operations.

### 2. Over-abstracting infrastructure
Expose useful knobs (resource limits, scaling strategy, data retention) while keeping safe defaults.

### 3. Ignoring migration strategy
Support brownfield services with import workflows and incremental compliance adoption.

### 4. Measuring only technical metrics
Track platform product metrics too: adoption, satisfaction, and time saved per team.

### 5. Treating the catalog as static documentation
Continuously sync runtime and pipeline metadata to keep it trustworthy.

## Rollout Strategy for Real Organizations

A pragmatic rollout model:

- **Phase 1 (4-6 weeks)**: Build catalog MVP, one golden path, basic provisioning
- **Phase 2 (6-10 weeks)**: Add policy gates, GitOps integration, and scorecards
- **Phase 3 (ongoing)**: Expand templates, improve UX, automate upgrade paths

Start with one or two teams that are motivated to co-design. Early success stories drive broader adoption more effectively than top-down mandates.

## Conclusion

Platform engineering with Go gives organizations a practical way to scale software delivery without sacrificing reliability, security, or developer autonomy. A well-designed internal developer platform reduces cognitive load, standardizes best practices, and accelerates shipping through self-service workflows.

The service catalog is the foundation that connects ownership, architecture, compliance, and runtime reality. Combined with golden paths, policy-as-code, and GitOps, it turns DevOps from a collection of manual tasks into a cohesive product experience for engineering teams.

If you build the platform as a product, measure outcomes, and continuously improve based on developer feedback, you will create a durable competitive advantage: teams that deliver faster with fewer incidents and less operational friction.

