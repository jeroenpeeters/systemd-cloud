connect   = require 'ssh2-connect'
fs        = require 'ssh2-fs'

# https://github.com/wdavidw/node-ssh2-connect
opts =
  host: '10.19.88.21'
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


module.exports =

  executeScript: (script, project, instance) ->
    connect opts, (err, ssh)->
      fs.writeFile ssh, "#{project}_#{instance}.sh", script, (err) ->
        exec ssh, "chmod +x #{project}_#{instance}.sh && ./#{project}_#{instance}.sh", (err, res) ->
          console.log err, res
          ssh.end()
