worker = require './src/worker.coffee'

worker '8383', 'docker1.rni.org', 6379,  "0.0.0.0:8383",  "ssh core@10.19.88.16  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
