worker = require './src/worker.coffee'

worker '8282', 'docker1.rni.org', 6379, "0.0.0.0:8282",  "ssh core@10.19.88.15", "10.19.88.15"
