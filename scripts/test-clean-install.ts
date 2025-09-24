#!/usr/bin/env tsx
/**
 * Test dev3000 in a clean environment similar to what real users experience
 * This script creates isolated environments to test global installations
 */

import { execSync, spawn } from "child_process"
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs"
import { tmpdir } from "os"
import { join } from "path"

const GREEN = "\x1b[32m"
const RED = "\x1b[31m"
const YELLOW = "\x1b[33m"
const BLUE = "\x1b[36m"
const RESET = "\x1b[0m"

function log(message: string, color = RESET) {
  console.log(`${color}${message}${RESET}`)
}

interface TestResult {
  name: string
  passed: boolean | "skipped"
  error?: string
  duration: number
}

class CleanEnvironmentTester {
  private results: TestResult[] = []

  /**
   * Create a minimal PATH that simulates a fresh system
   */
  private getCleanPath(): string {
    // Include system essentials and Node.js location
    const nodePath = process.execPath
    const nodeDir = nodePath.substring(0, nodePath.lastIndexOf("/"))

    const essentialPaths = [
      nodeDir, // Include Node.js binary location
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
      "/usr/sbin",
      "/sbin"
    ]
    return essentialPaths.join(":")
  }

  /**
   * Create a clean environment with minimal variables
   */
  private getCleanEnv(): NodeJS.ProcessEnv {
    return {
      PATH: this.getCleanPath(),
      HOME: process.env.HOME || "",
      USER: process.env.USER || "",
      LANG: "en_US.UTF-8",
      // Explicitly unset common dev environment variables
      NODE_ENV: undefined,
      npm_config_prefix: undefined,
      NVM_DIR: undefined,
      PNPM_HOME: undefined
    }
  }

  /**
   * Test installation using Docker (most isolated)
   */
  async testDockerInstall(tarballPath: string): Promise<TestResult> {
    const startTime = Date.now()
    const testName = "Docker Clean Install"

    try {
      log(`\n🐳 Testing ${testName}...`, BLUE)

      // Check if Docker is available and running
      try {
        execSync("docker --version", { stdio: "ignore" })
        // Also check if Docker daemon is running
        execSync("docker info", { stdio: "ignore" })
      } catch {
        log("Docker not available or not running, skipping Docker test", YELLOW)
        return {
          name: testName,
          passed: "skipped",
          error: "Docker not available or daemon not running",
          duration: 0
        } as TestResult
      }

      // Create a Dockerfile for testing
      const tempDir = mkdtempSync(join(tmpdir(), "d3k-docker-test-"))
      const dockerfilePath = join(tempDir, "Dockerfile")

      writeFileSync(
        dockerfilePath,
        `
FROM node:20-slim
WORKDIR /test
COPY *.tgz ./
# Test with npm (most common)
RUN npm install -g ./$(ls *.tgz)
# Test that d3k command exists
RUN which d3k
# Test running with --version
RUN d3k --version
`
      )

      // Copy tarball to temp directory
      execSync(`cp ${tarballPath} ${tempDir}/`)

      // Build Docker image
      log("Building Docker image...", YELLOW)
      execSync(`docker build -t d3k-test-clean ${tempDir}`, { stdio: "inherit" })

      // Run tests in container
      log("Running d3k in Docker container...", YELLOW)
      const output = execSync(`docker run --rm d3k-test-clean sh -c "d3k --version && echo 'SUCCESS'"`, {
        encoding: "utf-8"
      })

      const passed = output.includes("SUCCESS")

      // Cleanup
      execSync("docker rmi d3k-test-clean", { stdio: "ignore" })
      rmSync(tempDir, { recursive: true })

      return {
        name: testName,
        passed,
        duration: Date.now() - startTime
      }
    } catch (error) {
      return {
        name: testName,
        passed: false,
        error: error instanceof Error ? error.message : String(error),
        duration: Date.now() - startTime
      }
    }
  }

  /**
   * Test installation in isolated directory with clean environment using npm
   */
  async testCleanEnvInstall(tarballPath: string): Promise<TestResult> {
    const startTime = Date.now()
    const testName = "Clean Environment Install (npm)"

    try {
      log(`\n📦 Testing ${testName}...`, BLUE)

      // Create isolated temp directory
      const testDir = mkdtempSync(join(tmpdir(), "d3k-clean-test-"))
      const npmPrefix = join(testDir, "npm-global")

      mkdirSync(npmPrefix, { recursive: true })

      // Set up clean environment with minimal PATH
      const cleanEnv = {
        ...this.getCleanEnv(),
        npm_config_prefix: npmPrefix,
        PATH: `${join(npmPrefix, "bin")}:${this.getCleanPath()}`
      }

      // Install dev3000 globally using npm
      log("Installing dev3000 globally with npm...", YELLOW)
      execSync(`npm install -g ${tarballPath}`, {
        env: cleanEnv,
        cwd: testDir,
        stdio: "inherit"
      })

      // Test that it runs
      log("Testing d3k command...", YELLOW)

      // First check if d3k was installed
      try {
        const whichOutput = execSync(`which d3k`, {
          env: cleanEnv,
          encoding: "utf-8"
        })
        log(`d3k installed at: ${whichOutput.trim()}`, YELLOW)
      } catch (e) {
        log("Failed to find d3k executable", RED)
        throw e
      }

      // Run d3k --version
      log("Running d3k --version...", YELLOW)
      const output = execSync(`d3k --version`, {
        env: cleanEnv,
        cwd: testDir,
        encoding: "utf-8"
      })

      log(`Output: ${output.trim()}`, YELLOW)

      const passed = output.includes("0.0") || output.includes("dev3000")

      // Cleanup
      rmSync(testDir, { recursive: true })

      return {
        name: testName,
        passed,
        duration: Date.now() - startTime
      }
    } catch (error) {
      return {
        name: testName,
        passed: false,
        error: error instanceof Error ? error.message : String(error),
        duration: Date.now() - startTime
      }
    }
  }

  /**
   * Test with minimal PATH using npm
   */
  async testMinimalPath(tarballPath: string): Promise<TestResult> {
    const startTime = Date.now()
    const testName = "Minimal PATH Test (npm)"

    try {
      log(`\n🛤️ Testing ${testName}...`, BLUE)

      // Get Node.js binary location
      const nodePath = process.execPath
      const nodeDir = nodePath.substring(0, nodePath.lastIndexOf("/"))

      // Create a test script that runs with minimal PATH
      const testScript = `
        set -e
        # Include Node.js in minimal PATH
        export PATH="${nodeDir}:/usr/local/bin:/usr/bin:/bin"
        
        # Create temporary directory for npm global installs
        TEMP_DIR=$(mktemp -d)
        export npm_config_prefix="$TEMP_DIR/npm-global"
        mkdir -p "$npm_config_prefix"
        
        # Add npm global bin to PATH
        export PATH="$npm_config_prefix/bin:$PATH"
        
        # Install and test dev3000
        echo "Installing dev3000 with npm..."
        npm install -g ${tarballPath}
        
        # Verify d3k is available
        which d3k || (echo "d3k not found in PATH" && exit 1)
        
        # Test it runs
        d3k --version
        
        # Cleanup
        rm -rf "$TEMP_DIR"
      `

      const output = execSync(testScript, {
        shell: "/bin/bash",
        encoding: "utf-8"
      })

      const passed = output.includes("0.0") || output.includes("dev3000")

      return {
        name: testName,
        passed,
        duration: Date.now() - startTime
      }
    } catch (error) {
      return {
        name: testName,
        passed: false,
        error: error instanceof Error ? error.message : String(error),
        duration: Date.now() - startTime
      }
    }
  }

  /**
   * Test server startup in clean environment
   */
  async testServerStartup(_tarballPath: string): Promise<TestResult> {
    const startTime = Date.now()
    const testName = "MCP Server Startup Test"

    try {
      log(`\n🚀 Testing ${testName}...`, BLUE)

      // Create test directory with minimal app
      const testDir = mkdtempSync(join(tmpdir(), "d3k-startup-test-"))
      const packageJson = {
        name: "test-app",
        scripts: {
          dev: "echo 'Test server running on port 3000'"
        }
      }
      writeFileSync(join(testDir, "package.json"), JSON.stringify(packageJson, null, 2))

      // Run d3k with clean environment
      const d3kProcess = spawn("d3k", ["--debug", "--servers-only"], {
        cwd: testDir,
        env: {
          ...this.getCleanEnv(),
          PATH: process.env.PATH // Need current PATH to find d3k
        }
      })

      let output = ""
      let errorOutput = ""
      let hasError = false

      d3kProcess.stdout.on("data", (data) => {
        output += data.toString()
      })

      d3kProcess.stderr.on("data", (data) => {
        errorOutput += data.toString()
      })

      // Wait for successful startup or failure
      const timeoutPromise = new Promise((resolve) => setTimeout(resolve, 35000)) // Slightly longer than MCP timeout
      const startupPromise = new Promise((resolve) => {
        const checkInterval = setInterval(() => {
          // Check for successful MCP server startup
          if (
            output.includes("MCP server process spawned") ||
            output.includes("Waiting for MCP server to be ready") ||
            output.includes("Starting dev3000 MCP server")
          ) {
            // Keep waiting for actual server ready status
          }

          // Check for errors that indicate startup failure
          if (
            output.includes("MCP server failed to start") ||
            output.includes("dev3000 exited due to") ||
            output.includes("Failed to start development environment") ||
            errorOutput.includes("Error:")
          ) {
            hasError = true
            clearInterval(checkInterval)
            resolve(false)
          }

          // Check for successful completion
          if (
            output.includes("MCP server ready") ||
            output.includes("MCP server health check: 200") ||
            output.includes("MCP server health check: 404")
          ) {
            clearInterval(checkInterval)
            resolve(true)
          }
        }, 500)
      })

      const result = await Promise.race([startupPromise, timeoutPromise])

      // Kill the process
      d3kProcess.kill()

      // Log debug info on failure
      if (result !== true || hasError) {
        log(`Test failed. Output captured:`, YELLOW)
        log(`STDOUT: ${output.slice(-500)}`, YELLOW)
        log(`STDERR: ${errorOutput.slice(-500)}`, YELLOW)
      }

      // Cleanup
      rmSync(testDir, { recursive: true })

      return {
        name: testName,
        passed: result === true && !hasError,
        error: result !== true ? "MCP server failed to start or errored during startup" : undefined,
        duration: Date.now() - startTime
      }
    } catch (error) {
      return {
        name: testName,
        passed: false,
        error: error instanceof Error ? error.message : String(error),
        duration: Date.now() - startTime
      }
    }
  }

  /**
   * Test pnpm installation specifically
   */
  async testPnpmInstall(tarballPath: string): Promise<TestResult> {
    const startTime = Date.now()
    const testName = "pnpm Global Install Test"

    try {
      log(`\n🔷 Testing ${testName}...`, BLUE)

      // Create a test script that installs pnpm first, then dev3000
      const testScript = `
        set -e
        
        # Create temporary directory
        TEMP_DIR=$(mktemp -d)
        export PNPM_HOME="$TEMP_DIR/.pnpm"
        mkdir -p "$PNPM_HOME"
        export PATH="$PNPM_HOME:$PATH"
        
        # Install pnpm
        echo "Installing pnpm..."
        npm install -g --prefix "$TEMP_DIR" pnpm
        
        # Link pnpm to PNPM_HOME
        ln -sf "$TEMP_DIR/node_modules/.bin/pnpm" "$PNPM_HOME/pnpm"
        
        # Verify pnpm works
        which pnpm
        pnpm --version
        
        # Install dev3000 with pnpm
        echo "Installing dev3000 with pnpm..."
        pnpm install -g "${tarballPath}"
        
        # Test it runs
        pnpm exec d3k --version
        
        # Cleanup
        rm -rf "$TEMP_DIR"
      `

      const output = execSync(testScript, {
        shell: "/bin/bash",
        encoding: "utf-8"
      })

      const passed = output.includes("0.0") || output.includes("dev3000")

      return {
        name: testName,
        passed,
        duration: Date.now() - startTime
      }
    } catch (error) {
      return {
        name: testName,
        passed: false,
        error: error instanceof Error ? error.message : String(error),
        duration: Date.now() - startTime
      }
    }
  }

  async runAllTests(tarballPath: string) {
    log("🧹 Starting Clean Environment Tests", GREEN)
    log(`📦 Testing with: ${tarballPath}`, YELLOW)

    // Run tests
    this.results.push(await this.testDockerInstall(tarballPath))
    this.results.push(await this.testCleanEnvInstall(tarballPath))
    this.results.push(await this.testMinimalPath(tarballPath))
    this.results.push(await this.testPnpmInstall(tarballPath))
    this.results.push(await this.testServerStartup(tarballPath))

    // Summary
    log("\n📊 Test Results Summary", GREEN)
    log("=".repeat(50))

    let allPassed = true
    let hasFailures = false

    for (const result of this.results) {
      let status: string
      let color: string

      if (result.passed === "skipped") {
        status = `⏭️  SKIPPED`
        color = YELLOW
      } else if (result.passed) {
        status = `✅ PASSED`
        color = GREEN
      } else {
        status = `❌ FAILED`
        color = RED
        hasFailures = true
      }

      const duration = `(${(result.duration / 1000).toFixed(2)}s)`
      log(`${status} ${result.name} ${duration}`, color)

      if (result.error && result.passed !== "skipped") {
        log(`   Error: ${result.error}`, YELLOW)
      } else if (result.passed === "skipped") {
        log(`   Reason: ${result.error}`, YELLOW)
      }
    }

    // Only fail if there were actual test failures, not skips
    allPassed = !hasFailures

    log("=".repeat(50))

    if (allPassed) {
      log("\n✨ All tests passed! Safe to publish.", GREEN)
      return 0
    } else {
      log("\n⚠️  Some tests failed. Review before publishing.", RED)
      return 1
    }
  }
}

// Main execution
async function main() {
  // Clean up any old tarballs first
  try {
    execSync("rm -f dev3000-*.tgz", { stdio: "ignore" })
  } catch {
    // Ignore errors
  }

  // Build using shared build script (same as canary.sh)
  log("Building project...", YELLOW)
  execSync("./scripts/build.sh", { stdio: "inherit" })

  // Create fresh tarball (suppress verbose file listing)
  log("Creating tarball...", YELLOW)
  const packOutput = execSync("pnpm pack 2>&1 | tail -n 1", { encoding: "utf-8", shell: true })
  const tarballName = packOutput.trim()
  const fullPath = join(process.cwd(), tarballName)

  log(`Created: ${tarballName}`, GREEN)

  const tester = new CleanEnvironmentTester()
  const exitCode = await tester.runAllTests(fullPath)

  process.exit(exitCode)
}

main().catch((error) => {
  log(`Fatal error: ${error}`, RED)
  process.exit(1)
})
