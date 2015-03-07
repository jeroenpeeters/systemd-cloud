Handlebars  = require 'handlebars'
yaml        = require 'js-yaml'
path        = require 'path'
fs          = require 'fs'

template = Handlebars.compile("#{fs.readFileSync path.join(__dirname,'../systemd-service.hbs')}")

getNameAndVersion = (doc) -> [doc.name, doc.version]
notNameAndVersion = (service) -> service != 'name' and service != 'version'

dockerLinks = (doc) ->
  doc.links?.reduce (prev, link) ->
    "#{prev}--link #{link}-#{doc.project}-#{doc.instance}:#{link}"
  , ""
volumesFrom = (doc) ->
  doc['volumes-from']?.reduce (prev, volume) ->
    "#{prev}--volumes-from #{volume}-#{doc.project}-#{doc.instance}"
  , ""

process = (doc, project, instance) ->
  [appName, appVersion] = getNameAndVersion doc
  for service in Object.keys doc when notNameAndVersion service
    doc[service].appName = appName
    doc[service].appVersion = appVersion
    doc[service].project = project
    doc[service].instance = instance
    doc[service].name = service
    doc[service].linkage = dockerLinks doc[service]
    doc[service].volumesfrom = volumesFrom doc[service]
    console.log template doc[service]

generate = (yaml_text, project, instance) ->
  try
    process yaml.safeLoad(yaml_text), project, instance
  catch e
    console.log e

generate (fs.readFileSync path.join(__dirname, '../test.yaml')), 'projectName', 'instanceName'
