import { createServer } from 'node:http'
import railsDev from '../../lib/rails_dev/vite.mjs'

const httpServer = createServer()
railsDev().plugin.configureServer({ httpServer })
httpServer.listen(0, '127.0.0.1', () => {
  console.log(httpServer.address().port)
  httpServer.close()
})
