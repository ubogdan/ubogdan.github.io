---
title: "Database Patterns in Go: SQL, GORM, and Connection Pooling"
date: 2024-10-22T15:25:15+03:00
tags: ["golang", "database", "sql", "gorm"]
categories: ["Programming"]
description: "Master database interactions in Go with various libraries and learn optimal connection pooling strategies."
draft: true
---

# Database Patterns in Go: SQL, GORM, and Connection Pooling

Database interactions are at the heart of most web applications and services. In Go, you have several options for working with databases, from the standard library's `database/sql` package to powerful ORMs like GORM. Understanding when and how to use each approach, along with proper connection pooling strategies, is crucial for building scalable and performant applications.

This article explores the most common database patterns in Go, comparing raw SQL approaches with ORM solutions, and diving deep into connection pooling strategies that can make or break your application's performance under load.

## Prerequisites

Before diving into this article, you should have:

- **Solid understanding of Go fundamentals**: Variables, structs, interfaces, and error handling
- **Basic SQL knowledge**: SELECT, INSERT, UPDATE, DELETE operations
- **Familiarity with PostgreSQL**: While examples use PostgreSQL, concepts apply to other databases
- **Understanding of concurrent programming**: Goroutines and channels basics
- **Docker knowledge** (optional): For running database instances locally

## Setting Up the Foundation

Let's start by establishing our database setup and basic project structure. We'll use PostgreSQL as our primary database throughout this article.

### Database Schema

First, let's create a simple but realistic schema for a blog application:

```sql
-- Create our database schema
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE posts (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    author_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    published BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_posts_author_id ON posts(author_id);
CREATE INDEX idx_posts_published ON posts(published);
```

### Project Structure

```
project/
├── cmd/
│   └── main.go
├── internal/
│   ├── models/
│   │   └── user.go
│   ├── repository/
│   │   ├── sql/
│   │   │   └── user_repo.go
│   │   └── gorm/
│   │       └── user_repo.go
│   └── database/
│       └── connection.go
├── go.mod
└── go.sum
```

## Working with database/sql Package

The `database/sql` package is Go's standard library solution for database interactions. It provides a generic interface around SQL databases and is the foundation that most other database libraries build upon.

### Basic Connection Setup

```go
// internal/database/connection.go
package database

import (
    "database/sql"
    "fmt"
    "time"

    _ "github.com/lib/pq" // PostgreSQL driver
)

type Config struct {
    Host     string
    Port     int
    User     string
    Password string
    DBName   string
    SSLMode  string
}

// NewConnection creates a new database connection with proper configuration
func NewConnection(cfg Config) (*sql.DB, error) {
    dsn := fmt.Sprintf(
        "host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
        cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.DBName, cfg.SSLMode,
    )

    db, err := sql.Open("postgres", dsn)
    if err != nil {
        return nil, fmt.Errorf("failed to open database connection: %w", err)
    }

    // Configure connection pool
    db.SetMaxOpenConns(25)                 // Maximum number of open connections
    db.SetMaxIdleConns(25)                 // Maximum number of idle connections
    db.SetConnMaxLifetime(5 * time.Minute) // Maximum lifetime of a connection

    // Test the connection
    if err := db.Ping(); err != nil {
        return nil, fmt.Errorf("failed to ping database: %w", err)
    }

    return db, nil
}
```

### Repository Pattern with Raw SQL

The repository pattern helps abstract database operations and makes your code more testable and maintainable.

```go
// internal/models/user.go
package models

import (
    "time"
)

type User struct {
    ID           int       `json:"id"`
    Email        string    `json:"email"`
    Username     string    `json:"username"`
    PasswordHash string    `json:"-"` // Never serialize password hash
    CreatedAt    time.Time `json:"created_at"`
    UpdatedAt    time.Time `json:"updated_at"`
}

type CreateUserRequest struct {
    Email    string `json:"email" validate:"required,email"`
    Username string `json:"username" validate:"required,min=3,max=50"`
    Password string `json:"password" validate:"required,min=8"`
}
```

```go
// internal/repository/sql/user_repo.go
package sql

import (
    "database/sql"
    "fmt"
    "time"

    "your-project/internal/models"
    "golang.org/x/crypto/bcrypt"
)

type UserRepository struct {
    db *sql.DB
}

func NewUserRepository(db *sql.DB) *UserRepository {
    return &UserRepository{db: db}
}

// CreateUser creates a new user with proper password hashing
func (r *UserRepository) CreateUser(req models.CreateUserRequest) (*models.User, error) {
    // Hash the password
    hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
    if err != nil {
        return nil, fmt.Errorf("failed to hash password: %w", err)
    }

    query := `
        INSERT INTO users (email, username, password_hash, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id, email, username, created_at, updated_at
    `

    now := time.Now()
    var user models.User

    err = r.db.QueryRow(
        query,
        req.Email,
        req.Username,
        string(hashedPassword),
        now,
        now,
    ).Scan(
        &user.ID,
        &user.Email,
        &user.Username,
        &user.CreatedAt,
        &user.UpdatedAt,
    )

    if err != nil {
        return nil, fmt.Errorf("failed to create user: %w", err)
    }

    return &user, nil
}

// GetUserByID retrieves a user by their ID
func (r *UserRepository) GetUserByID(id int) (*models.User, error) {
    query := `
        SELECT id, email, username, password_hash, created_at, updated_at
        FROM users
        WHERE id = $1
    `

    var user models.User
    err := r.db.QueryRow(query, id).Scan(
        &user.ID,
        &user.Email,
        &user.Username,
        &user.PasswordHash,
        &user.CreatedAt,
        &user.UpdatedAt,
    )

    if err != nil {
        if err == sql.ErrNoRows {
            return nil, fmt.Errorf("user not found")
        }
        return nil, fmt.Errorf("failed to get user: %w", err)
    }

    return &user, nil
}

// GetUsersByPage implements pagination for user listing
func (r *UserRepository) GetUsersByPage(limit, offset int) ([]*models.User, error) {
    query := `
        SELECT id, email, username, created_at, updated_at
        FROM users
        ORDER BY created_at DESC
        LIMIT $1 OFFSET $2
    `

    rows, err := r.db.Query(query, limit, offset)
    if err != nil {
        return nil, fmt.Errorf("failed to query users: %w", err)
    }
    defer rows.Close()

    var users []*models.User
    for rows.Next() {
        var user models.User
        err := rows.Scan(
            &user.ID,
            &user.Email,
            &user.Username,
            &user.CreatedAt,
            &user.UpdatedAt,
        )
        if err != nil {
            return nil, fmt.Errorf("failed to scan user: %w", err)
        }
        users = append(users, &user)
    }

    if err = rows.Err(); err != nil {
        return nil, fmt.Errorf("error iterating rows: %w", err)
    }

    return users, nil
}

// UpdateUser updates user information
func (r *UserRepository) UpdateUser(id int, email, username string) error {
    query := `
        UPDATE users 
        SET email = $2, username = $3, updated_at = $4
        WHERE id = $1
    `

    result, err := r.db.Exec(query, id, email, username, time.Now())
    if err != nil {
        return fmt.Errorf("failed to update user: %w", err)
    }

    rowsAffected, err := result.RowsAffected()
    if err != nil {
        return fmt.Errorf("failed to get rows affected: %w", err)
    }

    if rowsAffected == 0 {
        return fmt.Errorf("user not found")
    }

    return nil
}

// DeleteUser soft deletes a user
func (r *UserRepository) DeleteUser(id int) error {
    query := `DELETE FROM users WHERE id = $1`

    result, err := r.db.Exec(query, id)
    if err != nil {
        return fmt.Errorf("failed to delete user: %w", err)
    }

    rowsAffected, err := result.RowsAffected()
    if err != nil {
        return fmt.Errorf("failed to get rows affected: %w", err)
    }

    if rowsAffected == 0 {
        return fmt.Errorf("user not found")
    }

    return nil
}
```

## Working with GORM

GORM is Go's most popular ORM library, providing a developer-friendly API for database operations while maintaining good performance characteristics.

### GORM Setup and Configuration

```go
// internal/database/gorm_connection.go
package database

import (
    "fmt"
    "time"

    "gorm.io/driver/postgres"
    "gorm.io/gorm"
    "gorm.io/gorm/logger"
)

// NewGORMConnection creates a new GORM database connection
func NewGORMConnection(cfg Config) (*gorm.DB, error) {
    dsn := fmt.Sprintf(
        "host=%s user=%s password=%s dbname=%s port=%d sslmode=%s",
        cfg.Host, cfg.User, cfg.Password, cfg.DBName, cfg.Port, cfg.SSLMode,
    )

    db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
        Logger: logger.Default.LogMode(logger.Info),
        NowFunc: func() time.Time {
            return time.Now().UTC()
        },
    })

    if err != nil {
        return nil, fmt.Errorf("failed to connect to database: %w", err)
    }

    // Get underlying sql.DB to configure connection pool
    sqlDB, err := db.DB()
    if err != nil {
        return nil, fmt.Errorf("failed to get underlying sql.DB: %w", err)
    }

    // Configure connection pool
    sqlDB.SetMaxIdleConns(10)
    sqlDB.SetMaxOpenConns(100)
    sqlDB.SetConnMaxLifetime(time.Hour)

    return db, nil
}
```

### GORM Models and Relationships

```go
// internal/models/gorm_models.go
package models

import (
    "time"
    "gorm.io/gorm"
)

// User model for GORM with proper tags
type GormUser struct {
    ID           uint      `gorm:"primaryKey" json:"id"`
    Email        string    `gorm:"uniqueIndex;not null" json:"email"`
    Username     string    `gorm:"uniqueIndex;not null;size:100" json:"username"`
    PasswordHash string    `gorm:"not null" json:"-"`
    Posts        []GormPost `gorm:"foreignKey:AuthorID" json:"posts,omitempty"`
    CreatedAt    time.Time `json:"created_at"`
    UpdatedAt    time.Time `json:"updated_at"`
    DeletedAt    gorm.DeletedAt `gorm:"index" json:"-"`
}

type GormPost struct {
    ID        uint      `gorm:"primaryKey" json:"id"`
    Title     string    `gorm:"not null" json:"title"`
    Content   string    `gorm:"type:text;not null" json:"content"`
    AuthorID  uint      `gorm:"not null;index" json:"author_id"`
    Author    GormUser  `gorm:"foreignKey:AuthorID" json:"author,omitempty"`
    Published bool      `gorm:"default:false;index" json:"published"`
    CreatedAt time.Time `json:"created_at"`
    UpdatedAt time.Time `json:"updated_at"`
    DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

// TableName overrides the table name used by GORM
func (GormUser) TableName() string {
    return "users"
}

func (GormPost) TableName() string {
    return "posts"
}
```

### GORM Repository Implementation

```go
// internal/repository/gorm/user_repo.go
package gorm

import (
    "fmt"

    "your-project/internal/models"
    "golang.org/x/crypto/bcrypt"
    "gorm.io/gorm"
)

type GormUserRepository struct {
    db *gorm.DB
}

func NewGormUserRepository(db *gorm.DB) *GormUserRepository {
    return &GormUserRepository{db: db}
}

// CreateUser creates a new user using GORM
func (r *GormUserRepository) CreateUser(req models.CreateUserRequest) (*models.GormUser, error) {
    hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
    if err != nil {
        return nil, fmt.Errorf("failed to hash password: %w", err)
    }

    user := models.GormUser{
        Email:        req.Email,
        Username:     req.Username,
        PasswordHash: string(hashedPassword),
    }

    if err := r.db.Create(&user).Error; err != nil {
        return nil, fmt.Errorf("failed to create user: %w", err)
    }

    return &user, nil
}

// GetUserByID retrieves a user by ID with optional preloading
func (r *GormUserRepository) GetUserByID(id uint, preloadPosts bool) (*models.GormUser, error) {
    var user models.GormUser
    
    query := r.db
    if preloadPosts {
        query = query.Preload("Posts")
    }

    if err := query.First(&user, id).Error; err != nil {
        if err == gorm.ErrRecordNotFound {
            return nil, fmt.Errorf("user not found")
        }
        return nil, fmt.Errorf("failed to get user: %w", err)
    }

    return &user, nil
}

// GetUsersByPage implements pagination with GORM
func (r *GormUserRepository) GetUsersByPage(limit, offset int)