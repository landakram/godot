express = require 'express'
http = require 'http'
routes = require './routes'
client = require('./models').client

app = express()

app.configure ->
    app.set "port", process.env.PORT
    app.set 'apiKey', process.env.API_KEY
    app.set 'redirectURL', process.env.REDIRECT_URL
    app.set 'appName', process.env.APP_NAME
    app.set 'emailAddress', process.env.EMAIL_ADDRESS
    # Configure enabled from redis, then env, or just start enabled
    client.hget 'config', 'enabled', (err, val) ->
        if val?
            enabled = val is 'true'
            app.set 'enabled', enabled
        else
            app.set 'enabled', process.env.ENABLED or false
    app.use express.favicon()
    app.use express.logger('dev')
    app.use express.bodyParser()
    app.use express.methodOverride()
    app.use express.cookieParser(process.env.SECRET or 'secret')
    app.use express.cookieSession()
    app.use app.router

app.configure 'development', ->
    app.set 'apiKey', process.env.API_KEY or '4747'
    app.set "port", process.env.PORT or 4000
    app.set 'redirectURL', process.env.REDIRECT_URL or 'http://www.google.com'
    app.set 'appName', process.env.APP_NAME or 'Development app'
    app.set 'emailAddress', process.env.EMAIL_ADDRESS or 'dev@example.org'
    app.use express.cookieParser(process.env.SECRET or 'secret')
    app.use express.errorHandler()

# User
app.post '/u/reserve', routes.reserveSpot
app.post '/u/email/set', routes.setEmail
app.get '/u/check', routes.checkSpot

# Referrals
app.post '/r/create', routes.getReferralLink
app.get '/r/:referralID', routes.trackReferral

# Invitations
app.post '/i/create', routes.getInviteLink
app.get '/i/:inviteID', routes.trackInvite
app.post '/i/add', routes.incrementInvites

# Admin
app.post '/a/toggle', routes.toggleWaitingList
app.post '/a/open/sesame', routes.openSesame

http.createServer(app).listen app.get('port'), ->
    console.log "Listening on port #{app.get('port')}"
