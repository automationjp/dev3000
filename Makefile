# Dev3000 Development Makefile
# Simplified development workflow for Docker-based dev3000

.PHONY: help setup init dev-up dev-down dev-logs dev-rebuild dev-rebuild-fast dev3000-sync dev-rebuild-frontend clean clean-frontend deploy-frontend deploy-and-start list-examples start-chrome-cdp start-chrome-cdp-xplat stop-chrome-cdp status cdp-check dev-build dev-build-fast diagnose log-clean log-ls log-tail-last test-echo test-fail test test-node test-shellspec test-all install-checkmake lint-make

# Default target
.DEFAULT_GOAL := help

# Use a single bash shell per recipe to preserve variables like START_TS/END_TS
SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -lc

# Resolve absolute directory of this Makefile for robust cd in recipes (deferred evaluation)
MAKEFILE_DIR = $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Detect environment
IS_WSL2 := $(shell grep -qi microsoft /proc/version 2>/dev/null && echo 1 || echo 0)

# CDP URLs always use localhost (WSL2 uses socat proxy in container)
CDP_URL := http://localhost:9222
CDP_CHECK_URL := http://localhost:9222/json/version

## ========== Quick Start ==========

help: ## Show this help message
	@echo "Dev3000 Development Commands"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-21s %s\n", $$1, $$2}'

## ========== Docker Development ==========

dev-up: ## Start dev3000 in Docker (launches Chrome automatically)
	@START_TS=$$(date +%s); echo "[RUN] Start: $$(date '+%Y-%m-%d %H:%M:%S')"
	@. scripts/make-helpers.sh
	@echo "Starting dev3000 development environment..."
	@echo ""
	@echo "Step 1: Starting Docker containers..."
	@run_cmd "docker compose up" docker compose up -d
	@echo ""
	@echo "Step 2: Waiting for Next.js to be ready..."
	@if [ "$$D3K_LOG_DRY_RUN" = "1" ]; then \
		echo "[DRY-RUN] Skipping readiness wait"; \
	else \
		NEXT_READY=0; i=1; while [ $$i -le 60 ]; do \
			if curl -s http://localhost:3000 > /dev/null 2>&1; then \
				NEXT_READY=1; \
				echo "✅ Next.js is ready!"; \
				break; \
			fi; \
			if [ $$i -eq 60 ]; then \
				echo "⚠️  Timeout waiting for Next.js (60s)"; \
				echo "Services may still be starting. Check logs with: make dev-logs"; \
			fi; \
			echo -n "."; \
			sleep 1; \
			i=$$((i + 1)); \
		done; \
	fi
	@echo ""
	@if [ "$$NEXT_READY" = "1" ]; then \
		echo "Step 2.5: Warming common routes (compile ahead of time)..."; \
		for route in "/" "/demos/counter" "/demos/server-actions" "/demos/parallel-routes"; do \
			START_RT=$$(date +%s); \
			echo "  → warming http://localhost:3000$$route"; \
			code=$$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000$$route" || echo 000); \
			END_RT=$$(date +%s); EL=$$((END_RT-START_RT)); \
			if [ "$$code" -ge 200 ] && [ "$$code" -lt 300 ]; then \
				echo "    warmed ($$code) in $${EL}s ✅"; \
			else \
				echo "    warmed ($$code) in $${EL}s ⚠️"; \
			fi; \
		done; \
	else \
		echo "Step 2.5: Skipping route warming (Next not ready)"; \
	fi
	@echo ""
	@echo "[CDP] Step 3: Launching Chrome with CDP..."
	@$(MAKE) -C $(MAKEFILE_DIR) start-chrome-cdp-xplat
	@echo ""
	@echo "[CDP] Step 4: Running cdp-check diagnostics (host + container)"; $(MAKE) -C $(MAKEFILE_DIR) cdp-check
	@echo ""
	@echo "✅ Development environment started"
	@echo ""
	@echo "Access points:"
	@echo "  Next.js App:    http://localhost:3000"
	@echo "  Dev3000 UI:     http://localhost:3684"
	@echo "  Logs Viewer:    http://localhost:3684/logs"
	@echo ""
	@echo "View logs: make dev-logs"
	@echo "Stop:      make dev-down"
	@# Open logs UI automatically (best-effort)
	@if [ "$(IS_WSL2)" = "1" ]; then \
		echo "[LOGS] Opening http://localhost:3684/logs in Windows..."; \
		cmd.exe /C start http://localhost:3684/logs >/dev/null 2>&1 || true; \
	else \
		if command -v xdg-open >/dev/null 2>&1; then \
			echo "[LOGS] Opening http://localhost:3684/logs..."; \
			if ! xdg-open http://localhost:3684/logs >/dev/null 2>&1; then \
				echo "[LOGS] ⚠️  Failed to auto-open; visit: http://localhost:3684/logs"; \
			fi; \
		elif command -v open >/dev/null 2>&1; then \
			echo "[LOGS] Opening http://localhost:3684/logs..."; \
			if ! open http://localhost:3684/logs >/dev/null 2>&1; then \
				echo "[LOGS] ⚠️  Failed to auto-open; visit: http://localhost:3684/logs"; \
			fi; \
		else \
			echo "[LOGS] Visit: http://localhost:3684/logs"; \
		fi; \
	fi
	@END_TS=$$(date +%s); ELAPSED=$$((END_TS-START_TS)); echo "[RUN] End:   $$(date '+%Y-%m-%d %H:%M:%S') (elapsed: $${ELAPSED}s)"

dev-down: ## Stop dev3000 Docker environment
	@START_TS=$$(date +%s); echo "[RUN] Start: $$(date '+%Y-%m-%d %H:%M:%S')"
	@. scripts/make-helpers.sh
	@echo "Stopping development environment..."
	@run_cmd "docker compose down" docker compose down
	@echo ""
	@echo "✅ Development environment stopped"
	@echo ""
	@echo "⚠️  Note: Chrome CDP browser is still running"
	@echo "To close Chrome, close the Chrome window manually or run:"
	@if [ "$(IS_WSL2)" = "1" ]; then \
		echo "  powershell.exe -Command \"Get-Process chrome | Where-Object {\$$_.CommandLine -like '*remote-debugging-port*'} | Stop-Process\""; \
	else \
		echo "  pkill -f 'chrome.*remote-debugging-port'"; \
	fi
	@END_TS=$$(date +%s); ELAPSED=$$((END_TS-START_TS)); echo "[RUN] End:   $$(date '+%Y-%m-%d %H:%M:%S') (elapsed: $${ELAPSED}s)"

dev-logs: ## Follow Docker container logs
	@START_TS=$$(date +%s); echo "[RUN] Start: $$(date '+%Y-%m-%d %H:%M:%S')"
	@. scripts/make-helpers.sh
	@if [ "$$D3K_LOG_ONE_SHOT" = "1" ]; then \
		run_cmd "docker compose logs --tail 100" docker compose logs --tail 100; \
	else \
		run_cmd "docker compose logs -f" docker compose logs -f; \
	fi
	@END_TS=$$(date +%s); ELAPSED=$$((END_TS-START_TS)); echo "[RUN] End:   $$(date '+%Y-%m-%d %H:%M:%S') (elapsed: $${ELAPSED}s)"

dev-rebuild: ## Rebuild and restart Docker environment
	@START_TS=$$(date +%s); echo "[RUN] Start: $$(date '+%Y-%m-%d %H:%M:%S')"
	@. scripts/make-helpers.sh
	@echo "Rebuilding development environment..."
	@# Ensure frontend/Dockerfile.dev exists; auto-provision default example if missing
	@if [ ! -f "frontend/Dockerfile.dev" ]; then \
		echo "[SETUP] Missing frontend/Dockerfile.dev. Auto-deploying example: nextjs16"; \
		$(MAKE) -C $(MAKEFILE_DIR) deploy-frontend APP=nextjs16; \
	fi
	@run_cmd "docker compose down" docker compose down
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "docker compose build --no-cache" bash -lc "DOCKER_BUILDKIT=1 docker compose build --no-cache"'
	@$(MAKE) -C $(MAKEFILE_DIR) dev-up
	@END_TS=$$(date +%s); ELAPSED=$$((END_TS-START_TS)); echo "[RUN] End:   $$(date '+%Y-%m-%d %H:%M:%S') (elapsed: $${ELAPSED}s)"

dev-rebuild-fast: ## Fast rebuild using cache (for minor changes)
	@START_TS=$$(date +%s); echo "[RUN] Start: $$(date '+%Y-%m-%d %H:%M:%S')"
	@. scripts/make-helpers.sh
	@echo "Fast rebuilding development environment (with cache)..."
	@# Ensure frontend/Dockerfile.dev exists; auto-provision default example if missing
	@if [ ! -f "frontend/Dockerfile.dev" ]; then \
		echo "[SETUP] Missing frontend/Dockerfile.dev. Auto-deploying example: nextjs16"; \
		$(MAKE) -C $(MAKEFILE_DIR) deploy-frontend APP=nextjs16; \
	fi
	@run_cmd "docker compose down" docker compose down
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "docker compose build (cache)" bash -lc "DOCKER_BUILDKIT=1 docker compose build"'
	@$(MAKE) -C $(MAKEFILE_DIR) dev-up
	@END_TS=$$(date +%s); ELAPSED=$$((END_TS-START_TS)); echo "[RUN] End:   $$(date '+%Y-%m-%d %H:%M:%S') (elapsed: $${ELAPSED}s)"

# Build-only targets (do not start or stop containers)
dev-build: ## Build Docker images without cache (no start)
	@START_TS=$$(date +%s); echo "[RUN] Start: $$(date '+%Y-%m-%d %H:%M:%S')"
	@. scripts/make-helpers.sh
	@echo "Building images (no-cache)..."
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "docker compose build --no-cache" bash -lc "DOCKER_BUILDKIT=1 docker compose build --no-cache"'
	@END_TS=$$(date +%s); ELAPSED=$$((END_TS-START_TS)); echo "[RUN] End:   $$(date '+%Y-%m-%d %H:%M:%S') (elapsed: $${ELAPSED}s)"

dev-build-fast: ## Build Docker images with cache (no start)
	@START_TS=$$(date +%s); echo "[RUN] Start: $$(date '+%Y-%m-%d %H:%M:%S')"
	@. scripts/make-helpers.sh
	@echo "Building images (with cache)..."
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "docker compose build (cache)" bash -lc "DOCKER_BUILDKIT=1 docker compose build"'
	@END_TS=$$(date +%s); ELAPSED=$$((END_TS-START_TS)); echo "[RUN] End:   $$(date '+%Y-%m-%d %H:%M:%S') (elapsed: $${ELAPSED}s)"

dev3000-sync: ## Update dev3000 submodule to latest version
	@echo "🔄 Updating dev3000 submodule..."
	@if [ -d "frontend/.dev3000/.git" ]; then \
		cd frontend/.dev3000 && git pull origin main; \
		echo "✅ dev3000 submodule updated to latest"; \
		echo ""; \
		echo "Next step: make dev-rebuild-frontend"; \
	else \
		echo "❌ Error: frontend/.dev3000 is not a git repository"; \
		echo ""; \
		echo "To set up frontend/.dev3000:"; \
		echo "  1. Run: make deploy-frontend APP=nextjs16"; \
		echo "  2. Or manually: cd frontend && git submodule add https://github.com/automationjp/dev3000 .dev3000"; \
		exit 1; \
	fi

dev-rebuild-frontend: ## Rebuild frontend Docker image only (without full restart)
	@. scripts/make-helpers.sh
	@echo "🔨 Rebuilding frontend Docker image..."
	@# Ensure frontend/Dockerfile.dev exists; auto-provision default example if missing
	@if [ ! -f "frontend/Dockerfile.dev" ]; then \
		echo "[SETUP] Missing frontend/Dockerfile.dev. Auto-deploying example: nextjs16"; \
		$(MAKE) -C $(MAKEFILE_DIR) deploy-frontend APP=nextjs16; \
	fi
	@run_cmd "docker compose down" docker compose down
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "docker compose build (cache)" bash -lc "DOCKER_BUILDKIT=1 docker compose build"'
	@echo "✅ Frontend Docker image rebuilt"
	@echo ""
	@echo "Next step: make dev-up"

clean: ## Clean up Docker resources and build artifacts
	@. scripts/make-helpers.sh
	@echo "Cleaning up..."
	@run_cmd "docker compose down -v" docker compose down -v || true
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "rm example builds" bash -lc "rm -rf example/*/node_modules example/*/.next"' || true
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "rm frontend builds" bash -lc "rm -rf frontend/node_modules frontend/.next"' || true
	@echo "✅ Cleanup complete"

clean-frontend: ## Clear frontend directory (keeps only .keep file)
	@echo "Clearing frontend directory..."
	@. scripts/make-helpers.sh
	@run_cmd "docker compose down" docker compose down || true
	@if [ -d "frontend" ]; then \
		. scripts/make-helpers.sh; run_cmd "rm frontend/* (keep .keep)" find frontend -mindepth 1 -maxdepth 1 -not -name .keep -exec rm -rf {} +; \
		echo "# Frontend deployment directory" > frontend/.keep; \
		echo "✅ Frontend directory cleared"; \
		echo "   Only .keep file remains"; \
		echo ""; \
		echo "Deploy an example with: make deploy-frontend APP=nextjs16"; \
	else \
		echo "❌ Error: frontend directory does not exist"; \
	fi

## ========== Frontend Deployment ==========

# deploy-frontend: Copies example app to frontend/ and sets up .dev3000 reference
# The .dev3000 directory simulates how production users would include dev3000 as a git submodule
# This allows Dockerfile.dev to build dev3000 from the submodule during container builds
# Process:
#   1. Copies example app to frontend/ directory (rsync, excluding build outputs)
#   2. Creates frontend/.dev3000/ with dev3000 source code (simulates: git submodule add)
# Production setup: git submodule add https://github.com/automationjp/dev3000 frontend/.dev3000

deploy-frontend: ## Deploy example app to frontend directory (e.g., make deploy-frontend APP=nextjs16)
	@if [ -z "$(APP)" ]; then \
        echo "❌ Error: APP parameter is required"; \
        echo ""; \
        echo "Usage: make deploy-frontend APP=<app-name>"; \
		echo ""; \
		echo "Available apps in example/:"; \
		ls -1 example/ | sed 's/^/  - /'; \
		exit 1; \
	fi; \
	if [ ! -d "example/$(APP)" ]; then \
		echo "❌ Error: example/$(APP) does not exist"; \
		echo ""; \
		echo "Available apps:"; \
		ls -1 example/ | sed 's/^/  - /'; \
		exit 1; \
	fi; \
	. scripts/make-helpers.sh; \
	echo "📦 Deploying example/$(APP) to frontend/..."; \
	. scripts/make-helpers.sh; run_cmd "rm -rf frontend" rm -rf frontend; \
	. scripts/make-helpers.sh; run_cmd "mkdir -p frontend" mkdir -p frontend; \
	. scripts/make-helpers.sh; run_cmd "rsync example -> frontend" rsync -av --exclude=node_modules --exclude=.next --exclude=out --exclude=.pnpm-store example/$(APP)/ frontend/; \
	# Ensure frontend/Dockerfile.dev exists for docker compose builds
	if [ -f "example/$(APP)/Dockerfile.dev" ]; then \
		. scripts/make-helpers.sh; run_cmd "copy Dockerfile.dev" cp "example/$(APP)/Dockerfile.dev" frontend/Dockerfile.dev; \
	else \
		echo "❌ Missing example/$(APP)/Dockerfile.dev. Cannot set up frontend Dockerfile."; \
		exit 1; \
	fi; \
	echo "✅ Copied example/$(APP) to frontend/"; \
	echo ""; \
	echo "🔗 Setting up frontend/.dev3000 (dev3000 reference)..."; \
	echo "   This simulates a user's dev3000 git submodule setup"; \
	echo "   Purpose: Dockerfile.dev references .dev3000 for building dev3000 CLI"; \
	echo "   Production users: git submodule add https://github.com/automationjp/dev3000 frontend/.dev3000"; \
	echo "   Development setup: Copy dev3000 source to frontend/.dev3000/"; \
	rm -rf frontend/.dev3000/src frontend/.dev3000/mcp-server frontend/.dev3000/www; \
	. scripts/make-helpers.sh; run_cmd "rsync dev3000 -> .dev3000" rsync -av --exclude=node_modules --exclude=.next --exclude=dist --exclude=.pnpm-store src mcp-server frontend/.dev3000/; \
	. scripts/make-helpers.sh; run_cmd "rm node_modules in .dev3000" rm -rf frontend/.dev3000/node_modules frontend/.dev3000/mcp-server/node_modules; \
	echo "   Removed node_modules directories (will be installed by Docker)"; \
	mkdir -p frontend/.dev3000/scripts; \
		. scripts/make-helpers.sh; run_cmd "copy entrypoint" cp scripts/docker-entrypoint.sh frontend/.dev3000/scripts/; \
		. scripts/make-helpers.sh; run_cmd "chmod entrypoint" chmod +x frontend/.dev3000/scripts/docker-entrypoint.sh; \
		. scripts/make-helpers.sh; run_cmd "copy meta files" cp package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.json biome.json Makefile docker-compose.yml frontend/.dev3000/; \
	echo ""; \
	echo "✅ Deployed example/$(APP) to frontend/"; \
	echo "✅ Created frontend/.dev3000 reference (simulating user setup)"; \
	echo ""; \
	echo "Frontend directory contents:"; \
	du -sh frontend/ 2>/dev/null || echo "  ⚠️  Could not determine frontend/ size"; \
	if [ -d "frontend/.dev3000" ]; then \
		du -sh frontend/.dev3000/ 2>/dev/null || echo "  ⚠️  Could not determine frontend/.dev3000/ size"; \
	else \
		echo "  ⚠️  frontend/.dev3000 not created"; \
	fi; \
	echo ""; \
	echo "📝 Note: Dependencies will be installed automatically by Docker on first run"; \
	echo ""; \
	echo "Next steps:"; \
	echo "  make dev-rebuild  - Rebuild Docker image with new frontend"; \
	echo "  make dev-up       - Start development environment"

deploy-and-start: ## Deploy example and start dev environment (e.g., make deploy-and-start APP=nextjs16)
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP parameter is required"; \
		echo ""; \
		echo "Usage: make deploy-and-start APP=<app-name>"; \
		echo ""; \
		echo "Available apps in example/:"; \
		ls -1 example/ | sed 's/^/  - /'; \
		exit 1; \
	fi
	@echo "🚀 Deploying and starting $(APP)..."
	@echo ""
	@$(MAKE) deploy-frontend APP=$(APP)
	@echo ""
	@echo "🔨 Rebuilding Docker image..."
	@$(MAKE) dev-rebuild

list-examples: ## List available example apps
	@echo "Available example apps:"
	@ls -1 example/ | sed 's/^/  - /'
	@echo ""
		@echo "Deploy with: make deploy-frontend APP=<app-name>"
		@echo "Deploy and start with: make deploy-and-start APP=<app-name>"

## ========== Initial Setup ==========

setup: ## Initial setup: deploy example (APP? default: nextjs16), build images, and start
	@START_TS=$$(date +%s); echo "[RUN] Start: $$(date '+%Y-%m-%d %H:%M:%S')"
	@. scripts/make-helpers.sh
	@# Determine app to deploy
	@if [ -z "$(APP)" ]; then \
		APP_NAME=nextjs16; \
		echo "[SETUP] APP not specified; defaulting to '$$APP_NAME'"; \
	else \
		APP_NAME="$(APP)"; \
	fi; \
	$(MAKE) -C $(MAKEFILE_DIR) deploy-frontend APP=$$APP_NAME
	@# Ensure pnpm exists
	@if ! command -v pnpm >/dev/null 2>&1; then \
		section "PNPM Setup"; \
		if confirm "pnpm not found. Install via corepack now?"; then \
			run_cmd "corepack enable" corepack enable || true; \
			run_cmd "corepack prepare pnpm@10.18.3 --activate" corepack prepare pnpm@10.18.3 --activate || true; \
		else \
			hint "Skipping pnpm setup."; \
		fi; \
	fi
	@# Install root dependencies when missing
	@if [ ! -d node_modules ]; then \
		section "Dependencies (root)"; \
		if confirm "Install root dependencies with pnpm install now?"; then \
			run_cmd "pnpm install (root)" pnpm install || true; \
		else \
			hint "Skipping pnpm install (root)."; \
		fi; \
	fi
	@# Install frontend dependencies when missing
	@if [ -f frontend/package.json ] && [ ! -d frontend/node_modules ]; then \
		section "Dependencies (frontend)"; \
		if confirm "Install frontend dependencies with pnpm install now?"; then \
			/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "pnpm install (frontend)" bash -lc "cd frontend && pnpm install"' || true; \
		else \
			hint "Skipping pnpm install (frontend)."; \
		fi; \
	fi
	@# Optionally install .dev3000 deps (rarely needed on host; mostly installed in Docker build)
	@if [ -f frontend/.dev3000/package.json ] && [ ! -d frontend/.dev3000/node_modules ]; then \
		section "Dependencies (frontend/.dev3000)"; \
		if confirm "Install frontend/.dev3000 deps on host? (Usually not required)"; then \
			/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "pnpm install (frontend/.dev3000)" bash -lc "cd frontend/.dev3000 && pnpm install"' || true; \
		else \
			hint "Skipping pnpm install (frontend/.dev3000)."; \
		fi; \
	fi
	@echo ""
	@echo "[SETUP] Building images and starting environment..."
	@$(MAKE) -C $(MAKEFILE_DIR) dev-rebuild
	@echo ""
	@section "Test Tooling"
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; if [ ! -x .shellspec/bin/shellspec ]; then hint "ShellSpec not bootstrapped (vendor)."; if confirm "Bootstrap ShellSpec locally now?"; then run_cmd "bootstrap shellspec" bash -lc "bash scripts/run-shellspec.sh --version || true"; else hint "Skipping ShellSpec bootstrap (NON_INTERACTIVE? set NON_INTERACTIVE=1 to skip prompts)"; fi; else run_cmd "shellspec --version" bash -lc ".shellspec/bin/shellspec --version"; fi' || true
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; if ! command -v kcov >/dev/null 2>&1; then hint "kcov not found (optional for coverage)."; if confirm "Install kcov via apt-get now? (sudo may be required)"; then run_cmd "install kcov (apt-get)" bash -lc "sudo apt-get update && sudo apt-get install -y kcov" || true; else hint "Skipping kcov install."; fi; else run_cmd "kcov --version" kcov --version; fi' || true
	@section "Makefile Linting"
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "lint-make" bash -lc "make -s lint-make"' || true
	@echo ""
	@echo "✅ Setup complete. Next steps:"
	@echo "  - Open: http://localhost:3000 (App)"
	@echo "  - Open: http://localhost:3684 (Dev3000 UI)"
	@echo "  - Logs: make dev-logs or http://localhost:3684/logs"
	@END_TS=$$(date +%s); ELAPSED=$$((END_TS-START_TS)); echo "[RUN] End:   $$(date '+%Y-%m-%d %H:%M:%S') (elapsed: $${ELAPSED}s)"

init: ## Alias for setup
	@$(MAKE) setup APP=$(APP)

cdp-check: ## Verify CDP reachability from Windows/WSL/Docker
	@START_TS=$$(date +%s); echo "[RUN] Start: $$(date '+%Y-%m-%d %H:%M:%S')"
	@. scripts/make-helpers.sh
	@echo "=== CDP Reachability Check ==="
	@# Ensure dev3000 container is running for container-side diagnostics
	@if ! docker ps --format '{{.Names}}' | grep -q '^dev3000$$'; then \
		echo "[CDP] dev3000 container not running. Starting via docker compose..."; \
		. scripts/make-helpers.sh; run_cmd "docker compose up" docker compose up -d; \
		sleep 1; \
	fi
	@/usr/bin/env bash -lc 'cd "$(MAKEFILE_DIR)" && . scripts/make-helpers.sh && run_cmd "node scripts/check-cdp.mjs" node scripts/check-cdp.mjs'
	@END_TS=$$(date +%s); ELAPSED=$$((END_TS-START_TS)); echo "[RUN] End:   $$(date '+%Y-%m-%d %H:%M:%S') (elapsed: $${ELAPSED}s)"

diagnose: ## Comprehensive diagnostics: env, ports, docker, browser, status
	@START_TS=$$(date +%s); echo "[RUN] Start: $$(date '+%Y-%m-%d %H:%M:%S')"
	@. scripts/make-helpers.sh
	@section "Environment"
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "node --version" node --version' || true
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "pnpm --version" pnpm --version' || true

	@section "Test Tooling"
	# Ensure ShellSpec is available (vendor via scripts/run-shellspec.sh)
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; if [ ! -x .shellspec/bin/shellspec ]; then hint "ShellSpec not bootstrapped (vendor)."; if confirm "Bootstrap ShellSpec locally now?"; then run_cmd "bootstrap shellspec" bash -lc "bash scripts/run-shellspec.sh --version || true"; else hint "Skipping ShellSpec bootstrap (NON_INTERACTIVE? set NON_INTERACTIVE=1 to skip prompts)"; fi; else run_cmd "shellspec --version" bash -lc ".shellspec/bin/shellspec --version"; fi' || true
	# Check kcov for coverage support (optional)
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; if ! command -v kcov >/dev/null 2>&1; then hint "kcov not found (optional for coverage)."; if confirm "Install kcov via apt-get now? (sudo may be required)"; then run_cmd "install kcov (apt-get)" bash -lc "sudo apt-get update && sudo apt-get install -y kcov" || true; else hint "Skipping kcov install."; fi; else run_cmd "kcov --version" kcov --version; fi' || true
	@# Offer to install pnpm via corepack if missing
	@if ! command -v pnpm >/dev/null 2>&1; then \
		section "PNPM Setup"; \
		if confirm "pnpm not found. Install via corepack now?"; then \
			run_cmd "corepack enable" corepack enable || true; \
			run_cmd "corepack prepare pnpm@10.18.3 --activate" corepack prepare pnpm@10.18.3 --activate || true; \
		else \
			hint "Skipping pnpm setup. Set NON_INTERACTIVE=1 to auto-skip prompts."; \
		fi; \
	fi
	@# Offer to install dependencies if node_modules missing
	@if [ ! -d node_modules ]; then \
		section "Dependencies"; \
		if confirm "Install root dependencies with pnpm install now?"; then \
			run_cmd "pnpm install (root)" pnpm install || true; \
		else \
			hint "Skipping pnpm install (root)."; \
		fi; \
	fi
	@if [ -f frontend/package.json ] && [ ! -d frontend/node_modules ]; then \
		section "Dependencies (frontend)"; \
		if confirm "Install frontend dependencies with pnpm install now?"; then \
			/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "pnpm install (frontend)" bash -lc "cd frontend && pnpm install"' || true; \
		else \
			hint "Skipping pnpm install (frontend)."; \
		fi; \
	fi
	@run_cmd "docker --version" docker --version || true
	@run_cmd "docker compose version" docker compose version || true
	@section "Docker Containers"
	@run_cmd "docker compose ps" docker compose ps || true
	@section "Ports"
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "ss -ltnp ports 3000/3684/9222" bash -lc "ss -ltnp 2>/dev/null | rg -n -e \":(3000|3684|9222)\" || true"'
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; l3000=$$(ss -ltnp 2>/dev/null | grep -E ":(3000)\b" | wc -l || true); l3684=$$(ss -ltnp 2>/dev/null | grep -E ":(3684)\b" | wc -l || true); l9222=$$(ss -ltnp 2>/dev/null | grep -E ":(9222)\b" | wc -l || true); kv "Port 3000" "$$( [ "$$l3000" -gt 0 ] && echo LISTEN || echo CLOSED)"; kv "Port 3684" "$$( [ "$$l3684" -gt 0 ] && echo LISTEN || echo CLOSED)"; kv "Port 9222" "$$( [ "$$l9222" -gt 0 ] && echo LISTEN || echo CLOSED)"; if [ "$$l3000" -eq 0 ]; then hint "App port 3000 CLOSED. Next: make dev-up; then make dev-logs"; fi; if [ "$$l3684" -eq 0 ]; then hint "MCP port 3684 CLOSED. Next: make dev-up; then make dev-logs"; fi; if [ "$$l9222" -eq 0 ]; then hint "CDP port 9222 CLOSED on host. Ensure Chrome started with --remote-debugging-port=9222"; fi'
	@section "HTTP Probes"
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "curl app /" bash -lc "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000 || true"'
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "curl cdp /json/version" bash -lc "curl -s -o /dev/null -w '%{http_code}' http://localhost:9222/json/version || true"'
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 || true); if [ "$$code" = "000" ]; then hint "App probe: NG (no response). Next: make dev-up, then make dev-logs"; else kv "App probe" "OK ($$code)"; fi'
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9222/json/version || true); if [ "$$code" = "000" ]; then hint "CDP probe: NG (no response). Next: make start-chrome-cdp or run make dev-up (which launches it)"; else kv "CDP probe" "OK ($$code)"; fi'
	@section "CDP Diagnostics"
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; if [ -f scripts/check-cdp.mjs ]; then run_cmd "node scripts/check-cdp.mjs" node scripts/check-cdp.mjs; else hint "Skipping deep CDP check (repo dir unresolved). Running lightweight probes."; run_cmd "curl cdp /json/version (light)" bash -lc "curl -sSf http://localhost:9222/json/version || true"; run_cmd "ss -ltnp :9222 (light)" bash -lc "ss -ltnp 2>/dev/null | grep \":9222\" || true"; fi'
	@section "Status"
	@/usr/bin/env bash -lc '. scripts/make-helpers.sh; echo "=== Dev3000 Status ==="; echo ""; echo "Docker Containers:"; docker compose ps; echo ""; echo "Chrome CDP:"; if curl -s http://localhost:9222/json/version >/dev/null 2>&1; then echo "  ✅ Chrome running with CDP on port 9222 (http://localhost:9222)"; else echo "  ❌ Chrome CDP not accessible (http://localhost:9222)"; fi'
	@END_TS=$$(date +%s); ELAPSED=$$((END_TS-START_TS)); echo "[RUN] End:   $$(date '+%Y-%m-%d %H:%M:%S') (elapsed: $${ELAPSED}s)"

## ========== Log Utilities ==========

log-clean: ## Clean the local make command logs directory
	@. scripts/make-helpers.sh
	@dir=$$(D3K_LOG_DIR="$$D3K_LOG_DIR" bash -lc 'echo $${D3K_LOG_DIR:-.make-logs}'); \
		echo "Cleaning logs in: $$dir"; \
		rm -rf "$$dir"; \
		mkdir -p "$$dir"; \
		echo "# keep" > "$$dir/.keep"; \
		echo "✅ Cleaned logs"

log-ls: ## List recent entries in combined.log
	@. scripts/make-helpers.sh
	@dir=$$(D3K_LOG_DIR="$$D3K_LOG_DIR" D3K_LOG_FILE="$$D3K_LOG_FILE" bash -lc 'd=$${D3K_LOG_DIR:-.make-logs}; echo $${D3K_LOG_FILE:-$$d/combined.log}'); \
		file="$$dir"; \
		N=$${LOGS_N:-10}; \
		if [ ! -f "$$file" ]; then echo "No logs yet in $$file"; exit 0; fi; \
		echo "=== Last $$N entries ($$file) ==="; \
		awk '/^===== ENTRY .* START =====/{printf("%s\n",$$0)} END{}' "$$file" | tail -n $$N

log-tail-last: ## Show last command details from combined.log
	@. scripts/make-helpers.sh
	@combined=$$(D3K_LOG_DIR="$$D3K_LOG_DIR" D3K_LOG_FILE="$$D3K_LOG_FILE" bash -lc 'dir=$${D3K_LOG_DIR:-.make-logs}; echo $${D3K_LOG_FILE:-$$dir/combined.log}'); \
		if [ ! -f "$$combined" ]; then echo "Combined log not found: $$combined"; exit 1; fi; \
		awk 'BEGIN{start=0} /^===== ENTRY .* START =====/{start=NR} {lines[NR]="" $$0} /^===== ENTRY .* END =====/{block_start=start; block_end=NR} END{ if (block_start) { for(i=block_start;i<=block_end;i++) print lines[i] } }' "$$combined"

## ========== Chrome CDP Management ==========

start-chrome-cdp: ## Start Chrome with CDP (now unified to cross-platform launcher)
	@$(MAKE) -C $(MAKEFILE_DIR) start-chrome-cdp-xplat


start-chrome-cdp-xplat: ## Start Chrome with CDP via cross-platform Node launcher
	@. scripts/make-helpers.sh
	@echo "🌐 Starting Chrome with CDP (cross-platform launcher)..."
	@echo "PWD: $$(pwd)"
	@echo "CDP check URL: $(CDP_CHECK_URL)"
	@APP_URL="http://localhost:3000/"; \
	echo "App URL: $$APP_URL"; \
	/usr/bin/env bash -lc 'cd "$(MAKEFILE_DIR)" && . scripts/make-helpers.sh && run_cmd "launch chrome cdp" node scripts/launch-chrome-cdp.js --app-url '"$$APP_URL"' --check-url "$(CDP_CHECK_URL)" --cdp-port 9222' || echo "[CDP] ⚠️  Chrome launcher exited with error (check logs)"

stop-chrome-cdp: ## Stop Chrome CDP process
	@. scripts/make-helpers.sh
	@echo "Stopping Chrome CDP..."
	@if [ "$(IS_WSL2)" = "1" ]; then \
		/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "stop chrome (powershell)" bash -lc "powershell.exe -Command \"Get-Process chrome | Where-Object {\$$_.CommandLine -like '*remote-debugging-port*'} | Stop-Process\""'; \
	else \
		/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "pkill chrome" bash -lc "pkill -f '"'"'chrome.*remote-debugging-port'"'"' 2>/dev/null || true"'; \
	fi
	@echo "✅ Chrome stopped"

## ========== Information ==========

status: ## Show development environment status
	@echo "=== Dev3000 Status ==="
	@echo ""
	@echo "Docker Containers:"
	@docker compose ps
	@echo ""
	@echo "Chrome CDP:"
	@if curl -s $(CDP_CHECK_URL) > /dev/null 2>&1; then \
		echo "  ✅ Chrome running with CDP on port 9222 ($(CDP_URL))"; \
		BROWSER_VER=$$(curl -s $(CDP_CHECK_URL) | grep -o '"Browser":"[^"]*"' | cut -d'"' -f4); \
		CDP_WS_URL=$$(curl -s $(CDP_CHECK_URL) | grep -o '"webSocketDebuggerUrl":"[^"]*"' | cut -d'"' -f4); \
		echo "  Version: $$BROWSER_VER"; \
		echo "  WebSocket URL: $$CDP_WS_URL"; \
	else \
		echo "  ❌ Chrome CDP not accessible ($(CDP_URL))"; \
		fi
		@echo ""
		@echo "CDP Integration:"
		@if docker ps --format '{{.Names}}' | grep -q 'dev3000'; then \
			CDP_ENV=$$(docker inspect dev3000 2>/dev/null | grep -o '"DEV3000_CDP_URL=[^"]*"' | head -1 | cut -d'=' -f2 | tr -d '"' || echo ""); \
			if [ -n "$$CDP_ENV" ]; then \
				echo "  ✅ Container configured with CDP URL"; \
				echo "  URL: $$CDP_ENV"; \
			else \
				echo "  ⚠️  Container running without explicit CDP URL (auto-detect mode)"; \
			fi; \
		else \
			echo "  ❌ Dev3000 container not running"; \
		fi

## ========== Testing ==========

test: ## Run Node/TS tests (Vitest)
	@. scripts/make-helpers.sh
	@run_cmd "pnpm test" pnpm -s test

test-node: ## Alias for make test
	@$(MAKE) test

test-shellspec: ## Run ShellSpec suite for Make targets (e.g., make test-shellspec ARGS="--format progress")
	@. scripts/make-helpers.sh
	@# Ensure expected dev3000 container is running (and belongs to this compose project)
	@echo "[TEST] Ensuring dev3000 container is running..."
	@if ! docker ps --format '{{.Names}}' | grep -q '^dev3000$$'; then \
		if [ ! -f "frontend/Dockerfile.dev" ]; then \
			/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "deploy-frontend default" bash -lc "make -s deploy-frontend APP=nextjs16"'; \
		fi; \
		/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "dev-up (pre-test)" bash -lc "make -s dev-up"'; \
	else \
		LABELS=$$(docker inspect dev3000 --format '{{ index .Config.Labels "com.docker.compose.project" }} {{ index .Config.Labels "com.docker.compose.service" }}' 2>/dev/null || echo ""); \
		if [ "$$LABELS" != "dev3000 dev3000" ]; then \
			echo "[TEST] ⚠️ dev3000 exists but is not this compose service (labels: '$$LABELS'). Restarting..."; \
			docker compose down || true; \
			if [ ! -f "frontend/Dockerfile.dev" ]; then \
				/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "deploy-frontend default" bash -lc "make -s deploy-frontend APP=nextjs16"'; \
			fi; \
			/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "dev-up (pre-test)" bash -lc "make -s dev-up"'; \
		fi; \
	fi
	@run_cmd "shellspec" bash scripts/run-shellspec.sh $(if $(ARGS),$(ARGS),--format documentation)
	@$(MAKE) log-ls

test-all: ## Run both Node tests and ShellSpec
	@$(MAKE) test
	@$(MAKE) test-shellspec $(if $(ARGS),ARGS="$(ARGS)")

## ========== Makefile Linting ==========

install-checkmake: ## Install checkmake Makefile linter (tries system/go/vendor)
	@. scripts/make-helpers.sh
	@# 1) If already available, show version
	@if command -v checkmake >/dev/null 2>&1; then \
		run_cmd "checkmake --version" checkmake --version; \
		exit 0; \
	fi
	@# 2) Try apt (Ubuntu/Debian)
	@if command -v apt-get >/dev/null 2>&1; then \
		if confirm "Install checkmake via apt-get now? (sudo may be required)"; then \
			/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "apt-get install checkmake" bash -lc "sudo apt-get update && sudo apt-get install -y checkmake"' && exit 0 || true; \
		else \
			hint "Skipping apt-get install for checkmake."; \
		fi; \
	fi; \
	# 3) Ensure Go exists (optional auto-install on apt systems)
	if ! command -v go >/dev/null 2>&1; then \
		if command -v apt-get >/dev/null 2>&1; then \
			if confirm "Go toolchain not found. Install golang-go now?"; then \
				/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "apt-get install golang-go" bash -lc "sudo apt-get update && sudo apt-get install -y golang-go"' || true; \
			fi; \
		fi; \
	fi; \
	# 4) Try Go install to local tools dir
	TOOLS=.tools/checkmake/bin; mkdir -p "$$TOOLS"; \
	if command -v go >/dev/null 2>&1; then \
		/usr/bin/env bash -lc '. scripts/make-helpers.sh; run_cmd "go install checkmake" bash -lc "GOBIN=\"$$PWD/.tools/checkmake/bin\" go install github.com/checkmake/checkmake/cmd/checkmake@latest"'; \
		if [ -x "$$TOOLS/checkmake" ]; then echo "Installed: $$TOOLS/checkmake"; exit 0; fi; \
	fi; \
	echo "❌ Failed to install checkmake automatically."; \
	echo "   Try one of:"; \
	echo "     - sudo apt-get install -y checkmake"; \
	echo "     - go install github.com/checkmake/checkmake/cmd/checkmake@latest"; \
	echo "     - or install a prebuilt binary from GitHub releases"; \
	exit 1

lint-make: ## Lint Makefile with checkmake (installs if needed)
	@. scripts/make-helpers.sh
	@# Ensure we have a usable binary (system or vendored)
	@CHECKMAKE_BIN=$$(command -v checkmake 2>/dev/null || echo "$$PWD/.tools/checkmake/bin/checkmake"); \
		if [ ! -x "$$CHECKMAKE_BIN" ]; then \
			$(MAKE) -s install-checkmake || true; \
			CHECKMAKE_BIN=$$(command -v checkmake 2>/dev/null || echo "$$PWD/.tools/checkmake/bin/checkmake"); \
		fi; \
		if [ ! -x "$$CHECKMAKE_BIN" ]; then \
			hint "checkmake not available. Install with: make install-checkmake"; \
			exit 0; \
		fi; \
		echo "Running: $$CHECKMAKE_BIN Makefile"; \
		"$$CHECKMAKE_BIN" Makefile || true

## ========== Testing (lightweight) ==========

test-echo: ## Test-only: exercise logger with simple success command
	@. scripts/make-helpers.sh
	@run_cmd "test echo" bash -lc "echo 'Hello from STDOUT'; echo 'Hello from STDERR' 1>&2"

test-fail: ## Test-only: exercise logger on failure (exit 2)
	@. scripts/make-helpers.sh
	@run_cmd "test fail" bash -lc "echo 'About to fail'; echo 'Error happened' 1>&2; exit 2"
