#sys           = require 'sys'
#child_process = require 'child_process'
request       = require 'request'
ssh           = require './control/ssh'
scriptgen     = require './script-generator'


module.exports = (db, bidder, config) ->

  workerId    = config.workerId
  execRunner  = config.execRunner

  changeWorkState = (itemOfWork, newState) ->
    db.changeWorkState itemOfWork.id, newState

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
        db.newWork itemOfWork
        cb null, "wooi"

  stop: (project, instance, cb) ->
    @status project, instance, (err, result) =>
      cb err                      if err
      cb null, null               if result == null
      @stopInstance result, cb    if result != null

  startInstance: (work, cb) ->
    bidder.notifyAboutWork work
    changeWorkState work, 'starting'
    script = scriptgen.generate work.itemOfWork.work.appdef, work.itemOfWork.project, work.itemOfWork.instance
    ssh.executeScript script, work.itemOfWork.project, work.itemOfWork.instance
    ###
    child_process.exec "#{config.execRunner} echo \"#{script}\" > #{work.itemOfWork.project}_#{work.itemOfWork.instance}.sh", (err, stdout, stderr) ->
      console.log 'work done: ', err, stdout, stderr
      work.state = 'running'
      db.updateWork work
    ###

  stopInstance: (instance, cb) ->
    if instance.state == 'running'
      if instance.auction.winningBid.workerId == workerId
        changeWorkState instance, 'stopping'
        child_process.exec "#{execRunner} \"cd #{instance.itemOfWork.project}-#{instance.itemOfWork.instance} && ./stop.sh\"", (err, stdout, stderr) ->
          db.removeWork instance.id
        cb null, ok: 'true'
      else
        cb null, forward: request.get("http://#{instance.auction.winningBid.workerId}/stop-app/#{instance.itemOfWork.project}/#{instance.itemOfWork.instance}")
    else
      cb error: "Instance cannot be stopped at current state"
