# Learn php - Minimal PHP Microservice

A simple PHP microservice for learning containerization and Kubernetes deployment.

## Overview

This is a **cloud-native PHP microservice** built using a minimal Symfony components stack, designed for learning and demonstration purposes. It provides RESTful API endpoints with comprehensive DevOps practices.

**Key Features:**
- Simple HTTP server using PHP built-in server with Symfony components
- 6 RESTful API endpoints (/, /ping, /healthz, /info, /version, /echo)
- Security headers middleware
- CORS support
- JSON response format
- Docker containerization
- Kubernetes/Helm deployment ready

## Installation

### Prerequisites
- php >= 8.1
- composer

### Local Setup

```console
git clone https://github.com/dxas90/learn-php.git
cd learn-php
composer install
```

## Running the Application

### Development Mode (PHP)
```console
# Using PHP built-in webserver (requires composer install)
composer install
php -S 0.0.0.0:4567 -t public

# OR use the Makefile target:
make run
```

The application will start on port 4567 by default. You can customize using environment variables. For local dev you can set APP_ENV and PORT per environment:

```console
APP_ENV=development PORT=8080 php -S 0.0.0.0:8080 -t public
```

### Environment Variables
- `PORT` - Server port (default: 4567)
- `HOST` - Server host (default: 0.0.0.0)
- `APP_ENV` - Environment (development/production/test)
- `APP_VERSION` - Application version (default: 0.0.1)
- `CORS_ORIGIN` - CORS origin (default: *)

## API Endpoints

### GET /
Welcome endpoint with API documentation
```bash
curl http://localhost:4567/
```

### GET /ping
Simple ping-pong response
```bash
curl http://localhost:4567/ping
# Response: pong
```

### GET /healthz
Health check endpoint with system metrics
```bash
curl http://localhost:4567/healthz
```

### GET /info
Application and system information
```bash
curl http://localhost:4567/info
```

### GET /version
Application version information
```bash
curl http://localhost:4567/version
```

### POST /echo
Echo back the request body
```bash
curl -X POST -H "Content-Type: application/json" -d '{"message":"test"}' http://localhost:4567/echo
```

## Docker (PHP)

### Build (PHP)
```console
docker build -f Dockerfile.php -t learn-php:php .
```

### Run (PHP)
```console
docker run -p 4567:4567 learn-php:php
```

## Endpoints (PHP)

All API endpoints in `public/index.php` mirror the original sample API:

- GET / - Welcome + endpoints
- GET /ping - returns "pong" plain text
- GET /healthz - system health info (uptime, memory, load)
- GET /info - detailed system & application info
- GET /version - application version from APP_VERSION
- POST /echo - echo JSON body back


## Kubernetes Deployment

The application includes a Helm chart for Kubernetes deployment.

### Using Helm

```console
helm install learn-php ./k8s/learn-php
```

## CI/CD Pipeline

This project includes a GitLab CI/CD pipeline with the following stages:

### Pipeline Stages

1. **initialize** - Displays pipeline information and verifies php/Bundler versions
2. **build** - Installs dependencies and creates build artifacts
3. **test** - Runs syntax checks and tests
4. **containerize** - Builds and pushes Docker images (only on tags)
5. **deployment** - Deploys to staging environment (only on tags)
6. **promote** - Manual job to promote images to production (only on tags)
7. **notify** - Sends pipeline status notifications

### Pipeline Behavior

**On every commit to any branch:**
- `initialize` → `build` → `test` → `notify`

**On tags only:**
- `initialize` → `build` → `test` → `containerize` → `deployment` (staging) → `promote` (manual) → `notify`

### Creating a Release

To trigger a full pipeline with containerization and deployment:

```console
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

After the staging deployment completes, you can manually trigger the `promote_production` job to deploy to production.

## Development

### Project Structure
```
learn-php/
├── public/             # Public webroot and entry point (index.php)
├── src/                # Application source code
├── composer.json       # PHP dependencies and autoloading
├── Dockerfile.php      # Optional PHP Dockerfile for this microservice
├── k8s/                # Kubernetes/Helm charts
└── scripts/            # Testing and deployment scripts
```

### Response Format
All JSON endpoints return a consistent format:
```json
{
  "success": true,
  "data": { ... },
  "timestamp": "2025-11-16T10:30:00Z"
}
```

### Security Features
- X-Content-Type-Options: nosniff
- X-Frame-Options: DENY
- X-XSS-Protection: 1; mode=block
- Referrer-Policy: strict-origin-when-cross-origin
- Content-Security-Policy: default-src 'self'

## License

This project is licensed under the MIT License.
