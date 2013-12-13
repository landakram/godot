express = require 'express'
http = require 'http'
routes = require './routes'

app = express()

app.configure ->
    app.set "port", process.env.PORT or 4000
    app.set 'apiKey', process.env.API_KEY or '4747'
    app.set 'externalRedirectURL', process.env.EXTERNAL_REDIRECT_URL or 'http://www.google.com'
    app.use express.favicon()
    app.use express.logger('dev')
    app.use express.bodyParser()
    app.use express.methodOverride()
    app.use express.cookieParser(process.env.SECRET or 'secret')
    app.use express.cookieSession()
    app.use app.router

app.configure 'development', ->
    app.use express.errorHandler()

app.get '/u/reserve', routes.reserveSpot
app.post '/u/email/set', routes.setEmail
app.get '/u/check', routes.checkSpot

app.post '/r/create', routes.getReferralLink
app.get '/r/:referralID', routes.trackReferral

app.post '/open/sesame', routes.openSesame

http.createServer(app).listen app.get('port'), ->
    console.log "Listening on port #{app.get('port')}"
