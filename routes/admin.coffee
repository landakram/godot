Q = require 'q'
_ = require 'underscore'
postmark = require('postmark')(process.env.POSTMARK_API_KEY)
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
            sendReadyEmails members, req

sendReadyEmails = (userIDs, req) ->
    waitingListSizePromise = Q.ninvoke(client, 'zcard', User.WAITING_LIST_KEY)
    userPromises = (User.get userID for userID in userIDs)
    Q.all(userPromises).then (users) ->
        waitingListSizePromise.then (size) ->
            messages = (composeEmail user, size, req for user in users when user? and user.info.email?)
            postmark.batch messages, (err, success) ->
                if err? then console.log "Errors sending emails: #{err}"
                if success? then console.log "Successes sending emails: #{success}"

composeEmail = (user, waitingListSize, req) ->
    appName = process.env.APP_NAME
    tweetText = encodeURIComponent "Hey friends, there are #{waitingListSize} people waiting in line to use #{appName}, but I waited so 5 of you can skip the line. #{user.info.shortInviteLink}"
    From: req.app.get 'emailAddress'
    To: user.info.email
    Subject: "We're ready for you!"
    HtmlBody: _.template(templateString, {redirectUrl: (req.app.get 'redirectURL'), tweetText: tweetText, appName: appName})

templateString = "
<p>You're in!</p>
<p>Thanks for waiting while we got everything ready for you.</p>
<p>Before you run off and start replacing passwords, there's one more thing. 
You've patiently waited for <%= appName %>, but if you 
<a href='https://twitter.com/intent/tweet?text=<%= tweetText %>'>tweet this link</a> before you 
start, 5 of your friends won't have to &mdash; they'll get to skip the line.</p>
<p>Should your friends benefit from your patience? We'll let you decide.</p>

<p><a href='<%= redirectUrl %>'>Get started using <%= appName %></a></p>

<p>Welcome, we hope you love what we've built!<br />
The <%= appName %> Team</p>
"
