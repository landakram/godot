models = require '../models'
User = models.User

exports.reserveSpot = (req, res) ->
    User.create (user) ->
        user.getRank (rank) ->
            waiting = true
            if user.list is User.GRANTED_LIST_KEY then waiting = false
            res.json {id: user.id, rank: rank, waiting: waiting}

exports.checkSpot = (req, res) ->
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.getRank (rank) ->
                waiting = true
                if user.list is User.GRANTED_LIST_KEY then waiting = false
                res.json {id: user.id, rank: rank, waiting: waiting}

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


