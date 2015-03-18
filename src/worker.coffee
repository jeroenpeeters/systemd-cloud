sys           = require 'sys'
child_process = require 'child_process'
redis_        = require 'redis'
sets          = require 'simplesets'
uuid          = require 'node-uuid'
extend        = require 'extend'
express       = require 'express'
bodyParser    = require 'body-parser'
request       = require 'request'
rethinkdbdash = require 'rethinkdbdash'

#r.connect host:'10.19.88.14', port: 28015, db: 'appcluster'
#r.table('data').run().then (result)->
#  console.log 'rethinkdb result!!!', result

_randomNum = (max,min=0) -> Math.floor(Math.random() * (max - min) + min)

module.exports = (http_port, redisHost, redisPort, workerApi, execRunner) ->

  workerId = workerApi

  db =
    r:        rethinkdbdash {host: redisHost, port: redisPort, db: 'appcluster'}
    newval:   (key) -> @r.row('new_val') key
    oldval:   (key) -> @r.row('old_val') key
    nodes:    -> @r.table 'nodes'
    work:     -> @r.table 'work'
    bids:     -> @r.table 'bids'

    registerNode: (endpoint) ->
      @nodes().filter({endpoint: endpoint}).delete().then => @nodes().insert({endpoint: endpoint}).run()

    unregisterNode: (endpoint, cb) ->
      @nodes().filter({endpoint: endpoint}).delete().then -> cb() if cb

    nodeCount: (cb) ->
      @nodes().count().then cb

    newWork: (itemOfWork, cb) ->
      @nodeCount (nodeCount) =>
        @work().insert
          auction:
            arbiter: workerId
            expectedBids: nodeCount
            bids: []
          itemOfWork: itemOfWork
          state: 'auctioning'
        .then (stat)-> cb stat.generated_keys[0] if cb

    removeWork: (id) ->
      @work().get(id).delete().run()

    findWork: (id, cb) ->
      @work().get(id).then cb

    findWorkByName: (project, instance, cb) ->
      @work().filter(itemOfWork: {project: project, instance: instance}).then cb

    updateWork: (value) ->
      @work().update(value).run()

    newBid: (bid, arbiter, workId, workerId) ->
      @bids().insert({bid: bid, arbiter: arbiter, workId: workId, workerId: workerId}).run()

    deleteBidsForWork: (workId) ->
      @bids().filter(workId: workId).delete().run()

    listenForNewWork: (cb) ->
      @work().changes()
        .filter @r.row('old_val').eq(null)
        .filter @newval('state').eq('auctioning')
        #.filter (work) -> work('new_val')('bids').contains((bid) -> bid('workerId').eq(workerId)).not()
        .then (cursor) -> cursor.each (_, value) -> cb value.new_val
        .error console.log

    listenForBids: (workerId, cb) ->
      @bids().changes().filter @r.row('old_val').eq(null)
        .filter @newval('arbiter').eq(workerId)
        .then (cursor) -> cursor.each (_, value) -> cb value.new_val
        .error console.log


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
