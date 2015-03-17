worker = require './src/worker.coffee'

worker '8181', '10.19.88.14', 28015, "0.0.0.0:8181", "ssh core@10.19.88.14 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
