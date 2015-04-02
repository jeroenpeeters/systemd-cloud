Promise   = require 'bluebird'
connect   = require 'ssh2-connect'
fs        = require 'ssh2-fs'

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


module.exports = sshmod = (opts, errCallback) ->
  x = _connect(opts)

  sshProm: x
  lastprom: x

  $: (cb) -> @lastprom = @lastprom.then(cb).catch @catcher; @;
  sshConn: (cb) -> =>@sshProm.then cb

  catcher: (err)->
    if errCallback
      errCallback err
    else
      console.warn "No error callback provided", err

  cmd: (cmd) ->
    @$ @sshConn _exec cmd

  mkdir: (dir) ->
    @cmd "mkdir #{dir}"

  writeFile: (filename, data) ->
    @$ @sshConn _writeFile filename, data

  execute: (filename) ->
    @$ @sshConn _exec "chmod +x #{filename} && #{filename} > #{filename}.log"

  value: (cb) ->
    @$ cb

  end: ->
    @$ @sshConn (ssh)-> ssh.end()

ssh = sshmod
  host: '10.19.88.21'
  username: 'core'
  privateKeyPath: '~/.ssh/docker-cluster/id_rsa'
  ,(err)-> console.log 'wooj', err

#ssh.mkdir('./test').writeFile('./test/file1', 'echo hoi2').execute('./test/file1').value(console.log)
#ssh.end()
