#!/usr/bin/env coffee
'use strict'
opts   = require 'opts'

opts.parse [
  short       : 's'
  long        : 'src'
  description : 'source ns'
  value       : true
  required    : true
,
  short       : 'd'
  long        : 'dst'
  description : 'destination ns'
  value       : true
  required    : false
,
  short       : 'a'
  long        : 'append'
  description : 'append mode'
  value       : true
  required    : false
,
  short       : 'c'
  long        : 'config'
  description : 'configPath'
  value       : true
  required    : false
,
  short       : 'p'
  long        : 'chunkSize'
  description : 'chunkSize (default: 300)'
  value       : true
  required    : false
]
src = opts.get 'src'
dst = opts.get('dst') || "#{src}.tf"
append = opts.get('append') || undefined
configPath = opts.get('config') || 'config/momonger.conf'
chunkSize = opts.get('chunkSize') || 1000

async   = require 'async'
Config = require 'momonger/config'
{JobControl} = require 'momonger/job'
{Tf} = require 'momonger/vectorize'

options = {
  runLocal: false
  chunkSize
  src
  dst
  append
}

momonger = Config.load configPath

jobControl = new JobControl momonger
jobid = null
async.series [
  (done) => jobControl.init done
  (done) => jobControl.put Tf, options, (err, result)->
    jobid = result
    done err
  (done) => jobControl.wait jobid, done
], (err, results)=>
  if err
    console.error err
    process.exit 1
  process.exit 0
