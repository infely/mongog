#!/usr/bin/coffee

fs            = require('fs')
child_process = require('child_process')
program       = require('commander')
_             = require('lodash')
moment        = require('moment')
mongodb       = require('mongodb')
table         = require('table').table
MongoClient   = mongodb.MongoClient
ObjectID      = mongodb.ObjectID

program
  .option('-l, --limit <number>', 'limit rows')
  .option('-t, --truncate <number>', 'truncate strings')
args = program.parse(process.argv).args
LIMIT = parseInt(program.limit) || 10
TRUNCATE = parseInt(program.truncate) || 32

makeCriteria = (r) ->
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
    _.fromPairs  _.filter _.map r.split(','), (i) ->
      j = i.split(':')
      if !j[1]
        projection[j[0]] = 1
        return
      j[1] = parseInt(j[1]) if parseInt(j[1]) + '' == j[1]
      j
  {criteria, projection}

do ->
  client = await MongoClient.connect 'mongodb://localhost:27017', {useUnifiedTopology: true}
  
  if !args[0]
    console.log _.map((await client.db('admin').admin().listDatabases()).databases, 'name').join('\n')
    return client.close()

  db = client.db args[0]
  
  if !args[1]
    console.log _.map(await db.listCollections().toArray(), 'name').join('\n')
    return client.close()

  collection = db.collection args[1]

  criteria = {}
  if args[2]
    {criteria, projection} = makeCriteria(args[2])
  count = await collection.find(criteria).count()
  options = limit: LIMIT
  options.projection = projection if projection && count > 1
  docs = await collection.find(criteria, options).toArray()
  
  if docs.length > 1
    data = [[]]
    data[0] = ['_id'].concat _.keys projection if projection
    _.each docs, (i) ->
      _.each _.keys(i), (j) ->
        data[0].push j if !data[0].includes j
    if (index = data[0].indexOf('__v')) != -1
      data[0].push(data[0].splice(index, 1))
    _.each docs, (i) ->
      line = []
      _.each data[0], (j) ->
        line.push if Array.isArray(i[j])
          "[#{i[j].length}]"
        else if i[j] instanceof Date
          moment(i[j]).format()
        else if typeof i[j] == 'string'
          i[j].replace(/[\n\r\t]/g, '')[...TRUNCATE]
        else
          i[j]
      data.push line

    data = table data
    info = "#{docs.length}/#{count}"
    data = _.map(data.split('\n'), (i) -> i[...process.stdout.columns])
    data.pop()
    data[data.length - 1] = data[data.length - 1][..[data[data.length - 1].length] - info.length - 3] + info + data[data.length - 1][-2..]
    console.log data.join('\n')
 
    client.close()
  else
    fs.writeFileSync '/tmp/mongod.json', JSON.stringify docs[0], null, 2
    child = child_process.spawn 'vi', ['/tmp/mongod.json'], stdio: 'inherit'
    
    child.on 'exit', (err, code) ->
      doc = JSON.parse fs.readFileSync '/tmp/mongod.json', 'utf8'

      if !doc._id
        await collection.insertOne doc
      else
        _id = new ObjectID doc._id
        delete doc._id
        await collection.updateOne {_id}, {$set: doc}
        
      client.close()
