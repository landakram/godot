Q = require 'q'
utils = require '../utils'
models = require '../models'
User = models.User

exports.getReferralLink = (req, res) ->
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.getReferralLink req, (err, link) ->
                if err
                    res.json {error: err}
                else
                    res.json {referralLink: link}

exports.trackReferral = (req, res) ->
    req.session.referrer = req.params.referralID
    res.redirect req.app.get('redirectURL')
