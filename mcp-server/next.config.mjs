import path from "path"
import { fileURLToPath } from "url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))

const nextConfig = {
  reactStrictMode: true,
  reactCompiler: true,
  // Cache Components enabled for Next.js 16 canary
  // In canary versions, cacheComponents is at root level
  cacheComponents: true,
  experimental: {
    turbopackFileSystemCacheForDev: true
  },
  devIndicators: false,
  turbopack: {
    root: path.join(__dirname, "..")
  },
  // Disable image optimization to avoid sharp dependency issues
  images: {
    unoptimized: true
  }
}

export default nextConfig
