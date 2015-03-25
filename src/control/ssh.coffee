Promise   = require 'bluebird'
connect   = require 'ssh2-connect'
fs        = require 'ssh2-fs'

# https://github.com/wdavidw/node-ssh2-connect
opts =
  host: '10.19.88.56'
  username: 'core'
  privateKeyPath: '~/.ssh/docker-cluster/id_rsa'

_exec = (cmd) -> (ssh) -> new Promise (resolve, reject) ->
  ssh.exec cmd, (err, stream) ->
    if err then reject err
    else
      buff = ""
      stream.on 'data', (chunk) -> buff += chunk
      stream.on 'err', (err) -> reject err
      stream.on 'end', -> resolve buff

_connect = (opts) -> new Promise (resolve, reject) ->
  connect opts, (err, ssh) -> if err then reject err else resolve ssh

_writeFile = (filename, data) -> (ssh) -> new Promise (resolve, reject) ->
  fs.writeFile ssh, filename, data, (err) -> if err then reject err else resolve()


module.exports = sshmod = () ->

  sshProm: _connect(opts)

  writeFile: (filename, data) ->
    @sshProm.then(_writeFile(filename, data))

  execute: (filename) ->
    @sshProm.then(_exec "chmod +x #{filename}\n./#{filename}")

  writeAndExecute: (filename, data) ->
    @writeFile(filename, data).then(=> @execute filename)
    .finally => @end()

  end: ->
    @sshProm.value()?.end()

ssh = sshmod()
ssh.writeAndExecute('testfile1', 'echo \'imma test123\'').then (val) -> console.log 'done!', val
