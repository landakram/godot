url = require 'url'

exports.absoluteUrlForPath = (req, path) ->
    absoluteUrl = {
        protocol: req.protocol,
        hostname: req.host,
        port: req.app.settings.port,
        pathname: path
    }
    url.format absoluteUrl
