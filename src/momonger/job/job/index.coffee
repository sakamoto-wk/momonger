'use strict'
_ = require 'underscore'
async = require 'async'
Mongo = require 'momonger/mongo'
{toTypeValue} = require 'momonger/common'

class Job
  constructor: (@jobcontrol, @jobid, @config, @options)->
    # console.log 'JOBID', @jobid

  _prepare: (done)->
    if @options.src
      @srcMongo = Mongo.getByNS @config, @options.src
    if @options.dst
      @dstMongo = Mongo.getByNS @config, @options.dst
    if @options.emit
      @emitMongo = Mongo.getByNS @config, @options.emit
    if @options.emitids
      @emitidsMongo = Mongo.getByNS @config, @options.emitids
    async.parallel [
      (done) =>
        return done null unless @srcMongo
        @srcMongo.init done
      (done) =>
        return done null unless @dstMongo
        @dstMongo.init done
      (done) =>
        return done null unless @emitMongo
        @emitMongo.init done
      (done) =>
        return done null unless @emitidsMongo
        @emitidsMongo.init done
    ], done

  _dropDestination: (done)->
    async.parallel [
      (done) =>
        return done null unless @dstMongo
        if @options.appendDst
          return done null unless @options.append
          @dstMongo.remove {a: @options.append}, ->
            done null
        else
          @dstMongo.drop ->
            done null
      (done) =>
        return done null unless @emitMongo
        @emitMongo.drop ->
          done null
      (done) =>
        return done null unless @emitidsMongo
        @emitidsMongo.drop ->
          done null
    ], done

  beforeRun: (done)->
    done null

  run: (done)->
    done 'Not implemented'

  _run: (done)->
    async.series {
      prepare:
        (done)=> @_prepare done
      beforeRun:
        (done)=> @beforeRun done
      run:
        (done)=> @run done
    }, (err, results) ->
      done err, results.run

exports.Job = Job

class Mapper extends Job
  constructor: (@jobcontrol, @jobid, @config, @options)->
    @ids ||= @options.map?.ids
    @ids ||= @options.reduce?.ids
    @options.org ||= @options.src
    @orgMongo = Mongo.getByNS @config, @options.org
    @emitDataById = {}

  emit: (id, value) ->
    typeVal = toTypeValue id
    @emitDataById[typeVal] ||= { id, values: []}
    @emitDataById[typeVal].values.push value

  map: (data, done)->
    done 'Not implemented'

  # reduce: (id, array, done)->
  #   done 'Not implemented'

  lastFormat: (data)->
    data

  beforeRun: (done)->
    done null

  afterRun: (done)->
    done null

  _maps: (done) ->
    @srcMongo.findAsArray
      _id:
        $in: @ids
    , (err, elements)=>
      return done err if err
      if @options.map
        async.eachLimit elements, 10, (element, done) =>
          @map element, (err) =>
            setTimeout =>
              done(err)
            , 0
        , done
      else if @options.reduce
        for element in elements
          typeVal = toTypeValue element.id
          @emitDataById[typeVal] ||= { id: element.id, values: []}
          for value in element.values
            @emitDataById[typeVal].values.push value
        done null
      else
        done 'Unknown map OP'

  _reduceEmitBuffer: (done) ->
    async.eachLimit _.values(@emitDataById), 10, (emitData, done)=>
      if emitData.values.length <= 1
        return setTimeout =>
          done(null)
        , 0
      @reduce emitData.id, emitData.values, (err, value) =>
        return done err if err
        typeVal = toTypeValue emitData.id
        @emitDataById[typeVal].values = [value]
        setTimeout =>
          done(null)
        , 0
    , done

  _saveEmitBuffer: (done) ->
    if @options.map
      return done null unless @emitMongo and @emitidsMongo
      emitIdById = {}
      emitDatas = []
      for typeVal, emitData of @emitDataById
        emitData._id = Mongo.ObjectId()
        emitDatas.push emitData
        emitIdById[typeVal] ||= [
          _id: typeVal
        ,
          $pushAll:
            ids: []
        ]
        emitIdById[typeVal][1].$pushAll.ids.push emitData._id
      async.parallel [
        (done) => @emitMongo.bulkInsert emitDatas, done
        (done) => @emitidsMongo.bulkUpdate _.values(emitIdById), done
      ], done
    else if @options.reduce
      inserts = []
      updates = []
      for result in _.values(@emitDataById)
        result.value = result.values[0]
        delete result.values
        result = @lastFormat(result)
        if _.isArray result
          updates.push result
        else
          inserts.push result
      async.series [
        (done) => @dstMongo.bulkInsert inserts, done
        (done) => @dstMongo.bulkUpdate updates, done
      ], done
    else
      done 'Unknown map OP'

  _run: (done)->
    async.series [
      (done)=> @_prepare done
      (done)=> @beforeRun done
      (done)=> @_maps done
      (done)=> @_reduceEmitBuffer done
      (done)=> @_saveEmitBuffer done
      (done)=> @afterRun done
    ], (err) =>
      console.error err if err
      done err, null

exports.Mapper = Mapper

class MapJob extends Job
  constructor: (@jobcontrol, @jobid, @config, @options)->
    @options = _.extend {
      chunkSize: 1000
      query: {}
    }, @options
    @options.query = _.extend {
      _id:
        $ne: '.meta'
    }, @options.query
    @options.emit ||= "#{@options.dst}.emit"
    @options.emitids ||= "#{@options.emit}.ids"

  beforeFirstMap: (done)->
    console.log 'map::beforeFirstMap'
    done null

  afterLastMap: (done)->
    console.log 'map::afterLastMap'
    done null

  afterRun: (done)->
    console.log 'map::afterRun'
    done null

  mapper: ->
    throw 'Should retern Mapper job'

  _run: (done)->
    doReduce = !!@mapper().prototype.reduce
    async.series {
      prepare:
        (done)=> @_prepare done
      drop:
        (done)=> @_dropDestination done
      beforeFirstMap:
        (done)=> @beforeFirstMap done
      mappers:
        (done)=> @_mappers done
      afterLastMap:
        (done)=> @afterLastMap done
      reducers:
        (done)=>
          return done null unless doReduce
          @_reducers done
      afterRun:
        (done)=> @afterRun done
    }, (err, results) =>
      done err, results?.afterRun

  _createMapper: (ids, done)->
    options = _.extend {}, @options, {
      map:
        ids: ids
    }
    @jobcontrol.put @mapper(), options, done

  _createReducer: (ids, done)->
    options = _.extend {}, @options, {
      org: @options.src
      src: @options.emit
      reduce:
        ids: ids
    }
    @jobcontrol.put @mapper(), options, done

  _mappers: (done)->
    @jobids = []
    async.series [
      (done) =>
        @srcMongo.find @options.query, (err, cursor)=>
          return done err if err
          Mongo.inBatch cursor, @options.chunkSize,
            (data)-> data._id
          ,
            (ids, done)=>
              @_createMapper ids, (err, jobid)=>
                @jobids.push jobid
                done null
          , done
      (done) =>
        async.eachSeries @jobids, (jobid, done) =>
          @jobcontrol.wait jobid, done
        , done
    ], done

  _reducers: (done)->
    @jobids = []
    chunkSize = 1
    async.series [
      (done) =>
        @emitidsMongo.count (err, result)->
          chunkSize = Math.floor(result / 100) + 1
          done null
      (done) =>
        @emitidsMongo.find {}, (err, cursor)=>
          return done err if err
          Mongo.inBatch cursor, chunkSize,
            (data)-> data.ids
          ,
            (idsArr, done)=>
              reduceIds = []
              for ids in idsArr
                reduceIds = reduceIds.concat ids
              @_createReducer reduceIds, (err, jobid)=>
                @jobids.push jobid
                done null
          , done
      (done) =>
        async.eachSeries @jobids, (jobid, done) =>
          @jobcontrol.wait jobid, done
        , done
    ], done


exports.MapJob = MapJob
