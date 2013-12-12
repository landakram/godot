express = require 'express'
http = require 'http'
routes = require './routes'

app = express()

app.configure ->
    app.set "port", process.env.PORT or 4000
    app.set 'apiKey', process.env.API_KEY or '4747'
    app.use express.favicon()
    app.use express.logger('dev')
    app.use express.bodyParser()
    app.use express.methodOverride()
    app.use app.router

app.configure 'development', ->
    app.use express.errorHandler()

app.post '/reserve', routes.reserveSpot
app.get '/check', routes.checkSpot
app.post '/open/sesame', routes.openSesame

http.createServer(app).listen app.get('port'), ->
    console.log "Listening on port #{app.get('port')}"
