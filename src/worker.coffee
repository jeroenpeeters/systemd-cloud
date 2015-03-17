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
      @work().insert({arbiter: workerId, state: 'auctioning', itemOfWork: itemOfWork, bids: []})
        .then (stat)-> cb stat.generated_keys[0] if cb

    updateWork: (value) ->
      @work().update(value).run()

    newBid: (bid, arbiter, workId, workerId) ->
      @bids().insert({bid: bid, arbiter: arbiter, workId: workId, workerId: workerId}).run()

    listenForNewWork: (cb) ->
      @work().changes()
        .filter @newval('state').eq('auctioning')
        #.filter (work) -> work('new_val')('bids').contains((bid) -> bid('workerId').eq(workerId)).not()
        .then (cursor) -> cursor.each (_, value) -> cb value.new_val
        .error console.log

    listenForBids: (workerId, cb) ->
      @bids().changes().filter @newval('arbiter').eq(workerId)
        .then (cursor) -> cursor.each (_, value) -> cb value.new_val
        .error console.log


  db.listenForNewWork (value) ->
    console.log 'new work:', value
    db.newBid x, value.arbiter, value.id, workerId
    #value.bids.push {workerId: workerId, bid: x}
    #db.updateWork value

  myWork = {}
  db.listenForBids workerId, (bid) ->
    console.log "bid on work #{bid.workId}", bid
    myWork[bid.workId] = new sets.Set() if not myWork[bid.workId]
    myWork[bid.workId].add bid
    if myWork[bid.workId].size() == workerSet.size()
      winningBid = selectWinningBid auction.bids
      console.log "all bids received for #{auction.id}, winner is #{winningBid.worker}"
      redis.pub.rpush "auction/#{auction.id}/winner", winningBid.worker
      redis.publishObject 'execute', {targetWorker: winningBid.worker, itemOfWork: auction.itemOfWork}
      delete myAuctions[auction.id]

  x = 100

  workerSet = new sets.Set([workerId])
  myAuctions = {}

  selectWinningBid = (bids) ->
    bids.array().reduce (prev, current) -> if prev == null || current.bid > prev.bid then current else prev

  handlers =
    'worker-left': (msg) ->
      console.log "Worker left: #{msg.id}"
      workerSet.remove msg.id
    'presence-announcement': (msg) ->
      anounceMyPresence() if not workerSet.has msg.id
      prevSize = workerSet.size()
      workerSet.add msg.id
      console.log "Total workers: #{workerSet.size()}" if prevSize != workerSet.size()

    'auction': (msg) ->
      console.log 'auction received:', msg
      x = 100 if x < 1
      setTimeout ->
        redis.publishObject 'bid', {auctionId: msg.id, worker: workerId, bid: x}
      , 1000

    'bid': (bid) ->
      if myAuctions[bid.auctionId]
        auction = myAuctions[bid.auctionId]
        auction.bids.add bid
        if auction.bids.size() == workerSet.size()
          winningBid = selectWinningBid auction.bids
          console.log "all bids received for #{auction.id}, winner is #{winningBid.worker}"
          redis.pub.rpush "auction/#{auction.id}/winner", winningBid.worker
          redis.publishObject 'execute', {targetWorker: winningBid.worker, itemOfWork: auction.itemOfWork}
          delete myAuctions[auction.id]

    'execute': (job) ->
      if job.targetWorker == workerId
        x -= 1
        stateKey = "/instance/#{job.itemOfWork.id}"
        redis.mergeObject stateKey, {state: 'loading', workerId: workerId}
        console.log 'Job received', job
        child_process.exec "#{execRunner} \"#{job.itemOfWork.work.cmd}\"", (err, stdout, stderr) ->
          console.log 'work done: ', err, stdout, stderr
          redis.mergeObject stateKey, {state: 'running'}

    'stop': (job) ->
      if job.workerId == workerId
        redis.mergeObject "/instance/#{job.itemOfWork.id}", {state: 'stopping'}
        console.log "stop -> #{execRunner} \"cd #{job.itemOfWork.project}-#{job.itemOfWork.instance} && ./stop.sh\""
        child_process.exec "#{execRunner} \"cd #{job.itemOfWork.project}-#{job.itemOfWork.instance} && ./stop.sh\"", (err, stdout, stderr) ->
          redis.del "/instance/#{job.itemOfWork.id}"

  onExit = (_ , exception)->
    console.log 'uncaughtException', exception if exception
    db.unregisterNode workerApi, ->
      process.exit()

  process.on 'SIGINT', onExit.bind null, exit:true
  process.on 'uncaughtException', onExit.bind null, exit:true

  createItemOfWork = (project, instance, work) ->
    id: "#{project}/#{instance}", project: project, instance: instance, work: work

  newWork = (itemOfWork, cb) ->
    db.nodeCount (nodeCount) ->
      db.newWork extend {expectedBids: nodeCount}, itemOfWork
      cb "wooi"
    ###
    stateKey = "/instance/#{itemOfWork.id}"
    redis.exists stateKey, (err, exists) ->
      if !err and exists == 0
        auction = id: uuid.v4()
        redis.setObject stateKey, {'state': 'auctioning', itemOfWork: itemOfWork}
        myAuctions[auction.id] = extend {itemOfWork: itemOfWork, bids:new sets.Set()}, auction
        redis.publishObject 'auction', auction
        redis.waitFor "auction/#{auction.id}/winner", (err, value) ->
          cb null, auction, value[1]
      else
        cb "Instance already exists"
    ###

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

  app.get '/app-state/:project/:instance', (req, res) ->
    redis.getObject "/instance/#{req.params.project}/#{req.params.instance}", (err, state)->
      res.json {error: err} if err
      res.json {error: "No such instance"} if !err and state is null
      res.json state if state

  app.get '/start-app/:project/:instance', (req, res) ->
    itemOfWork = createItemOfWork req.params.project, req.params.instance, cmd: 'echo hello;sleep 10;echo world;'
    newWork itemOfWork, (err, auction, winnerId) ->
      res.json error: err if err
      if !err
        res.json auctionId: auction.id, winnerId: winnerId, endpoints:
          state: "http://#{workerId}/app-state/#{req.params.project}/#{req.params.instance}"
          stop: "http://#{workerId}/stop-app/#{req.params.project}/#{req.params.instance}"

  app.post '/start-app/:project/:instance', (req, res) ->
    itemOfWork = createItemOfWork req.params.project, req.params.instance, cmd: req.body
    newWork itemOfWork, (err, auction, winnerId) ->
      res.json error: err if err
      res.json {auctionId: auction.id, winnerId: winnerId} if !err

  app.get '/stop-app/:project/:instance', (req, res) ->
    redis.getObject "/instance/#{req.params.project}/#{req.params.instance}", (err, state)->
      res.json {error: err} if err
      res.json {error: "No such instance"} if !err and state is null
      res.json {error: "Instance cannot be stopped at current state"} if state && (!state.workerId || state.state != 'running')
      if state && state.state == 'running'
        redis.publishObject 'stop', state
        res.json {ok:'ok'}

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

  app.get '/worker-info', (req, res) ->
    res.json
      workerId: workerId
      redisHost: "#{redisHost}:#{redisPort}"
      execRunner: execRunner
      clusterNodes: workerSet.array()

  server = app.listen http_port, ->
    host = server.address().address
    port = server.address().port
    console.log 'API listening at http://%s:%s', host, port
