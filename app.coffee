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

args = program.parse(process.argv).args

makeCriteria = (r) ->
  if r.match /^[0-9a-fA-F]{24}$/
    _id: new ObjectID r
  else if r.startsWith('{') && r.endsWith('}')
    try
      JSON.parse r.replace /(['"])?([a-z0-9A-Z_]+)(['"])?:/g, '"$2": '
    catch e
      {}
  else
    _.fromPairs _.map r.split(','), (i) ->
      j = i.split(':')
      j[1] = parseInt(j[1]) if parseInt(j[1]) + '' == j[1]
      j

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
  criteria = makeCriteria(args[2]) if args[2]
  docs = await collection.find(criteria).limit(10).toArray()
  
  if docs.length > 1
    count = await collection.find(criteria).count()
    
    data = [_.keys docs[0]]
    _.each docs[1..], (i) ->
      _.each _.keys(i), (j) ->
        data[0].push j if !data[0].includes j
    _.each docs, (i) ->
      line = []
      _.each data[0], (j) ->
        return line.push '' if !i[j]
        
        line.push if Array.isArray(i[j])
          '[]'
        else if i[j] instanceof Date
          moment(i[j]).format()
        else i[j]
      data.push line

    data = table data
    process.stdout.write _.map(data.split('\n'), (i) -> i[...process.stdout.columns]).join('\n')
    console.log "#{docs.length}/#{count}"
 
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
