express       = require 'express'
bodyParser    = require 'body-parser'

module.exports = (http_port, db, workerId) ->

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
