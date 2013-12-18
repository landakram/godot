models = require '../models'
client = models.client

Q = require 'q'
crypto = require('crypto')
utils = require '../utils'

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

    incrementInvites: (byAmount, callback) ->
        if typeof @info.invites is 'string'
            @info.invites = Number @info.invites
        @info.invites ?= 0
        @info.invites += byAmount
        @saveInfo callback

    clearInvites: (callback) ->
        @info.invites = 0
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
        if @rank and @projectedSharingRank
            if callback then callback @rank
        else
            client.zrevrank User.WAITING_LIST_KEY, @id, (err, val) =>
                @rank = val
                @getProjectedSharingRank().then =>
                    if callback then callback @rank
                .done()

    getProjectedSharingRank: (callback) ->
        rankDeferred = Q.defer()
        if @score?
            closestMemberPromise = Q.ninvoke client, 'zrevrangebyscore', User.WAITING_LIST_KEY, @score + 1, Number.NEGATIVE_INFINITY, 'limit', 0, 1
            closestMemberPromise.then (members) =>
                closestMember = members[0]
                if closestMember
                    client.zrevrank User.WAITING_LIST_KEY, closestMember, (err, val) =>
                        @projectedSharingRank = val
                        rankDeferred.resolve val
                        if callback then callback val
                else
                    rankDeferred.resolve null
                    if callback then callback null
            .done()
        else
            rankDeferred.resolve null
            if callback then callback null
        rankDeferred.promise

    getReferralLink: (req, callback) ->
        @getReferralID (referralID) =>
            referralLink = utils.absoluteUrlForPath req, "/r/#{referralID}"
            @info.referralLink = referralLink
            utils.shortenUrl referralLink, (err, link) =>
                if err?
                    callback err
                else if link?
                    @info.shortReferralLink = link
                    @saveInfo()
                    callback null, link

    getReferralID: (callback) ->
        if @info.referralID
            if callback then callback @info.referralID
        else
            Q.nfcall(crypto.randomBytes, User.ID_SIZE).then (buf) =>
                @info.referralID = buf.toString 'hex'
                [@saveInfo, Q.ninvoke(client, 'set', "referral:#{@info.referralID}", @id)]
            .spread =>
                callback @info.referralID
            .done()

    getInviteLink: (req, callback) ->
        @getInviteID (inviteID) =>
            inviteLink = utils.absoluteUrlForPath req, "/i/#{inviteID}"
            @info.inviteLink = inviteLink
            utils.shortenUrl inviteLink, (err, link) =>
                if err?
                    callback err
                else if link?
                    @info.shortInviteLink = link
                    @saveInfo()
                    callback null, link

    getInviteID: (callback) ->
        if @info.inviteID
            if callback then callback @info.inviteID
        else
            Q.nfcall(crypto.randomBytes, User.ID_SIZE).then (buf) =>
                @info.inviteID = buf.toString 'hex'
                [@saveInfo, Q.ninvoke(client, 'set', "invite:#{@info.inviteID}", @id)]
            .spread =>
                callback @info.inviteID
            .done()

    dequeue: (callback) ->
        multi = client.multi()
        multi.zrem User.WAITING_LIST_KEY, @id
        multi.sadd User.GRANTED_LIST_KEY, @id
        multi.exec (err, val) =>
            if callback then callback val

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

    @getByInviteID: (inviteID, callback) ->
        deferred = Q.defer()
        Q.ninvoke(client, 'get', "invite:#{inviteID}").then (id) ->
            User.get id, (user) =>
                deferred.resolve user
                if callback then callback user
        deferred.promise

    @get: (id, callback) ->
        user = new User {id: id}
        userDeferred = Q.defer()
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
            userDeferred.resolve user
        .done()
        userDeferred.promise

    @create: (waiting, callback) ->
        counterPromise = Q.ninvoke(client, 'incr', 'counter')
        idPromise = Q.nfcall(crypto.randomBytes, User.ID_SIZE).then (buf) ->
            Q.resolve(buf.toString 'hex')

        list = null
        Q.all([counterPromise, idPromise]).spread (spot, id) ->
            enqueuePromise = null
            score = null
            if waiting is true
                list = User.WAITING_LIST_KEY
                score = 1 / spot
                enqueuePromise = Q.ninvoke(client, 'zadd', list, score, id)
            else
                list = User.GRANTED_LIST_KEY
                enqueuePromise = Q.ninvoke(client, 'sadd', list, id)
            [id, score, enqueuePromise]
        .spread (id, score) ->
            if callback then callback(new User {id: id, score: score, list: list})
        .done()

    @waitingListLength: (callback) ->
        lengthPromise = Q.ninvoke client, 'zcard', User.WAITING_LIST_KEY
        lengthPromise.then (val) -> if callback then callback null, val
        lengthPromise.fail (err) -> if callback then callback err
        lengthPromise

exports.User = User
