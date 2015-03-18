sys           = require 'sys'
child_process = require 'child_process'
sets          = require 'simplesets'
request       = require 'request'
dbImpl        = require './db'
httpImpl      = require './http'

module.exports = (http_port, redisHost, redisPort, workerApi, execRunner) ->

  workerId = workerApi
  db = dbImpl redisHost, redisPort, workerApi
  http = httpImpl http_port, db, workerId

  myWork = {}

  db.listenForNewWork (value) ->
    console.log 'new work:', value
    db.newBid x, value.auction.arbiter, value.id, workerId

  db.listenForBids workerId, (bid) ->
    console.log "bid on work #{bid.workId}", bid
    myWork[bid.workId] = new sets.Set() if not myWork[bid.workId]
    myWork[bid.workId].add bid
    db.findWork bid.workId, (work) ->
      if myWork[bid.workId] and myWork[work.id].size() == work.auction.expectedBids
        winningBid = selectWinningBid myWork[bid.workId]
        console.log "winningbid for work #{winningBid.workId}", winningBid
        work.auction.bids = myWork[bid.workId].array()
        work.auction.winningBid = winningBid
        db.updateWork work
        request.post "http://#{winningBid.workerId}/worker/execute", {json: true, body: work}

        delete myWork[bid.workId]
        db.deleteBidsForWork bid.workId

  x = 100

  selectWinningBid = (bids) ->
    bids.array().reduce (prev, current) -> if prev == null || current.bid > prev.bid then current else prev

  onExit = (_, exception) ->
    console.log 'uncaughtException', exception if exception
    db.unregisterNode workerApi, ->
      process.exit()

  process.on 'SIGINT', onExit.bind null, exit:true
  process.on 'uncaughtException', onExit.bind null, exit:true

  createItemOfWork = (project, instance, work) ->
    project: project, instance: instance, work: work

  newWork = (itemOfWork, cb) ->
    db.findWorkByName itemOfWork.project, itemOfWork.instance, (res) ->
      if res.length > 0
        cb "Instance already exists"
      else
        db.newWork itemOfWork
        cb null, "wooi"

  db.registerNode workerApi
  console.log "Simple CloudEngine v1.0 by @jeroenpeeters"
  console.log "Worker started, redisHost=#{redisHost}, redisPort=#{redisPort}, httpPort=#{http_port}, workerId=#{workerId}"
  console.log "ExecRunner:#{execRunner}"
