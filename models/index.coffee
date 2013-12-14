_ = require 'underscore'
redis = require 'redis'
client = redis.createClient()

exports.client = client
_.extend exports, require './user'
