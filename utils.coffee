url = require 'url'
Bitly = require 'bitly'
sys = require 'sys'

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

exports.shortenUrl = (url, callback) ->
    if process.env.NODE_ENV is 'development'
        callback null, url
    else
        bitly = new Bitly process.env.BITLY_USER, process.env.BITLY_API_KEY
        bitly.shorten url, (err, response) ->
            if err then callback err else callback null, response.data.url
