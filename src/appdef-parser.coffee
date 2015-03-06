yaml = require 'js-yaml'
path = require 'path'
fs   = require 'fs'

try
  doc = yaml.safeLoad fs.readFileSync(path.join(__dirname,'../test.yml'), 'utf8')
  console.log doc
catch e
  console.log e
