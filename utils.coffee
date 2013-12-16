url = require 'url'

exports.absoluteUrlForPath = (req, path) ->
    absoluteUrl = {
        protocol: req.protocol,
        hostname: req.host,
        port: req.app.settings.port,
        pathname: path
    }
    if process.env.NODE_ENV is 'production'
        absoluteUrl.host = req.host
    url.format absoluteUrl
