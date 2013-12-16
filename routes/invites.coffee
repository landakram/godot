Q = require 'q'
utils = require '../utils'
models = require '../models'
User = models.User

exports.getInviteLink = (req, res) ->
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.getInviteID (inviteID) ->
                inviteLink = utils.absoluteUrlForPath req, "/i/#{inviteID}"
                res.json {inviteLink: inviteLink}

exports.trackInvite = (req, res) ->
    req.session.inviter = req.params.inviteID
    res.redirect req.app.get('redirectURL')

exports.incrementInvites = (req, res) ->
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.incrementInvites 1, ->
                res.json {invites: user.info.invites}

