rethinkdbdash = require 'rethinkdbdash'

module.exports = (host, port, workerId) ->

  r:        rethinkdbdash {host: host, port: port, db: 'appcluster'}
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
      .then (stat)=> @work().get(stat.generated_keys[0]).run cb if cb

  removeWork: (id) ->
    @work().get(id).delete().run()

  findWork: (id, cb) ->
    @work().get(id).then cb

  findWorkByName: (project, instance, cb) ->
    @work().filter(itemOfWork: {project: project, instance: instance}).run cb

  updateWork: (value) ->
    @work().update(value).run()

  changeWorkState: (id, newState) ->
    @work().get(id).update(state: newState).run()

  newBid: (bid, arbiter, workId, workerId) ->
    @bids().insert({bid: bid, arbiter: arbiter, workId: workId, workerId: workerId}).run()

  deleteBidsForWork: (workId) ->
    @bids().filter(workId: workId).delete().run()

  listenForNewWork: (cb) ->
    @work().changes()
      .filter @r.row('old_val').eq(null)
      .filter @newval('state').eq('auctioning')
      .then (cursor) -> cursor.each (_, value) -> cb value.new_val
      .error console.log

  listenForBids: (workerId, cb) ->
    @bids().changes().filter @r.row('old_val').eq(null)
      .filter @newval('arbiter').eq(workerId)
      .then (cursor) -> cursor.each (_, value) -> cb value.new_val
      .error console.log
