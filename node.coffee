worker = require './src/worker.coffee'

worker 80, process.env.REDIS_HOST, process.env.REDIS_PORT, process.env.EXEC_RUNNER, process.env.WORKER_HOST
