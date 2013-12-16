Q = require 'q'
utils = require '../utils'
models = require '../models'
User = models.User

exports.getReferralLink = (req, res) ->
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.getReferralID (referralID) ->
                referralLink = utils.absoluteUrlForPath req, "/r/#{referralID}"
                res.json {referralLink: referralLink}

exports.trackReferral = (req, res) ->
    req.session.referrer = req.params.referralID
    res.redirect req.app.get('redirectURL')
