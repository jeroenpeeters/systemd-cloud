worker = require './src/worker.coffee'

worker
  ssh: #see https://github.com/wdavidw/node-ssh2-connect
    host: '10.19.88.21'
    username: 'core'
    privateKeyPath: '~/.ssh/docker-cluster/id_rsa'
  rethinkdb:
    host: '10.19.88.56'
    port: 28015
  http:
    port: 8181
    public: '0.0.0.0:8181'
  network:
    if: 'ens160'
