sys           = require 'sys'
child_process = require 'child_process'
redis_        = require 'redis'
sets          = require 'simplesets'
uuid          = require 'node-uuid'
extend        = require 'extend'
express       = require 'express'
bodyParser    = require 'body-parser'
request       = require 'request'

repubsub      = require './repubsub'
r = require('rethinkdbdash')(host:'10.19.88.15', port: 28015, db: 'appcluster')
exchange = new repubsub.Exchange 'clusterExchange', {host:'10.19.88.15', port: 28015, db: 'pubsub'}

auctionQueue = exchange.queue (topic) -> topic.match 'auction'
auctionQueue.subscribe (topic, message) ->
  console.log 'recv:', topic, message, message.object

auctionTopic = exchange.topic 'auction'
auctionTopic.publish {object: "an object", x:1}

#r.connect host:'10.19.88.14', port: 28015, db: 'appcluster'
#r.table('data').run().then (result)->
#  console.log 'rethinkdb result!!!', result

_randomNum = (max,min=0) -> Math.floor(Math.random() * (max - min) + min)

module.exports = (http_port, redisHost, redisPort, workerApi, execRunner) ->

  workerId = workerApi

  redis =
    sub: redis_.createClient redisPort, redisHost
    pub: redis_.createClient redisPort, redisHost
    props: redis_.createClient redisPort, redisHost
    publishObject: (channel, object) -> @pub.publish channel, JSON.stringify object
    subscribe: (channel) -> @sub.subscribe channel
    onMessage: (cb) -> @sub.on 'message', cb
    getObject: (prop, cb) -> @props.get prop, (err, value) -> if err then cb err else cb null, JSON.parse value
    setObject: (prop, object) -> @props.set prop, JSON.stringify object
    mergeObject: (prop, object) -> @getObject prop, (err, value) =>
      @setObject prop, extend value, object if value
    exists: (prop, cb) -> @props.exists prop, cb
    del: (prop) -> @props.del prop
    waitFor: (key, cb) ->
      wait = redis_.createClient redisPort, redisHost
      wait.brpop key, 0, (err, value) ->
        wait.end()
        cb err, value

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


  redis.onMessage (channel, message) ->
    if handlers[channel]
      handlers[channel] JSON.parse message
    else console.log "Unknown channel #{channel} with message", message

  onExit = (_ , exception)->
    console.log 'uncaughtException', exception if exception
    redis.publishObject 'worker-left', id:workerId
    process.exit()

  process.on 'SIGINT', onExit.bind null, exit:true
  #process.on 'uncaughtException', onExit.bind null, exit:true

  createItemOfWork = (project, instance, work) ->
    id: "#{project}/#{instance}", project: project, instance: instance, work: work

  newAuction = (itemOfWork, cb) ->
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

  anounceMyPresence = -> redis.publishObject 'presence-announcement', id:workerId

  #
  # Start the worker
  #

  redis.subscribe 'auction'
  redis.subscribe 'worker-left'
  redis.subscribe 'bid'
  redis.subscribe 'presence-announcement'
  redis.subscribe 'execute'
  redis.subscribe 'stop'

  anounceMyPresence()
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
    newAuction itemOfWork, (err, auction, winnerId) ->
      res.json error: err if err
      if !err
        res.json auctionId: auction.id, winnerId: winnerId, endpoints:
          state: "http://#{workerId}/app-state/#{req.params.project}/#{req.params.instance}"
          stop: "http://#{workerId}/stop-app/#{req.params.project}/#{req.params.instance}"

  app.post '/start-app/:project/:instance', (req, res) ->
    itemOfWork = createItemOfWork req.params.project, req.params.instance, cmd: req.body
    newAuction itemOfWork, (err, auction, winnerId) ->
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
