
module.exports = () ->

  bid: 1000

  bidOn: (work, cb) ->
    setTimeout (=> cb @bid), 5000

  notifyAboutWork: (work) ->
    @bid -= 1   if @bid != 0
    @bid = 1000 if @bid == 0
