Q = require 'q'
models = require '../models'
client = models.client
User = models.User

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
