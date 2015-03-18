sys           = require 'sys'
child_process = require 'child_process'
sets          = require 'simplesets'
express       = require 'express'
bodyParser    = require 'body-parser'
request       = require 'request'
dbImpl        = require './db'

module.exports = (http_port, redisHost, redisPort, workerApi, execRunner) ->

  workerId = workerApi
  db = dbImpl redisHost, redisPort, workerApi

  db.listenForNewWork (value) ->
    console.log 'new work:', value
    db.newBid x, value.auction.arbiter, value.id, workerId

  myWork = {}
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

  workerSet = new sets.Set([workerId])
  myAuctions = {}

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

  #
  # WebEndpoints
  #

  app = express()
  app.use bodyParser.urlencoded extended: false
  app.use bodyParser.text()
  app.use bodyParser.json()

  getEndpointsObject = (project, instance) ->
    state: "http://#{workerId}/app-state/#{project}/#{instance}"
    stop: "http://#{workerId}/stop-app/#{project}/#{instance}"

  noSuchInstance = (req, res) ->
    res.status(404).json error: "No such instance"

  app.get '/app-state/:project/:instance', (req, res) ->
    db.findWorkByName req.params.project, req.params.instance, (result) ->
      if result.length == 0
        noSuchInstance req, res
      else
        res.json result[0]

  app.get '/start-app/:project/:instance', (req, res) ->
    itemOfWork = createItemOfWork req.params.project, req.params.instance, cmd: 'echo hello;sleep 10;echo world;'
    newWork itemOfWork, (err, auction, winnerId) ->
      if err
        res.status(400).json error: err, endpoints:
          getEndpointsObject req.params.project, req.params.instance
      else
        res.json auctionId: auction.id, winnerId: winnerId, endpoints:
          getEndpointsObject req.params.project, req.params.instance

  app.post '/start-app/:project/:instance', (req, res) ->
    itemOfWork = createItemOfWork req.params.project, req.params.instance, cmd: req.body
    newWork itemOfWork, (err, auction, winnerId) ->
      res.json error: err if err
      res.json {auctionId: auction.id, winnerId: winnerId} if !err

  app.get '/stop-app/:project/:instance', (req, res) ->
    db.findWorkByName req.params.project, req.params.instance, (result) ->
      if result.length == 0
        noSuchInstance req, res
      else
        instance = result[0]
        if instance.state == 'running'
          if instance.auction.winningBid.workerId == workerId
            console.log "stop -> #{execRunner} \"cd #{instance.itemOfWork.project}-#{instance.itemOfWork.instance} && ./stop.sh\""
            child_process.exec "#{execRunner} \"cd #{instance.itemOfWork.project}-#{instance.itemOfWork.instance} && ./stop.sh\"", (err, stdout, stderr) ->
              db.removeWork instance.id
            res.json ok: 'true'
          else
            request.get("http://#{instance.auction.winningBid.workerId}/stop-app/#{req.params.project}/#{req.params.instance}")
            .pipe(res)
        else
          res.status(400).json error: "Instance cannot be stopped at current state"

  app.get '/app-file/:project/:instance/:service', (req, res) ->
    console.log req.params.project, req.params.instance, req.query.path
    redis.getObject "/instance/#{req.params.project}/#{req.params.instance}", (err, state)->
      res.json {error: err} if err
      res.json {error: "No such instance"} if !err and state is null
      if state and state.workerId == workerId
        child_process.exec "#{execRunner} \"docker exec #{req.params.service}-#{req.params.project}-#{req.params.instance} cat #{req.query.path}\"", (err, stdout, stderr) ->
          res.send stderr if err
          res.send stdout if !err
      if state and state.workerId != workerId
        request.get("http://#{state.workerId}/app-file/#{req.params.project}/#{req.params.instance}/#{req.params.service}?path=#{req.query.path}")
        .pipe(res)

  app.get '/worker/info', (req, res) ->
    res.json
      workerId: workerId
      execRunner: execRunner
      rethinkdb:
        host: redisHost
        port: redisPort

  app.post '/worker/execute', (req, res) ->
    work = req.body
    console.log 'Execute work:', work
    x -= 1
    child_process.exec "#{execRunner} \"#{work.itemOfWork.work.cmd}\"", (err, stdout, stderr) ->
      console.log 'work done: ', err, stdout, stderr
      work.state = 'running'
      db.updateWork work
    res.writeHead 202
    res.end()

  server = app.listen http_port, ->
    host = server.address().address
    port = server.address().port
    console.log 'API listening at http://%s:%s', host, port
