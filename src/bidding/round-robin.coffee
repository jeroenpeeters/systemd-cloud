
module.exports = () ->

  bid: 100

  bidOn: (work, cb) ->
    setTimeout => cb @bid
    , 1000

  notifyAboutWork: (work) ->
    @bid -= 1
