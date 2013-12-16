_ = require 'underscore'
redis = require 'redis'
url = require 'url'

redisURL = url.parse 'http://localhost:6379'
if process.env.REDISCLOUD_URL
    redisURL = url.parse process.env.REDISCLOUD_URL

client = redis.createClient redisURL.port, redisURL.hostname, {no_ready_check: true}

if redisURL.auth?
    client.auth redisURL.auth.split(":")[1]

exports.client = client
_.extend exports, require './user'
