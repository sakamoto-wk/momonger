#!/usr/bin/env coffee
'use strict'
opts   = require 'opts'
cluster = require 'cluster'

opts.parse [
  short       : 'c'
  long        : 'config'
  description : 'Specify config file'
  value       : true
  required    : false
,
  short       : 'j'
  long        : 'jobs'
  description : 'Specify num of jobs'
  value       : true
  required    : false
,
]
configPath = 'config/momonger.conf'
configPath ||= opts.get 'config'
jobs = parseInt(opts.get('jobs')) || 5
{Worker, Config} = require 'momonger-core'

momonger = Config.load configPath

finish = false
if cluster.isMaster
  cluster.on 'exit', (worker, code, signal) ->
    cluster.fork() unless finish
  for _ in [0...jobs]
    cluster.fork()
  process.on 'SIGINT', ->
    finish = true
    for worker in cluster.workers
      worker.send 'int'
else
  Worker.start momonger
  process.on 'message', (msg)->
    Worker.finish()