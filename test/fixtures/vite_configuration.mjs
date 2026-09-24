import railsDev from '../../lib/rails_dev/vite.mjs'

const { plugin, rails } = railsDev()
console.log(JSON.stringify({ rails, ...plugin, config: plugin.config() }))
