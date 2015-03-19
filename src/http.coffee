sys           = require 'sys'
child_process = require 'child_process'
express       = require 'express'
bodyParser    = require 'body-parser'

module.exports = (http_port, config, ops) ->

  app = express()
  app.use bodyParser.urlencoded extended: false
  app.use bodyParser.text()
  app.use bodyParser.json()

  getEndpointsObject = (project, instance) ->
    state: "http://#{config.workerId}/app-state/#{project}/#{instance}"
    stop: "http://#{config.workerId}/stop-app/#{project}/#{instance}"

  noSuchInstance = (req, res) ->
    res.status(404).json error: "No such instance"

  startApp = (req, res, itemOfWork) ->
    ops.submit itemOfWork, (err, work) ->
      if err
        res.status(400).json error: err, endpoints:
          getEndpointsObject req.params.project, req.params.instance
      else
        res.json work

  app.get '/app-state/:project/:instance', (req, res) ->
    ops.status req.params.project, req.params.instance, (err, result) ->
      res.status(500).json err      if err
      noSuchInstance req, res       if !err and result == null
      res.json result               if !err and result

  app.get '/start-app/:project/:instance', (req, res) ->
    startApp req, res, ops.createItemOfWork req.params.project,
      req.params.instance, cmd: 'echo hello;sleep 10;echo world;'

  app.post '/start-app/:project/:instance', (req, res) ->
    startApp req, res, ops.createItemOfWork req.params.project,
      req.params.instance, cmd: req.body

  app.get '/stop-app/:project/:instance', (req, res) ->
    ops.stop req.params.project, req.params.instance, (err, result) ->
      if err
        res.status(400).json err
      else if result == null
        noSuchInstance req, res
      else if result.forward
        result.forward.pipe res
      else
        res.json result

  app.get '/app-file/:project/:instance/:service', (req, res) ->
    console.log req.params.project, req.params.instance, req.query.path
    redis.getObject "/instance/#{req.params.project}/#{req.params.instance}", (err, state)->
      res.json {error: err} if err
      res.json {error: "No such instance"} if !err and state is null
      if state and state.workerId == config.workerId
        child_process.exec "#{config.execRunner} \"docker exec #{req.params.service}-#{req.params.project}-#{req.params.instance} cat #{req.query.path}\"", (err, stdout, stderr) ->
          res.send stderr if err
          res.send stdout if !err
      if state and state.workerId != config.workerId
        request.get("http://#{state.workerId}/app-file/#{req.params.project}/#{req.params.instance}/#{req.params.service}?path=#{req.query.path}")
        .pipe(res)

  app.get '/worker/info', (req, res) -> res.json config

  app.post '/worker/execute', (req, res) ->
    work = req.body
    ops.startInstance work
    res.writeHead 202
    res.end()

  server = app.listen http_port, ->
    host = server.address().address
    port = server.address().port
    console.log 'API listening at http://%s:%s', host, port
