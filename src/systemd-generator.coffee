Handlebars = require 'handlebars'
path = require 'path'
fs   = require 'fs'

template = Handlebars.compile path.join(__dirname,'../systemd-service.hbs')

console.log template {name: 'piet'}
