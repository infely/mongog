#!/usr/bin/coffee

fs            = require('fs')
child_process = require('child_process')
program       = require('commander')
_             = require('lodash')
moment        = require('moment')
mongodb       = require('mongodb')
table         = require('table').table
chalk         = require('chalk')
sliceAnsi     = require('slice-ansi')
EJSON         = require('bson').EJSON
MongoClient   = mongodb.MongoClient
ObjectID      = mongodb.ObjectID

EDITOR = process.env['EDITOR'] || 'vi'

program
  .option('-h, --host <ip|domain>', 'host')
  .option('-p, --port <port>', 'port')
  .option('-s, --sort <string|object|order>', 'sort order')
  .option('-l, --limit <number>', 'limit rows')
  .option('-t, --truncate <number>', 'truncate strings')
  .option('-c, --create <string>', 'create collection')
  .option('-i, --insert', 'insert document')
  .option('-d, --delete', 'delete document')
args = program.parse(process.argv).args
HOST = program.host || 'localhost'
PORT = program.port || 27017
SORT = program.sort
LIMIT = parseInt(program.limit) || 10
TRUNCATE = parseInt(program.truncate) || 32
CREATE = program.create
INSERT = program.insert
DELETE = program.delete

makeCriteriaAndProjection = (r) ->
  projection = {}
  criteria = if r.match /^[0-9a-fA-F]{24}$/
    _id: new ObjectID r
  else if r.startsWith('{') && r.endsWith('}')
    try
      r = JSON.parse "[#{r}]".replace /(['"])?([a-z0-9A-Z_]+)(['"])?:/g, '"$2": '
      projection = r[1] if r[1]
      r[0]
    catch e
      {}
  else
    _.fromPairs _.filter _.map r.split(','), (i) ->
      j = i.split(':')
      if !j[1]
        projection[j[0]] = 1
        return
      j[1] = parseInt(j[1]) if parseInt(j[1]) + '' == j[1]
      j
  {criteria, projection}

makeSort = (r) ->
  sort = if r == '-1'
    _id: -1
  else if r.startsWith('{') && r.endsWith('}')
    try
      JSON.parse r.replace /(['"])?([a-z0-9A-Z_]+)(['"])?:/g, '"$2": '
    catch e
      {}
  else
    _.fromPairs _.filter _.map r.split(','), (i) ->
      j = i.split(':')
      return if !j[1]
      j[1] = parseInt(j[1]) || 1
      j

makeTableHeader = (docs, projection) ->
  header = []
  header = ['_id'].concat _.keys projection if projection
  _.each docs, (i) ->
    _.each _.keys(i), (j) ->
      header.push j if !header.includes j
  header.push(header.splice(index, 1)[0]) if (index = header.indexOf('__v')) != -1
  header

makeTableBody = (docs, header) ->
  body = []
  _.each docs, (i) ->
    line = []
    _.each header, (j) ->
      line.push switch true
        when i[j] instanceof ObjectID then chalk.red i[j]
        when i[j] instanceof Date then chalk.green moment(i[j]).format()
        when typeof i[j] == 'number' then chalk.green i[j]
        when typeof i[j] == 'string' then chalk.magenta i[j].replace(/[\n\r\t]/g, '')[...TRUNCATE]
        when i[j] instanceof Array then chalk.cyan "[#{i[j].length}]"
        when i[j] instanceof Object then chalk.cyan "{#{_.keys(i[j]).length}}"
        else i[j]
    body.push line
  body

makeTable = (docs, projection, count) ->
  header = makeTableHeader docs, projection
  body = makeTableBody docs, header
  data = table [header].concat body
  info = "#{docs.length}/#{count}"
  data = _.map(data.split('\n'), (i) -> sliceAnsi(i, 0, process.stdout.columns))
  data.pop()
  data[data.length - 1] = data[data.length - 1][..[data[data.length - 1].length] - info.length - 3] + info + data[data.length - 1][-2..]
  data.join('\n')

do ->
  client = await MongoClient.connect "mongodb://#{HOST}:#{PORT}", {useUnifiedTopology: true}
  
  if !args[0]
    console.log _.map((await client.db('admin').admin().listDatabases()).databases, 'name').join('\n')
    return client.close()

  db = client.db args[0]
  
  if !args[1]
    if CREATE
      await db.createCollection(CREATE)
      console.log 'collection created'
    else
      console.log _.map(await db.listCollections().toArray(), 'name').join('\n')
    return client.close()

  collection = db.collection args[1]

  criteria = {}
  if args[2]
    {criteria, projection} = makeCriteriaAndProjection(args[2])
  count = await collection.find(criteria).count()
  options = limit: LIMIT
  options.projection = projection if projection && count > 1
  sort = {}
  sort = makeSort(SORT) if program.sort
  docs = await collection.find(criteria, options).sort(sort).toArray()
  
  if INSERT
    doc = _.filter(_.map(makeTableHeader(docs, projection), (i) -> i != '_id' && !i.startsWith('__') && i))
    docs = [_.fromPairs(_.map(doc, (i) -> [i, '']))]

  if docs.length > 1
    console.log makeTable docs, projection, count
 
    client.close()

  else if docs.length == 1
    doc = docs[0]

    doc = Object.assign {__: 'SAVE THIS FILE TO DELETE'}, docs[0] if DELETE

    fs.writeFileSync '/tmp/mongog.json', EJSON.stringify doc, null, 2
    mtime = (fs.statSync('/tmp/mongog.json')).mtimeMs
    
    childExit = (err, code) ->
      mtime_new = (fs.statSync('/tmp/mongog.json')).mtimeMs

      if mtime != mtime_new
        mtime = mtime_new
        try
          doc = EJSON.parse fs.readFileSync '/tmp/mongog.json', 'utf8'
          if !doc._id
            await collection.insertOne doc
            console.log 'document inserted'
          else
            _id = new ObjectID doc._id
            if DELETE
              await collection.deleteOne {_id}
              console.log 'document deleted'
            else
              delete doc._id
              await collection.updateOne {_id}, {$set: doc}
              console.log 'document updated'
          client.close()
        catch
          child = child_process.spawn EDITOR, ['/tmp/mongog.json'], stdio: 'inherit'
          child.on 'exit', childExit
      else
        client.close()

    child = child_process.spawn EDITOR, ['/tmp/mongog.json'], stdio: 'inherit'
    child.on 'exit', childExit

  else
    client.close()
