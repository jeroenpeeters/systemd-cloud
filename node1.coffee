worker = require './src/worker.coffee'

worker '8181', 'docker1.rni.org', 6379, "0.0.0.0:8181", "ssh core@10.19.88.14", "10.19.88.14"
