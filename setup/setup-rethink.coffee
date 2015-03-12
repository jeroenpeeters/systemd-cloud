r = require('rethinkdbdash') host:'10.19.88.14', port: 28015, db: 'appcluster'

handleErr = (msg) -> (err) -> console.log msg, err

r.dbCreate('appcluster').then (result) ->
  console.log "Database created", result
.error handleErr "Unable to create database"
.then -> r.tableCreate 'data'
.error handleErr "Unable to create table 'data'"
.then -> r.getPool().drain()
