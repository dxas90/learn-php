SHELL=/bin/bash -o pipefail

# Application configuration
APP_NAME := learn-php
DOCKER_REPO := dxas90
REGISTRY := ghcr.io

# Version strategy using git tags
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
GIT_TAG := $(shell git describe --exact-match --abbrev=0 2>/dev/null || echo "")
COMMIT_HASH := $(shell git rev-parse --verify HEAD)
COMMIT_TIMESTAMP := $(shell date --date="@$$(git show -s --format=%ct)" --utc +%FT%T)

VERSION := $(shell git describe --tags --always --dirty)
VERSION_STRATEGY := commit_hash

ifdef GIT_TAG
	VERSION := $(GIT_TAG)
	VERSION_STRATEGY := tag
else
	ifeq (,$(findstring $(GIT_BRANCH),main master HEAD))
		ifneq (,$(patsubst release-%,,$(GIT_BRANCH)))
			VERSION := $(GIT_BRANCH)
			VERSION_STRATEGY := branch
		endif
	endif
endif

# Colors for output
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
RESET := \033[0m

.PHONY: help install build test clean run dev run-prod docker-build docker-run docker-compose docker-compose-down helm-deploy security lint version quick-start full-pipeline release

## Show this help message
help:
	@echo -e "$(BLUE)Available commands:$(RESET)"
	@awk '/^[a-zA-Z\-\_0-9%:\\ ]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = $$1; \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			gsub(":", "", helpCommand); \
			printf "  $(GREEN)%-20s$(RESET) %s\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)

## Install dependencies
install:
	@echo -e "$(BLUE)Installing dependencies...$(RESET)"
	@if [ -f "composer.json" ]; then \
		if ! command -v composer > /dev/null 2>&1; then echo -e "$(YELLOW)Composer not found. Install Composer to manage PHP dependencies.$(RESET)"; else composer install --no-interaction --no-scripts; fi; \
	fi
	@echo -e "$(GREEN)Dependencies installed successfully$(RESET)"

## Build the application (syntax check)
build: install
	@echo -e "$(BLUE)Building application (syntax check)...$(RESET)"
	@php -l public/index.php || exit 1
	@php -l src/Helpers.php || exit 1
	@echo -e "$(GREEN)php syntax OK$(RESET)"

## Run tests
test: install
	@echo -e "$(BLUE)Running tests...$(RESET)"
	@if [ -f "vendor/bin/phpunit" ]; then \
		vendor/bin/phpunit --configuration phpunit.xml || exit 1; \
	else \
		echo "No phpunit found, running syntax-only checks"; \
		php -l public/index.php || exit 1; \
		php -l src/Helpers.php || exit 1; \
	fi
	@echo -e "$(GREEN)Tests completed$(RESET)"

## Run Helm unit tests
helm-test:
	@echo -e "$(BLUE)Running Helm unit tests...$(RESET)"
	@helm lint k8s/learn-php || exit 1
	@helm unittest k8s/learn-php --output-type JUnit --output-file k8s/learn-php/test-results.xml || exit 1
	@echo -e "$(GREEN)Helm unit tests completed$(RESET)"

## Clean build artifacts
clean:
	@echo -e "$(BLUE)Cleaning build artifacts...$(RESET)"
	rm -rf vendor/ composer.lock log/*.log tmp/*
	@if command -v docker > /dev/null 2>&1; then \
		echo -e "$(BLUE)Cleaning Docker artifacts...$(RESET)"; \
		docker system prune -f || echo -e "$(YELLOW)Warning: Could not clean Docker artifacts$(RESET)"; \
	else \
		echo -e "$(YELLOW)Docker not available, skipping Docker cleanup$(RESET)"; \
	fi

## Run the application locally
run: install
	@echo -e "$(BLUE)Starting application locally...$(RESET)"
	@echo -e "$(BLUE)Starting PHP application locally (built-in server)...$(RESET)"
	@php -S 0.0.0.0:4567 -t public >/dev/null 2>&1 &
	@sleep 1; echo -e "$(GREEN)Server started at http://0.0.0.0:4567/$(RESET)"

## Run the application in development mode
dev: install
	@echo -e "$(BLUE)Starting application in development mode...$(RESET)"
	@echo -e "$(BLUE)Starting PHP app in development mode with built-in server...$(RESET)"
	@APP_ENV=development php -S 0.0.0.0:4567 -t public

## Run with production profile
run-prod: install
	@echo -e "$(BLUE)Starting application with production profile...$(RESET)"
	@APP_ENV=production php -S 0.0.0.0:4567 -t public

## Build Docker image
docker-build:
	@echo -e "$(BLUE)Building Docker image...$(RESET)"
	@echo -e "$(BLUE)Building Docker image for PHP app (Dockerfile.php)...$(RESET)"
	@if [ -f "Dockerfile.php" ]; then docker build -t $(APP_NAME):$(VERSION) -f Dockerfile.php .; else docker build -t $(APP_NAME):$(VERSION) .; fi
	docker tag $(APP_NAME):$(VERSION) $(APP_NAME):latest

## Run Docker container
docker-run:
	@echo -e "$(BLUE)Running Docker container...$(RESET)"
	docker run -it --rm -p 4567:4567 --name $(APP_NAME) $(APP_NAME):$(VERSION)

## Start application with Docker Compose
docker-compose:
	@echo -e "$(BLUE)Starting services with Docker Compose...$(RESET)"
	@if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then \
		docker-compose up --build; \
	else \
		echo -e "$(YELLOW)No docker-compose.yml file found$(RESET)"; \
		echo -e "$(YELLOW)Use 'make docker-run' to run the container directly$(RESET)"; \
	fi

## Stop Docker Compose services
docker-compose-down:
	@echo -e "$(BLUE)Stopping Docker Compose services...$(RESET)"
	@if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then \
		docker-compose down -v; \
	else \
		echo -e "$(YELLOW)No docker-compose.yml file found$(RESET)"; \
	fi

## Deploy using Helm
helm-deploy:
	@echo -e "$(BLUE)Deploying with Helm...$(RESET)"
	helm upgrade --install $(APP_NAME) ./k8s/learn-php

## Run security scan
security:
	@echo -e "$(BLUE)Running security scan...$(RESET)"
	@if command -v composer > /dev/null 2>&1; then \
		if composer --version >/dev/null 2>&1; then \
			# Modern composer has 'audit' command. If not available, echo message
			if composer audit --help >/dev/null 2>&1 2>/dev/null; then composer audit || true; else echo "composer audit not available in this composer version"; fi; \
		fi; \
	else \
		echo -e "$(YELLOW)Composer not installed, skipping security scan$(RESET)"; \
	fi

## Run code quality checks
lint: install
	@echo -e "$(BLUE)Running linters...$(RESET)"
	@if [ -f public/index.php ]; then php -l public/index.php || exit 1; fi
	@if [ -f src/Helpers.php ]; then php -l src/Helpers.php || exit 1; fi

## Show version information
version:
	@echo -e "$(BLUE)Version Information:$(RESET)"
	@echo -e "Version: $(VERSION)"
	@echo -e "Strategy: $(VERSION_STRATEGY)"
	@echo -e "Git Tag: $(GIT_TAG)"
	@echo -e "Git Branch: $(GIT_BRANCH)"
	@echo -e "Commit Hash: $(COMMIT_HASH)"
	@echo -e "Commit Timestamp: $(COMMIT_TIMESTAMP)"

## Health check
health-check:
	@echo -e "$(BLUE)Performing health check...$(RESET)"
	@curl -s http://localhost:4567/healthz | jq . || echo -e "$(RED)Health check failed$(RESET)"

## Update dependencies
update:
	@echo -e "$(BLUE)Updating dependencies...$(RESET)"
	@if command -v composer > /dev/null 2>&1; then composer update --no-interaction; else echo "Composer not found"; fi

## Check for outdated packages
outdated:
	@echo -e "$(BLUE)Checking for outdated packages...$(RESET)"
	@if command -v composer > /dev/null 2>&1; then composer outdated || true; else echo "Composer not found"; fi

## Quick start - install, test, and run locally
quick-start: clean install test run

## Full pipeline - test, build, and deploy locally
full-pipeline: test security docker-build docker-compose

## Release - tag and build for release
release:
	@echo -e "$(BLUE)Preparing release $(VERSION)...$(RESET)"
	git tag -a v$(VERSION) -m "Release version $(VERSION)"
	$(MAKE) docker-build
	@echo -e "$(GREEN)Release $(VERSION) ready!$(RESET)"
