_           = require 'underscore'
Handlebars  = require 'handlebars'
yaml        = require 'js-yaml'
topsort     = require 'topsort'
path        = require 'path'
fs          = require 'fs'

template = Handlebars.compile("#{fs.readFileSync path.join(__dirname,'../templates/bash.hbs')}")

Handlebars.registerHelper 'dockervolumes', (rootPath, ctx) ->
  @volumes?.reduce (prev, volume) =>
    "#{prev}-v #{rootPath}/#{ctx.project}/#{ctx.instance}#{@service}#{volume}:#{volume} "
  , ""

getNameAndVersion = (doc) -> [doc.name, doc.version]
notNameAndVersion = (service) -> service != 'name' and service != 'version'

dockerLinks = (ctx, doc) ->
  doc.links?.reduce (prev, link) ->
    "#{prev}--link #{link}-#{ctx.project}-#{ctx.instance}:#{link} "
  , ""
volumesFrom = (ctx, doc) ->
  doc['volumes-from']?.reduce (prev, volume) ->
    "#{prev}--volumes-from #{volume}-#{ctx.project}-#{ctx.instance} "
  , ""

toTopsortArray = (doc) ->
  arr = []
  for service in Object.keys doc when notNameAndVersion service
    for x in _.without(_.union(doc[service].links, doc[service]['volumes-from']), undefined)
      arr.push [service, x]
  arr

process = (doc, project, instance) ->
  [appName, appVersion] = getNameAndVersion doc
  ctx =
    appName: appName
    appVersion: appVersion
    project: project
    instance: instance
    services: []

  for service in topsort(toTopsortArray doc).reverse()
    doc[service].service = service
    doc[service].linkage = dockerLinks ctx, doc[service]
    doc[service].volumesfrom = volumesFrom ctx, doc[service]
    ctx.services.push doc[service]

  template ctx

generate = (yaml_text, project, instance) ->
  try
    process yaml.safeLoad(yaml_text), project, instance
  catch e
    console.log e

exports.generate = generate

#generate (fs.readFileSync path.join(__dirname, '../defs/libreboard.yaml')), 'innovation', 'libre1'
