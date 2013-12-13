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
        @info = options.info ? {}

    saveInfo: (callback) ->
        infoList = []
        infoList.push(key) and infoList.push(@info[key]) for own key of @info when key isnt 'email'
        otherInfoPromise = if infoList.length then Q.ninvoke(client, 'hmset', "user:#{@id}", infoList...) else Q.resolve()
        emailPromise = if @info.email then Q.ninvoke(client, 'hsetnx', "user:#{@id}", 'email', @info.email) else Q.resolve()
        Q.all([otherInfoPromise, emailPromise]).then(callback).done()

    setEmail: (email, callback) ->
        @info.email = email
        @saveInfo callback

    incrementScore: (byAmount, callback) ->
        if @list is User.WAITING_LIST_KEY
            client.zincrby @list, byAmount, @id, (err, val) =>
                @rank = null
                @getRank callback
        else
            callback null

    redeemReferral: (callback) ->
        @info.referrals = (@info.referrals or 0) + 1
        @incrementScore 1, => (@saveInfo -> callback)

    getRank: (callback) ->
        if @rank
            if callback then callback @rank
        else
            client.zrevrank User.WAITING_LIST_KEY, @id, (err, val) ->
                @rank = val
                if callback then callback @rank

    getReferralID: (callback) ->
        if @info.referralID
            if callback then callback @info.referralID
        else
            Q.nfcall(crypto.randomBytes, User.ID_SIZE).then (buf) =>
                @info.referralID = buf.toString 'hex'
                [@saveInfo, Q.ninvoke(client, 'set', "referral:#{@info.referralID}", @id)]
            .spread =>
                callback @info.referralID

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

    @getByReferralID: (referralID, callback) ->
        Q.ninvoke(client, 'get', "referral:#{referralID}").then (id) ->
            User.get id, callback

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
             Q.ninvoke(client, 'zadd', User.WAITING_LIST_KEY, score, id)]
        .spread (id, score) ->
            if callback then callback(new User {id: id, score: score, list: User.WAITING_LIST_KEY})
        .done()

exports.User = User
