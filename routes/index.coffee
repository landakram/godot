Q = require 'q'
url = require 'url'
models = require '../models'
client = models.client
User = models.User

exports.reserveSpot = (req, res) ->
    referralID = req.session.referrer
    referDeferred = Q.defer()
    inviteID = req.session.inviter
    inviteDeferred = Q.defer()
    if inviteID?
        User.getByInviteID inviteID, (invitingUser) ->
            # Only count the invite if the inviting user has invites left
            if invitingUser? and invitingUser.info.invites > 0
                invitingUser.incrementInvites -1
                inviteDeferred.resolve(invitingUser)
            else
                inviteDeferred.resolve {error: 'expired'}
    else
        inviteDeferred.resolve()

    if referralID?
        inviteDeferred.promise.then (invitingUser) ->
            # If the user was invited, then we don't worry about referrals
            if invitingUser? and not invitingUser.error
                referDeferred.resolve()
            # Otherwise, do the referral stuff
            else
                User.getByReferralID referralID, (referringUser) ->
                    referDeferred.resolve(referringUser)
                    if referringUser then referringUser.redeemReferral()
        .done()
    else
        referDeferred.resolve()

    createUserAndSendResponse = (waiting) ->
        User.create waiting, (user) ->
            user.getRank (rank) ->
                Q.all([inviteDeferred.promise, referDeferred.promise]).spread (invitingUser, referringUser) ->
                    user.info.referredBy = referralID if referringUser?
                    user.info.invitedBy = inviteID if invitingUser? and not invitingUser.error
                    user.saveInfo()
                    req.session.id = user.id
                    req.session.referrer = null
                    res.json {
                        id: user.id, rank: rank, waiting: waiting,
                        referred: true if referringUser?,
                        invited: true if invitingUser? and not invitingUser.error,
                        error: invitingUser.error if invitingUser?
                    }
                .done()

    waiting = req.app.get('enabled')
    if not waiting
        createUserAndSendResponse(waiting)
    else
        inviteDeferred.promise.then (invitingUser) ->
            waiting = false if invitingUser? and not invitingUser.error
            createUserAndSendResponse(waiting)
        .done()

exports.checkSpot = (req, res) ->
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.getRank (rank) ->
                waiting = true
                if user.list is User.GRANTED_LIST_KEY then waiting = false
                res.json {id: user.id, rank: rank, waiting: waiting}

exports.setEmail = (req, res) ->
    email = req.param('email')
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.setEmail email, ->
                res.json {success: true}



exports.getReferralLink = (req, res) ->
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.getReferralID (referralID) ->
                referralLink = absoluteUrlForPath req, "/r/#{referralID}"
                res.json {referralLink: referralLink}

exports.trackReferral = (req, res) ->
    req.session.referrer = req.params.referralID
    res.redirect req.app.get('externalRedirectURL')


exports.getInviteLink = (req, res) ->
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.getInviteID (inviteID) ->
                inviteLink = absoluteUrlForPath req, "/i/#{inviteID}"
                res.json {inviteLink: inviteLink}

exports.trackInvite = (req, res) ->
    req.session.inviter = req.params.inviteID
    res.redirect req.app.get('externalRedirectURL')

exports.incrementInvites = (req, res) ->
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.incrementInvites 1, ->
                res.json {invites: user.info.invites}

exports.toggleWaitingList = (req, res) ->
    apiKey = req.param('apiKey')
    if apiKey isnt req.app.get('apiKey')
        res.json 403, {error: 'Forbidden.'}

    type = req.param('t')
    enable = if type is 'enable' then true else if type is 'disable' then false
    if not enable?
        res.json 400, {error: 'Please specify "enable" or "disable".'}
    else
        client.hset 'config', 'enabled', enable
        req.app.set 'enabled', enable

        # If we're disabling the list, dequeue everybody
        dequeuedDeferred = Q.defer()
        if enable isnt true
            Q.ninvoke(client, 'zcard', User.WAITING_LIST_KEY).then (everybody) ->
                User.dequeue everybody, (members) ->
                    dequeuedDeferred.resolve members
            .done()
        # Otherwise, don't do anything, since we check for enabled when we
        # reserve a spot
        else
            dequeuedDeferred.resolve null

        dequeuedDeferred.promise.then (members) ->
            res.json {enabled: req.app.get('enabled'), dequeued: members}
        .done()

exports.openSesame = (req, res) ->
    spots = Number req.param('spots')
    apiKey = req.param('apiKey')

    if apiKey isnt req.app.get('apiKey')
        res.json 403, {error: 'Forbidden.'}
    else if not spots
        res.json 400, {error: 'Please specify the number of spots to open.'}
    else
        User.dequeue spots, (members) ->
            res.json {dequeued: members}


absoluteUrlForPath = (req, path) ->
    absoluteUrl = {
        protocol: req.protocol,
        hostname: req.host,
        port: req.app.settings.port,
        pathname: path
    }
    url.format absoluteUrl
