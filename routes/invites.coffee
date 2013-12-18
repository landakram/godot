Q = require 'q'
utils = require '../utils'
models = require '../models'
User = models.User

exports.getInviteLink = (req, res) ->
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.getInviteLink req, (err, link) ->
                if err
                    res.json {error: err}
                else
                    res.json {inviteLink: link}

exports.trackInvite = (req, res) ->
    req.session.inviter = req.params.inviteID
    res.redirect req.app.get('redirectURL')

exports.incrementInvites = (req, res) ->
    lengthPromise = User.waitingListLength()
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.incrementInvites 1, ->
                waiting = req.app.get('enabled')
                data = {invites: user.info.invites, waiting: waiting}
                if waiting
                    lengthPromise.then (length) ->
                        data.waitingListLength = length
                        res.json data
                else
                    res.json data

exports.clearInvites = (req, res) ->
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.clearInvites ->
                waiting = req.app.get('enabled')
                res.json {invites: user.info.invites, waiting: waiting}
