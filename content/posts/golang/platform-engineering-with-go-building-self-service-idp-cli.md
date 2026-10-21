---
title: "Platform Engineering with Go: Building a Self-Service Internal Developer Platform CLI"
date: 2026-03-21T10:00:00+02:00
publishDate: 2026-03-21T10:00:00+02:00
lastmod: 2026-03-21
draft: false
thumbnail: "images/platform-engineering-go-idp-cli.png"
description: "Learn how to build a self-service Internal Developer Platform (IDP) CLI in Go using Cobra. Empower your engineering teams with automated workflows, golden paths, and self-service infrastructure provisioning that reduces cognitive load and accelerates delivery."
categories:
  - "DevOps"
  - "Programming"
tags:
  - "golang"
  - "automation"
---

Platform engineering has emerged as the natural evolution of DevOps, addressing a critical problem that plagues growing engineering organizations: **cognitive overload**. As infrastructure complexity explodes—Kubernetes, Terraform, CI/CD pipelines, observability stacks, secrets management—developers increasingly spend time fighting tooling instead of shipping features.

The solution is an **Internal Developer Platform (IDP)**: a curated, self-service layer that abstracts away infrastructure complexity and provides developers with "golden paths" to production. At the heart of many successful IDPs sits a command-line interface (CLI) that developers use daily to scaffold services, provision resources, and deploy applications.

In this guide, you'll build a production-grade IDP CLI in Go using the Cobra framework. Go is the de facto language for platform tooling—it powers Kubernetes, Docker, Terraform, and countless cloud-native tools—thanks to its single-binary distribution, excellent concurrency, and robust standard library.

<!--more-->

## Why Platform Engineering Matters

Before diving into code, it's worth understanding the problem space. Traditional DevOps promised "you build it, you run it," but this often resulted in every team reinventing the wheel—writing their own Terraform modules, crafting bespoke CI pipelines, and debugging Kubernetes YAML at 2 AM.

Platform engineering flips this model. Instead of expecting every developer to be an infrastructure expert, a dedicated platform team builds **reusable, self-service capabilities** that the rest of the organization consumes.

### The Core Principles

- **Self-Service**: Developers provision what they need without filing tickets or waiting on ops teams
- **Golden Paths**: Opinionated, well-supported routes to production that encode best practices
- **Reduced Cognitive Load**: Abstract away the underlying complexity; developers focus on business logic
- **Guardrails, Not Gates**: Enable autonomy while enforcing security and compliance automatically
- **Treating the Platform as a Product**: Internal developers are customers; their experience matters

### Why a CLI?

While many IDPs include web portals (like Backstage), a CLI remains essential because developers live in the terminal. A well-designed CLI:

- Integrates seamlessly into existing workflows and scripts
- Works in CI/CD pipelines without a browser
- Provides fast, keyboard-driven interactions
- Distributes as a single binary with zero dependencies (thanks to Go)

## Setting Up the Project

Let's start by scaffolding our CLI project. We'll call it `idp` (Internal Developer Platform).

```bash
mkdir idp && cd idp
go mod init github.com/yourorg/idp
go get github.com/spf13/cobra@latest
go get github.com/spf13/viper@latest
```

Here's the project structure we'll build:

```
idp/
├── main.go
├── cmd/
│   ├── root.go
│   ├── service.go
│   ├── deploy.go
│   └── env.go
├── internal/
│   ├── scaffold/
│   │   └── scaffold.go
│   ├── provision/
│   │   └── provision.go
│   └── config/
│       └── config.go
├── templates/
│   └── service/
│       ├── main.go.tmpl
│       └── Dockerfile.tmpl
├── go.mod
└── go.sum
```

## Building the Root Command

Cobra organizes CLIs around commands. The root command is the entry point that ties everything together. Let's create `cmd/root.go`:

```go
package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var (
	cfgFile string
	verbose bool
)

// rootCmd represents the base command when called without any subcommands.
var rootCmd = &cobra.Command{
	Use:   "idp",
	Short: "Internal Developer Platform CLI",
	Long: `idp is a self-service CLI for the Internal Developer Platform.

It empowers developers to scaffold services, provision infrastructure,
and deploy applications through curated golden paths—without needing
deep knowledge of the underlying infrastructure.`,
	Version: "1.0.0",
}

// Execute adds all child commands to the root command and sets flags appropriately.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func init() {
	cobra.OnInitialize(initConfig)

	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "",
		"config file (default is $HOME/.idp.yaml)")
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false,
		"enable verbose output")
}

// initConfig reads in config file and ENV variables if set.
func initConfig() {
	if cfgFile != "" {
		viper.SetConfigFile(cfgFile)
	} else {
		home, err := os.UserHomeDir()
		cobra.CheckErr(err)

		viper.AddConfigPath(home)
		viper.SetConfigType("yaml")
		viper.SetConfigName(".idp")
	}

	// Allow environment variables to override config (IDP_REGISTRY, etc.)
	viper.SetEnvPrefix("IDP")
	viper.AutomaticEnv()

	if err := viper.ReadInConfig(); err == nil && verbose {
		fmt.Fprintln(os.Stderr, "Using config file:", viper.ConfigFileUsed())
	}
}
```

And a minimal `main.go`:

```go
package main

import "github.com/yourorg/idp/cmd"

func main() {
	cmd.Execute()
}
```

The root command establishes our configuration strategy using Viper, which gives us a powerful precedence chain: **command-line flags > environment variables > config file > defaults**. This flexibility is crucial for an IDP CLI that must work in local development, CI pipelines, and automated scripts.

## The `service create` Command: Scaffolding Golden Paths

The most impactful IDP feature is scaffolding new services from templates. Instead of copy-pasting from an old repo, a developer runs a single command and gets a production-ready service with CI/CD, observability, and security baked in.

Let's create `cmd/service.go`:

```go
package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
	"github.com/yourorg/idp/internal/scaffold"
)

var (
	serviceName     string
	serviceTemplate string
	serviceOwner    string
)

var serviceCmd = &cobra.Command{
	Use:   "service",
	Short: "Manage services on the platform",
	Long:  "Create, list, and manage services through golden-path templates.",
}

var serviceCreateCmd = &cobra.Command{
	Use:   "create [name]",
	Short: "Scaffold a new service from a golden-path template",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		serviceName = args[0]

		opts := scaffold.Options{
			Name:     serviceName,
			Template: serviceTemplate,
			Owner:    serviceOwner,
		}

		fmt.Printf("🚀 Scaffolding service %q using the %q template...\n",
			serviceName, serviceTemplate)

		if err := scaffold.Generate(opts); err != nil {
			return fmt.Errorf("failed to scaffold service: %w", err)
		}

		fmt.Printf("✅ Service %q created successfully!\n", serviceName)
		fmt.Println("\nNext steps:")
		fmt.Printf("  cd %s\n", serviceName)
		fmt.Println("  idp deploy --env dev")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(serviceCmd)
	serviceCmd.AddCommand(serviceCreateCmd)

	serviceCreateCmd.Flags().StringVarP(&serviceTemplate, "template", "t",
		"go-http", "service template (go-http, go-grpc, worker)")
	serviceCreateCmd.Flags().StringVarP(&serviceOwner, "owner", "o",
		"", "owning team (required)")
	serviceCreateCmd.MarkFlagRequired("owner")
}
```

Notice how we use `RunE` (rather than `Run`) to return errors idiomatically, and `MarkFlagRequired` to enforce that every service has an owner—a small guardrail that pays dividends for accountability and on-call routing.

## Implementing the Scaffolding Engine

Now let's build the engine that turns templates into real files. Go's `text/template` package combined with `embed` lets us bundle templates directly into the binary—no external files to distribute.

Create `internal/scaffold/scaffold.go`:

```go
package scaffold

import (
	"embed"
	"fmt"
	"os"
	"path/filepath"
	"text/template"
	"time"
)

//go:embed templates/*
var templateFS embed.FS

// Options configures service scaffolding.
type Options struct {
	Name     string
	Template string
	Owner    string
}

// templateData is passed to each template during rendering.
type templateData struct {
	Name      string
	Owner     string
	Module    string
	CreatedAt string
}

// Generate scaffolds a new service directory from the chosen template.
func Generate(opts Options) error {
	if err := validate(opts); err != nil {
		return err
	}

	data := templateData{
		Name:      opts.Name,
		Owner:     opts.Owner,
		Module:    fmt.Sprintf("github.com/yourorg/%s", opts.Name),
		CreatedAt: time.Now().Format(time.RFC3339),
	}

	// Create the target directory.
	if err := os.MkdirAll(opts.Name, 0o755); err != nil {
		return fmt.Errorf("creating directory: %w", err)
	}

	templateDir := filepath.Join("templates", opts.Template)
	entries, err := templateFS.ReadDir(templateDir)
	if err != nil {
		return fmt.Errorf("unknown template %q: %w", opts.Template, err)
	}

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		if err := renderFile(templateDir, entry.Name(), opts.Name, data); err != nil {
			return err
		}
	}

	return nil
}

// renderFile reads a template, executes it, and writes the result.
func renderFile(templateDir, fileName, destDir string, data templateData) error {
	content, err := templateFS.ReadFile(filepath.Join(templateDir, fileName))
	if err != nil {
		return fmt.Errorf("reading template %s: %w", fileName, err)
	}

	tmpl, err := template.New(fileName).Parse(string(content))
	if err != nil {
		return fmt.Errorf("parsing template %s: %w", fileName, err)
	}

	// Strip the .tmpl suffix for the output filename.
	outName := fileName[:len(fileName)-len(".tmpl")]
	outPath := filepath.Join(destDir, outName)

	f, err := os.Create(outPath)
	if err != nil {
		return fmt.Errorf("creating %s: %w", outPath, err)
	}
	defer f.Close()

	if err := tmpl.Execute(f, data); err != nil {
		return fmt.Errorf("rendering %s: %w", outName, err)
	}

	return nil
}

func validate(opts Options) error {
	if opts.Name == "" {
		return fmt.Errorf("service name is required")
	}
	if opts.Owner == "" {
		return fmt.Errorf("service owner is required")
	}
	return nil
}
```

A sample template `internal/scaffold/templates/go-http/main.go.tmpl` might look like:

```go
// Service: {{ .Name }}
// Owner: {{ .Owner }}
// Generated: {{ .CreatedAt }}
package main

import (
	"log"
	"net/http"
)

func main() {
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	log.Println("{{ .Name }} listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
```

By embedding templates with `//go:embed`, the entire golden path travels inside the single `idp` binary. This is a superpower of Go for platform tooling—developers download one file and immediately have access to every opinionated template your platform team maintains.

## The `deploy` Command: Self-Service Deployment

Deployment is where self-service shines. Rather than asking developers to understand Kubernetes manifests or Helm charts, we give them a simple, environment-aware command.

Create `cmd/deploy.go`:

```go
package cmd

import (
	"context"
	"fmt"
	"time"

	"github.com/spf13/cobra"
	"github.com/yourorg/idp/internal/provision"
)

var (
	deployEnv   string
	deployWait  bool
	deployTimeout time.Duration
)

var deployCmd = &cobra.Command{
	Use:   "deploy",
	Short: "Deploy the current service to an environment",
	Long: `Deploy builds, pushes, and rolls out the current service
to the specified environment using the platform's golden deployment path.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(cmd.Context(), deployTimeout)
		defer cancel()

		deployer := provision.NewDeployer(deployEnv, verbose)

		fmt.Printf("📦 Deploying to %s...\n", deployEnv)

		result, err := deployer.Run(ctx, deployWait)
		if err != nil {
			return fmt.Errorf("deployment failed: %w", err)
		}

		fmt.Printf("✅ Deployed %s to %s (revision %s)\n",
			result.Service, deployEnv, result.Revision)
		fmt.Printf("🔗 URL: %s\n", result.URL)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(deployCmd)

	deployCmd.Flags().StringVarP(&deployEnv, "env", "e", "dev",
		"target environment (dev, staging, prod)")
	deployCmd.Flags().BoolVar(&deployWait, "wait", true,
		"wait for the rollout to complete")
	deployCmd.Flags().DurationVar(&deployTimeout, "timeout", 5*time.Minute,
		"deployment timeout")
}
```

The key insight here is **context propagation**. We create a `context.Context` with a timeout and pass it down through the deployment logic. This lets us cancel long-running operations gracefully—a critical pattern for any production CLI that interacts with remote systems.

## Provisioning with Concurrency and Guardrails

Here's where Go's concurrency model becomes invaluable. A single deployment often triggers multiple parallel operations: building the image, running security scans, and provisioning dependent resources. Let's look at `internal/provision/provision.go`:

```go
package provision

import (
	"context"
	"fmt"
	"time"
)

// Deployer orchestrates a deployment to a target environment.
type Deployer struct {
	env     string
	verbose bool
}

// Result captures the outcome of a deployment.
type Result struct {
	Service  string
	Revision string
	URL      string
}

func NewDeployer(env string, verbose bool) *Deployer {
	return &Deployer{env: env, verbose: verbose}
}

// Run executes the deployment pipeline with guardrails per environment.
func (d *Deployer) Run(ctx context.Context, wait bool) (*Result, error) {
	// Guardrail: production deployments require extra validation.
	if d.env == "prod" {
		if err := d.validateProductionReadiness(ctx); err != nil {
			return nil, fmt.Errorf("production guardrail failed: %w", err)
		}
	}

	// Run independent pipeline stages concurrently.
	type stageResult struct {
		name string
		err  error
	}

	stages := []struct {
		name string
		fn   func(context.Context) error
	}{
		{"build", d.build},
		{"security-scan", d.securityScan},
		{"provision-resources", d.provisionResources},
	}

	results := make(chan stageResult, len(stages))
	for _, stage := range stages {
		go func(name string, fn func(context.Context) error) {
			results <- stageResult{name: name, err: fn(ctx)}
		}(stage.name, stage.fn)
	}

	for range stages {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case res := <-results:
			if res.err != nil {
				return nil, fmt.Errorf("%s stage failed: %w", res.name, res.err)
			}
			if d.verbose {
				fmt.Printf("  ✓ %s completed\n", res.name)
			}
		}
	}

	return &Result{
		Service:  "example-service",
		Revision: fmt.Sprintf("r-%d", time.Now().Unix()),
		URL:      fmt.Sprintf("https://%s.%s.platform.internal", "example-service", d.env),
	}, nil
}

func (d *Deployer) validateProductionReadiness(ctx context.Context) error {
	// Enforce guardrails: require passing tests, approved change window, etc.
	return nil
}

func (d *Deployer) build(ctx context.Context) error {
	// Build and push the container image.
	time.Sleep(500 * time.Millisecond)
	return nil
}

func (d *Deployer) securityScan(ctx context.Context) error {
	// Run container and dependency vulnerability scans.
	time.Sleep(300 * time.Millisecond)
	return nil
}

func (d *Deployer) provisionResources(ctx context.Context) error {
	// Provision databases, queues, secrets via Terraform/Crossplane.
	time.Sleep(400 * time.Millisecond)
	return nil
}
```

This pattern demonstrates two platform engineering essentials:

1. **Environment-specific guardrails**: Production deployments trigger additional validation, enforcing safety without blocking developer velocity in lower environments.
2. **Concurrent pipeline stages**: Independent operations run in parallel using goroutines, with results collected through a channel. The `select` on `ctx.Done()` ensures we respect cancellation and timeouts.

## Environment Management

Rounding out the CLI, let's add an `env` command so developers can inspect and switch contexts. Create `cmd/env.go`:

```go
package cmd

import (
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/spf13/cobra"
)

var envCmd = &cobra.Command{
	Use:   "env",
	Short: "Manage platform environments",
}

var envListCmd = &cobra.Command{
	Use:   "list",
	Short: "List available environments",
	Run: func(cmd *cobra.Command, args []string) {
		w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
		fmt.Fprintln(w, "ENVIRONMENT\tCLUSTER\tREGION\tSTATUS")
		fmt.Fprintln(w, "dev\tdev-cluster\teu-central-1\tactive")
		fmt.Fprintln(w, "staging\tstg-cluster\teu-central-1\tactive")
		fmt.Fprintln(w, "prod\tprod-cluster\teu-west-1\tactive")
		w.Flush()
	},
}

func init() {
	rootCmd.AddCommand(envCmd)
	envCmd.AddCommand(envListCmd)
}
```

Using `text/tabwriter` from the standard library gives us cleanly aligned columnar output—a small touch that dramatically improves the developer experience.

## Putting It All Together

With all commands wired up, developers interact with the platform through an intuitive interface:

```bash
# Scaffold a new service from a golden path
idp service create payments-api --template go-http --owner team-payments

# Deploy to the dev environment
cd payments-api
idp deploy --env dev

# Inspect available environments
idp env list

# Promote to production (triggers extra guardrails)
idp deploy --env prod --wait
```

Behind each of these simple commands lies the accumulated expertise of your platform team—best-practice templates, security scanning, concurrency, and guardrails—all packaged into a single, distributable binary.

## Distribution and Versioning

One of Go's greatest strengths for platform tooling is distribution. Compile once, run anywhere:

```bash
# Build for multiple platforms
GOOS=linux  GOARCH=amd64 go build -o dist/idp-linux-amd64 .
GOOS=darwin GOARCH=arm64 go build -o dist/idp-darwin-arm64 .
GOOS=windows GOARCH=amd64 go build -o dist/idp-windows-amd64.exe .
```

You can distribute these binaries through a Homebrew tap, an internal artifact registry, or a simple install script. Pair this with `goreleaser` to automate cross-platform builds, checksums, and release notes.

A critical practice is embedding version metadata at build time using `ldflags`:

```bash
go build -ldflags "\
  -X main.version=1.2.0 \
  -X main.commit=$(git rev-parse --short HEAD) \
  -X main.buildDate=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -o idp .
```

This lets developers run `idp --version` to see exactly which build they're running—invaluable when debugging issues across a fleet of developer machines.

## Best Practices for IDP CLIs

As your platform matures, keep these principles in mind:

- **Treat the CLI as a product**: Gather feedback, measure usage, and iterate. Your developers are customers.
- **Fail loudly and helpfully**: Error messages should suggest the next action, not just report a stack trace.
- **Make the right thing the easy thing**: Golden paths should be simpler than the alternatives.
- **Version everything**: Templates, the CLI itself, and platform APIs should be versioned for safe evolution.
- **Instrument usage**: Emit anonymous telemetry to understand which commands matter and where developers get stuck.
- **Keep guardrails invisible until needed**: Security and compliance should be automatic, surfacing only when something needs attention.
- **Document inline**: Rich `Long` descriptions and examples in Cobra commands serve as built-in documentation.

## Conclusion

Platform engineering is fundamentally about **leverage**—building capabilities once so that hundreds of developers can move faster. A well-crafted CLI is the daily touchpoint between your platform and its users, and Go is the ideal language for building it.

We've assembled a self-service IDP CLI that scaffolds services from golden-path templates, deploys across environments with concurrency and guardrails, and distributes as a single zero-dependency binary. From here, you can extend the platform with resource provisioning (databases, queues), integration with your GitOps workflow, policy enforcement via OPA, and rich telemetry.

The goal is never to take control away from developers—it's to remove friction so they can focus on what matters: delivering value. When your platform makes the right path the easy path, adoption follows naturally, and the entire organization accelerates.

Start small, ship a single golden path, listen to your developers, and iterate. That's how great internal developer platforms are built.

