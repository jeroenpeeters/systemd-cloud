worker = require './src/worker.coffee'

worker '8282', '10.19.88.57', 28015, "0.0.0.0:8282", "ssh core@10.19.88.57  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
