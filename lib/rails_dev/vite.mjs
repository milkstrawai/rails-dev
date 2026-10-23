import { writeFileSync } from 'node:fs'
import { join } from 'node:path'

export default function railsDev() {
  const runtime = process.env.RAILS_DEV_RUNTIME
  const origin = new URL(process.env.RAILS_DEV_VITE_URL)

  return {
    rails: { devMetaFile: join(runtime, 'rails-vite.json') },
    plugin: {
      name: 'rails-dev',
      apply: 'serve',
      config: () => ({
        cacheDir: join(runtime, 'vite-cache'),
        define: {
          'import.meta.env.VITE_RAILS_DEV_COOKIE_PREFIX': JSON.stringify(`rails-dev-${process.env.RAILS_PORT}-`),
        },
        server: {
          host: '127.0.0.1',
          origin: origin.origin,
          allowedHosts: [origin.hostname],
          cors: { origin: process.env.RAILS_DEV_URL },
          ws: {
            protocol: origin.protocol === 'https:' ? 'wss' : 'ws',
            host: origin.hostname,
            clientPort: Number(origin.port || (origin.protocol === 'https:' ? 443 : 80)),
          },
        },
      }),
      configureServer: (server) => {
        server.httpServer?.once('listening', () => {
          writeFileSync(join(runtime, 'vite-loopback-url'), `http://127.0.0.1:${server.httpServer.address().port}`)
        })
      },
    },
  }
}
