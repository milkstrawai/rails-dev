import { pathToFileURL } from 'node:url'

const [modulePath, directory, routeJSON] = process.argv.slice(2)
const { RouteStore } = await import(pathToFileURL(modulePath).href)
const store = new RouteStore(directory)
const routes = Object.entries(JSON.parse(routeJSON))

function stop() {
  cleanup()
  process.exit(0)
}

function cleanup() {
  for (const [hostname] of routes) store.removeRoute(hostname, process.pid)
}

process.on('SIGTERM', stop)
process.on('SIGINT', stop)

try {
  for (const [hostname, port] of routes) store.addRoute(hostname, port, process.pid)
  setInterval(() => {}, 60_000)
  console.log('HTTPS routes registered')
} catch (error) {
  cleanup()
  console.error(error.message)
  process.exitCode = 1
}
