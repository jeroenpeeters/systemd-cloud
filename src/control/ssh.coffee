connect = require 'ssh2-connect'
fs = require 'ssh2-fs'

# https://github.com/wdavidw/node-ssh2-connect
opts =
  host: '10.19.88.57'
  #port: 22
  username: 'core'
  #password: 'geheim'
  privateKeyPath: '~/.ssh/docker-cluster/id_rsa'

module.exports = ->

  connect opts, (err, ssh)->
    #fs.readdir ssh, 'uploads', (err, files) ->
    #  console.log err, files
    #fs.readFile ssh, 'uploads/test.txt', (err, data) ->
    #  console.log err, data
    console.log err
    fs.writeFile ssh, 'writtenByNode.txt', 'Im a file', (err) ->
      console.log 'written'   if !err
      console.log err         if err
      ssh.exec "ls -al | grep writtenBy", (err, stream) ->
        console.log 'exec', err
        buff = ""
        stream.on 'data', (chunk) ->
          buff += chunk
        stream.on 'end', ->
          console.log 'recv', buff
          ssh.end()

module.exports()
