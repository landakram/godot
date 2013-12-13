Q = require 'q'
url = require 'url'
models = require '../models'
User = models.User

exports.reserveSpot = (req, res) ->
    referralID = req.session.referrer
    referralDeferred = Q.defer()
    if referralID
        User.getByReferralID referralID, (referringUser) ->
            referralDeferred.resolve(referringUser)
            if referringUser then referringUser.redeemReferral()
    else
        referralDeferred.resolve()

    User.create (user) ->
        user.getRank (rank) ->
            referralDeferred.promise.then (referringUser) ->
                if referringUser then user.info.referredBy = referralID
                user.saveInfo()
                waiting = true
                if user.list is User.GRANTED_LIST_KEY then waiting = false
                req.session.id = user.id
                req.session.referrer = null
                res.json {id: user.id, rank: rank, waiting: waiting, referred: true if referralID?}

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
                res.json {sucess: true}

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



exports.getReferralLink = (req, res) ->
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.getReferralID (referralID) ->
                referralLink = absoluteUrlForPath req, "/r/#{referralID}"
                res.json {referralLink: referralLink}

exports.trackReferral = (req, res) ->
    redirectURL = decodeURIComponent req.param('r')
    req.session.referrer = req.params.referralID
    res.redirect req.app.get('externalRedirectURL')



absoluteUrlForPath = (req, path) ->
    absoluteUrl = {
        protocol: req.protocol,
        hostname: req.host,
        port: req.app.settings.port,
        pathname: path
    }
    url.format absoluteUrl
