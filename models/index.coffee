Q = require 'q'
redis = require('redis')
crypto = require('crypto')
client = redis.createClient()

class User
    @ID_SIZE: 4
    @WAITING_LIST_KEY: 'waiting_list'
    @GRANTED_LIST_KEY: 'granted_list'

    constructor: (options) ->
        @id = options.id
        @score = options.score
        @list = options.list
        @info = options.info or {}

    saveInfo: (callback) ->
        infoList = []
        infoList.push(key) and infoList.push(@info[key]) for own key of @info
        Q.ninvoke(client, 'hset', "user:#{@id}", infoList...).then(callback).done()

    setEmail: (email, callback) ->
        @info.email = email
        @saveInfo callback

    getRank: (callback) ->
        if @rank
            if callback then callback @rank
        else
            client.zrevrank User.WAITING_LIST_KEY, @id, (err, val) ->
                @rank = val
                if callback then callback @rank

    @dequeue: (spots, callback) ->
        # Unfortunately, there is no way to atomically remove and return
        # members of a redis sorted set. I suppose this is close enough.

        # Get the first `spots` members
        Q.ninvoke(client, 'zrevrange', User.WAITING_LIST_KEY, 0, spots - 1).then (members) ->
            members ?= []
            multi = client.multi()
            if members.length > 0
                multi.zrem User.WAITING_LIST_KEY, members...
                multi.sadd User.GRANTED_LIST_KEY, members...
                [members, Q.ninvoke(multi, 'exec')]
            else
                [members]
        .spread (members) ->
            if callback then callback members
        .done()

    @get: (id, callback) ->
        user = new User {id: id}
        grantedPromise = Q.ninvoke(client, 'sismember', User.GRANTED_LIST_KEY, id)
        scorePromise = Q.ninvoke(client, 'zscore', User.WAITING_LIST_KEY, id)
        infoPromise = Q.ninvoke(client, 'hgetall', "user:#{id}")
        Q.all([scorePromise, grantedPromise, infoPromise])
        .spread (score, alreadyGranted, persistedInfo) ->
            user.info = persistedInfo ? {}
            doesntExist = not score and not alreadyGranted
            if doesntExist
                user = null
            else if alreadyGranted
                user.list = User.GRANTED_LIST_KEY
            else if score
                user.list = User.WAITING_LIST_KEY
                user.score = Number score
            if callback then callback user
        .done()

    @create: (callback) ->
        counterPromise = Q.ninvoke(client, 'incr', 'counter')
        idPromise = Q.nfcall(crypto.randomBytes, User.ID_SIZE).then (buf) ->
            Q.resolve(buf.toString 'hex')

        Q.all([counterPromise, idPromise]).then ([spot, id]) ->
            score = 1 / spot
            [id,
             score,
             #Q.ninvoke(client, 'hset', "user:#{id}", 'status', 'waiting'),
             Q.ninvoke(client, 'zadd', User.WAITING_LIST_KEY, score, id)]
        .spread (id, score) ->
            if callback then callback(new User {id: id, score: score, list: User.WAITING_LIST_KEY})
        .done()

exports.User = User
