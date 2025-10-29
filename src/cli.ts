#!/usr/bin/env -S node --no-warnings

import { execSync, spawn } from "node:child_process"
import chalk from "chalk"
import { Command } from "commander"
import { existsSync, readFileSync } from "fs"
import { homedir, tmpdir } from "os"
import { detect } from "package-manager-detector"
import { dirname, join } from "path"
import { fileURLToPath } from "url"
import { createPersistentLogFile, startDevEnvironment } from "./dev-environment.js"
import { getProjectName } from "./utils/project-name.js"

interface ProjectConfig {
  type: "node" | "python" | "rails"
  framework?: "nextjs" | "svelte" | "other" // For node projects
  packageManager?: string // Only for node projects
  pythonCommand?: string // Only for python projects
  defaultScript: string
  defaultPort: string
}

function detectPythonCommand(debug = false): string {
  // Check if we're in a virtual environment
  if (process.env.VIRTUAL_ENV) {
    if (debug) {
      console.log(`[DEBUG] Virtual environment detected: ${process.env.VIRTUAL_ENV}`)
      console.log(`[DEBUG] Using activated python command`)
    }
    return "python"
  }

  // Check if python3 is available and prefer it
  try {
    execSync("python3 --version", { stdio: "ignore" })
    if (debug) {
      console.log(`[DEBUG] python3 is available, using python3`)
    }
    return "python3"
  } catch {
    if (debug) {
      console.log(`[DEBUG] python3 not available, falling back to python`)
    }
    return "python"
  }
}

async function detectProjectType(debug = false): Promise<ProjectConfig> {
  // Check for Python project
  if (existsSync("requirements.txt") || existsSync("pyproject.toml")) {
    if (debug) {
      console.log(`[DEBUG] Python project detected (found requirements.txt or pyproject.toml)`)
    }
    return {
      type: "python",
      defaultScript: "main.py",
      defaultPort: "8000", // Common Python web server port
      pythonCommand: detectPythonCommand(debug)
    }
  }

  // Check for Rails project
  if (existsSync("Gemfile") && existsSync("config/application.rb")) {
    if (debug) {
      console.log(`[DEBUG] Rails project detected (found Gemfile and config/application.rb)`)
    }
    return {
      type: "rails",
      defaultScript: "server",
      defaultPort: "3000" // Rails default port
    }
  }

  // Check for Node.js project using package-manager-detector
  const detected = await detect()

  // Helper to detect framework for Node.js projects
  const detectFramework = (): "nextjs" | "svelte" | "other" => {
    // Check for Next.js
    const nextConfigFiles = ["next.config.js", "next.config.ts", "next.config.mjs", "next.config.cjs"]
    if (nextConfigFiles.some((file) => existsSync(file))) {
      if (debug) {
        console.log(`[DEBUG] Next.js framework detected`)
      }
      return "nextjs"
    }

    // Check for Svelte - look for svelte.config.js or svelte dependency
    if (existsSync("svelte.config.js")) {
      if (debug) {
        console.log(`[DEBUG] Svelte framework detected (svelte.config.js)`)
      }
      return "svelte"
    }

    // Check package.json for svelte dependency
    try {
      if (existsSync("package.json")) {
        const packageJson = JSON.parse(readFileSync("package.json", "utf-8"))
        const deps = { ...packageJson.dependencies, ...packageJson.devDependencies }
        if (deps.svelte || deps["@sveltejs/kit"]) {
          if (debug) {
            console.log(`[DEBUG] Svelte framework detected (package.json dependency)`)
          }
          return "svelte"
        }
      }
    } catch {
      // Ignore parse errors
    }

    return "other"
  }

  if (detected) {
    const framework = detectFramework()
    if (debug) {
      console.log(`[DEBUG] Node.js project detected with ${detected.agent} package manager and ${framework} framework`)
    }
    return {
      type: "node",
      framework,
      packageManager: detected.agent,
      defaultScript: "dev",
      defaultPort: "3000"
    }
  }

  // Fallback to npm for Node.js
  const framework = detectFramework()
  if (debug) {
    console.log(`[DEBUG] No project files detected, defaulting to Node.js with npm and ${framework} framework`)
  }
  return {
    type: "node",
    framework,
    packageManager: "npm",
    defaultScript: "dev",
    defaultPort: "3000"
  }
}

// Read version from package.json
function getVersion(): string {
  try {
    const currentFile = fileURLToPath(import.meta.url)
    const packageRoot = dirname(dirname(currentFile)) // Go up from dist/ to package root
    const packageJsonPath = join(packageRoot, "package.json")
    const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8"))
    let version = packageJson.version

    // Use git to detect if we're in the dev3000 source repository
    try {
      const gitRemote = execSync("git remote get-url origin 2>/dev/null", {
        cwd: packageRoot,
        encoding: "utf8"
      }).trim()

      if (gitRemote.includes("vercel-labs/dev3000") && !version.includes("canary")) {
        version += "-local"
      }
    } catch {
      // Not in git repo or no git - use version as-is
    }

    return version
  } catch (_error) {
    return "0.0.0" // fallback
  }
}

// Check if installed globally before proceeding
function checkGlobalInstall() {
  const currentFile = fileURLToPath(import.meta.url)
  const packageRoot = dirname(dirname(currentFile))

  // Check common global install paths
  const globalPaths = [
    "/usr/local/lib/node_modules",
    "/usr/lib/node_modules",
    process.env.NPM_CONFIG_PREFIX && join(process.env.NPM_CONFIG_PREFIX, "lib/node_modules"),
    process.env.PNPM_HOME,
    process.platform === "win32" && process.env.APPDATA && join(process.env.APPDATA, "npm/node_modules"),
    process.env.HOME && join(process.env.HOME, ".npm-global/lib/node_modules"),
    process.env.HOME && join(process.env.HOME, ".pnpm"),
    process.env.HOME && join(process.env.HOME, ".yarn/global/node_modules")
  ].filter(Boolean) as string[]

  // Check if our package path contains any of these global paths
  for (const globalPath of globalPaths) {
    if (packageRoot.includes(globalPath)) {
      return true
    }
  }

  // Additional check: if we're in node_modules but not in a project's node_modules
  if (packageRoot.includes("node_modules") && !existsSync(join(packageRoot, "..", "..", "..", "package.json"))) {
    return true
  }

  // If we're in dev (running from source), that's fine
  if (!packageRoot.includes("node_modules")) {
    return true
  }

  return false
}

// Perform the check
if (!checkGlobalInstall()) {
  console.error(chalk.red("\n❌ Error: dev3000 must be installed globally.\n"))
  console.error(chalk.white("This package won't work correctly as a local dependency.\n"))
  console.error(chalk.cyan("To install globally, use one of these commands:"))
  console.error(chalk.gray("  pnpm install -g dev3000"))
  console.error(chalk.gray("  npm install -g dev3000"))
  console.error(chalk.gray("  yarn global add dev3000\n"))
  console.error(chalk.white("Then run 'd3k' or 'dev3000' from any project directory.\n"))
  process.exit(1)
}

const program = new Command()

program
  .name("dev3000")
  .description("AI-powered development tools with browser monitoring and MCP server")
  .version(getVersion())

program
  .description("AI-powered development tools with browser monitoring and MCP server")
  .option("-p, --port <port>", "Development server port (auto-detected by project type)")
  .option("-m, --port-mcp <port>", "MCP server port", "3684")
  .option("-s, --script <script>", "Script to run (e.g. dev, main.py) - auto-detected by project type")
  .option("-c, --command <command>", "Custom command to run (overrides auto-detection and --script)")
  .option("--profile-dir <dir>", "Chrome profile directory", join(tmpdir(), "dev3000-chrome-profile"))
  .option(
    "--browser <path>",
    "Full path to browser executable (e.g. for Arc: '/Applications/Arc.app/Contents/MacOS/Arc')"
  )
  .option("--servers-only", "Run servers only, skip browser launch (use with Chrome extension)")
  .option("--debug", "Enable debug logging to console (automatically disables TUI)")
  .option("-t, --tail", "Output consolidated logfile to terminal (like tail -f)")
  .option("--no-tui", "Disable TUI mode and use standard terminal output")
  .option(
    "--date-time <format>",
    "Timestamp format: 'local' (default, e.g. 12:54:03 PM) or 'utc' (ISO string)",
    "local"
  )
  .option("--plugin-react-scan", "Enable react-scan performance monitoring for React applications")
  .option("--no-chrome-devtools-mcp", "Disable chrome-devtools MCP integration (enabled by default)")
  .option("--kill-mcp", "Kill the MCP server on port 3684 and exit")
  .action(async (options) => {
    // Handle --kill-mcp option
    if (options.killMcp) {
      console.log(chalk.yellow("🛑 Killing MCP server on port 3684..."))
      try {
        await new Promise<void>((resolve) => {
          const killProcess = spawn("sh", ["-c", "lsof -ti:3684 | xargs kill -9"], { stdio: "inherit" })
          killProcess.on("exit", () => resolve())
        })
        console.log(chalk.green("✅ MCP server killed"))
      } catch (_error) {
        console.log(chalk.gray("⚠️ No MCP server found on port 3684"))
      }
      process.exit(0)
    }

    // Detect project type and configuration
    const projectConfig = await detectProjectType(options.debug)

    // Use defaults from project detection if not explicitly provided
    const port = options.port || projectConfig.defaultPort
    const script = options.script || projectConfig.defaultScript
    const userSetPort = options.port !== undefined
    const userSetMcpPort = process.argv.includes("--port-mcp") || process.argv.includes("-p-mcp")

    // Generate server command based on custom command or project type
    let serverCommand: string
    if (options.command) {
      // Use custom command if provided - this overrides everything
      serverCommand = options.command
      if (options.debug) {
        console.log(`[DEBUG] Using custom command: ${serverCommand}`)
      }
    } else if (projectConfig.type === "python") {
      serverCommand = `${projectConfig.pythonCommand} ${script}`
    } else if (projectConfig.type === "rails") {
      serverCommand = `bundle exec rails ${script}`
    } else {
      // Node.js project
      serverCommand = `${projectConfig.packageManager} run ${script}`
    }

    // Check for circular dependency - detect if the script would invoke dev3000 itself
    // Skip this check if using a custom command
    if (projectConfig.type === "node" && !options.command) {
      try {
        const packageJson = JSON.parse(readFileSync(join(process.cwd(), "package.json"), "utf-8"))
        const scriptContent = packageJson.scripts?.[script]

        // Check if the script invokes dev3000 or d3k
        if (scriptContent && (scriptContent.includes("dev3000") || /\bd3k\b/.test(scriptContent))) {
          console.error(chalk.red(`\n❌ Circular dependency detected!`))
          console.error(
            chalk.yellow(
              `   The "${script}" script in package.json calls dev3000, which would create an infinite loop.`
            )
          )
          console.error(chalk.yellow(`   Current script content: "${scriptContent}"`))
          console.error(chalk.yellow(`\n💡 Fix this by either:`))
          console.error(chalk.yellow(`   1. Change the "${script}" script to call your actual dev server`))
          console.error(
            chalk.yellow(`   2. Use dev3000 globally (run 'd3k' directly) instead of via package.json scripts`)
          )
          console.error(
            chalk.yellow(
              `   3. Use a different script name that doesn't invoke dev3000 (e.g., '${script === "dev" ? "dev:next" : "dev:server"}')`
            )
          )
          process.exit(1)
        }
      } catch (_error) {
        // Ignore errors reading package.json
      }
    }

    if (options.debug) {
      console.log(`[DEBUG] Project type: ${projectConfig.type}`)
      console.log(`[DEBUG] Port: ${port} (${options.port ? "explicit" : "auto-detected"})`)
      console.log(`[DEBUG] Script: ${script} (${options.script ? "explicit" : "auto-detected"})`)
      console.log(`[DEBUG] Server command: ${serverCommand}`)
    }

    // Detect which command name was used (dev3000 or d3k)
    const executablePath = process.argv[1]
    const commandName = executablePath.endsWith("/d3k") || executablePath.includes("/d3k") ? "d3k" : "dev3000"

    try {
      // Create persistent log file
      const logFile = createPersistentLogFile()

      // Get unique project name to create profile dir
      const projectName = getProjectName()
      const profileDir = join(homedir(), ".d3k", "chrome-profiles", projectName)

      await startDevEnvironment({
        ...options,
        port,
        portMcp: options.portMcp,
        defaultPort: projectConfig.defaultPort,
        framework: projectConfig.framework,
        userSetPort,
        userSetMcpPort,
        logFile,
        profileDir,
        serverCommand,
        debug: options.debug,
        serversOnly: options.serversOnly,
        commandName,
        tail: options.tail,
        tui: options.noTui !== true && !options.debug, // TUI is default unless --no-tui or --debug is specified
        dateTimeFormat: options.dateTime || "local",
        pluginReactScan: options.pluginReactScan || false,
        chromeDevtoolsMcp: options.chromeDevtoolsMcp !== false // Default to true unless explicitly disabled
      })
    } catch (error) {
      console.error(chalk.red("❌ Failed to start development environment:"), error)
      process.exit(1)
    }
  })

program.parse()
