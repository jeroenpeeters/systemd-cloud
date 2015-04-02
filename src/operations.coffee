#sys           = require 'sys'
#child_process = require 'child_process'
request       = require 'request'
ssh           = require './control/ssh'
scriptgen     = require './script-generator'


module.exports = (db, bidder, config) ->

  workerId    = config.workerId
  #!!! >execRunner  = config.execRunner

  changeWorkState = (itemOfWork, newState) ->
    db.changeWorkState itemOfWork.id, newState

  testConnectivity: () ->
    ssh(config.ssh, ((err)-> console.log "SSH Connectivity Check: failed", err))
    .cmd('whoami').value((whoami) -> console.log "SSH Connectivity Check: whoami? #{whoami}").end()

  createItemOfWork: (project, instance, work) ->
    project: project, instance: instance, work: work

  status: (project, instance, cb) ->
    db.findWorkByName project, instance, (err, result) ->
      cb err              if err
      cb null, null       if !err and result.length == 0
      cb null, result[0]  if !err and result.length > 0

  submit: (itemOfWork, cb) ->
    db.findWorkByName itemOfWork.project, itemOfWork.instance, (err, result) ->
      if err
        cb err
      else if result.length > 0
        cb "Instance already exists"
      else
        db.newWork itemOfWork, cb

  stop: (project, instance, cb) ->
    @status project, instance, (err, result) =>
      cb err                      if err
      cb null, null               if result == null
      @stopInstance result, cb    if result != null

  startInstance: (work, cb) ->
    bidder.notifyAboutWork work
    changeWorkState work, 'pre-start'
    [startscript, stopscript] = scriptgen.generate config.network.if, work.itemOfWork.work.appdef, work.itemOfWork.project, work.itemOfWork.instance
    dir = "./#{work.itemOfWork.project}-#{work.itemOfWork.instance}"
    conn = ssh(config.ssh)
    conn.mkdir(dir).writeFile("#{dir}/start.sh", startscript).writeFile("#{dir}/stop.sh", stopscript)
    conn.value -> changeWorkState work, 'starting'
    conn.execute("#{dir}/start.sh")
    conn.end()
    conn.value -> changeWorkState work, 'running'

  stopInstance: (instance, cb) ->
    if instance.state == 'running'
      if instance.auction.winningBid.workerId == workerId
        changeWorkState instance, 'stopping'
        dir = "./#{instance.itemOfWork.project}-#{instance.itemOfWork.instance}"
        conn = ssh(config.ssh)
        conn.execute("#{dir}/stop.sh")
        conn.end()
        conn.value -> db.removeWork instance.id
        cb null, instance
      else
        cb null, forward: request.get("http://#{instance.auction.winningBid.workerId}/app/#{instance.itemOfWork.project}/#{instance.itemOfWork.instance}/stop")
    else
      cb error: "Instance cannot be stopped at current state"
