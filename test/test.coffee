request = require 'supertest'
express = require 'express'
app = require '../app'
models = require '../models'
client = models.client

describe 'POST /u/reserve', ->
    before (done) ->
        client.flushdb (err, val) ->
            if err then done err else done()

    it 'should return json', (done) ->
        app.set 'enabled', true
        request(app)
            .post('/u/reserve')
            .expect('Content-Type', /json/)
            .expect(200, done)

    it 'should reserve an initial user', (done) ->
        app.set 'enabled', true
        request(app)
            .post('/u/reserve')
            .expect(/\"rank\": 1/, done)
            .expect(/\"waiting\": true/, done)

    it 'should increment the user count', (done) ->
        app.set 'enabled', true
        request(app)
            .post('/u/reserve')
            .expect(/\"rank\": 2/, done)

    it 'should give me a referral link', (done) ->
        app.set 'enabled', true
        request(app)
            .post('/u/reserve')
            .expect(/\"referralLink\": \"http/, done)

    it 'should give me an invite link', (done) ->
        app.set 'enabled', true
        request(app)
            .post('/u/reserve')
            .expect(/\"inviteLink\": \"http/, done)

    it 'should not be waiting when disabled', (done) ->
        app.set 'enabled', false
        request(app)
            .post('/u/reserve')
            .expect(/\"rank\": null/, done)
            .expect(/\"waiting\": false/, done)
