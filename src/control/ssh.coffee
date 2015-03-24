Promise   = require 'bluebird'
connect   = Promise.promisify require 'ssh2-connect'
fs        = require 'ssh2-fs'

# https://github.com/wdavidw/node-ssh2-connect
opts =
  host: '10.19.88.56'
  username: 'core'
  privateKeyPath: '~/.ssh/docker-cluster/id_rsa'

exec = (ssh, cmd, cb) ->
  ssh.exec cmd, (err, stream) ->
    if err
      cb err
    else
      buff = ""
      stream.on 'data', (chunk) -> buff += chunk
      stream.on 'err', (err) -> cb err
      stream.on 'end', -> cb null, buff

_writeFile = (filename, data) -> (ssh) -> return new Promise (resolve, reject) ->
  fs.writeFile ssh, filename, data, (err) -> if err then reject err else resolve()

module.exports =

  writeFile: (filename, data) -> new Promise (resolve, reject) ->
    console.log 'yo'
    connect(opts).then(-> console.log 'connected!').then(_writeFile filename, data).then resolve
    .catch reject

  executeScript: (script, project, instance) ->
    connect opts, (err, ssh)->
      fs.writeFile ssh, "#{project}_#{instance}.sh", script, (err) ->
        exec ssh, "chmod +x #{project}_#{instance}.sh && ./#{project}_#{instance}.sh", (err, res) ->
          console.log err, res
          ssh.end()

module.exports.writeFile('testfile1', 'imma test').then (a) -> console.log 'ok!', a
  .catch (e) -> console.log 'nok!', e
