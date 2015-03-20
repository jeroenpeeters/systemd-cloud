r = require('rethinkdbdash') host:'10.19.88.57', port: 28015, db: 'appcluster'

handleErr = (msg) -> (err) -> console.log msg, err

r.dbCreate('appcluster').then (result) ->
  console.log "Database created", result
.error handleErr "Unable to create database"

.then -> r.tableCreate 'work'
.error handleErr "Unable to create table 'work'"

.then -> r.tableCreate 'nodes'
.error handleErr "Unable to create table 'nodes'"

.then -> r.tableCreate 'bids'
.error handleErr "Unable to create table 'bids'"

.then -> r.getPool().drain()
