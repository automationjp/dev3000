#!/bin/sh
set -e

# Fix permissions for WSL2 mounted volumes
chmod -R u+w /app/frontend 2>/dev/null || true

echo "Dev3000 Container Starting..."
echo "Working directory: $(pwd)"

# Check if package.json exists
if [ ! -f package.json ]; then
  echo "Error: No package.json found in /app/frontend"
  echo "Please ensure your frontend app is properly mounted"
  exit 1
fi

# Check and install dependencies if needed
if [ ! -f node_modules/.pnpm/lock.yaml ] && [ ! -f node_modules/.bin/next ]; then
  echo "📦 Installing dependencies (first run)..."
  # Configure pnpm to use container temp directories
  pnpm config set store-dir /tmp/.pnpm-store
  pnpm config set cache-dir /tmp/.pnpm-cache
  # Install with config to avoid WSL2 permission issues
  pnpm install --config.package-import-method=hardlink --no-lockfile || exit 1
  echo "✅ Dependencies installed"
else
  echo "✅ Dependencies already installed"
fi

# Remove stale lock file
rm -f /tmp/dev3000-*.lock

# Start dev3000
echo "Starting dev3000..."
exec node /usr/local/lib/dev3000/dist/cli.js "$@"
