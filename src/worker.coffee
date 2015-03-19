sys           = require 'sys'
child_process = require 'child_process'
sets          = require 'simplesets'
request       = require 'request'

dbImpl        = require './db'
httpImpl      = require './http'
opsImpl       = require './operations'
roundRobin    = require './bidding/round-robin'

module.exports = (http_port, redisHost, redisPort, workerApi, execRunner) ->

  workerId = workerApi
  config =
    workerId: workerId
    execRunner: execRunner
  bidder = roundRobin()

  db = dbImpl redisHost, redisPort, workerApi
  ops = opsImpl db, bidder, config
  http = httpImpl http_port, config, ops

  myWork = {}

  db.listenForNewWork (value) ->
    bidder.bidOn value, (bid) ->
      console.log 'bidding ->', bid
      db.newBid bid, value.auction.arbiter, value.id, workerId

  db.listenForBids workerId, (bid) ->
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

  selectWinningBid = (bids) ->
    bids.array().reduce (prev, current) -> if prev == null || current.bid > prev.bid then current else prev

  onExit = (_, exception) ->
    console.log 'uncaughtException', exception if exception
    db.unregisterNode workerApi, ->
      process.exit()

  process.on 'SIGINT', onExit.bind null, exit:true
  process.on 'uncaughtException', onExit.bind null, exit:true

  db.registerNode workerApi

  console.log "Simple CloudEngine v1.0 by @jeroenpeeters"
  console.log "Worker started", config
