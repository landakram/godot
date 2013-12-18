Q = require 'q'
models = require '../models'
utils = require '../utils'
User = models.User

exports.reserveSpot = (req, res) ->
    referralID = req.session.referrer
    referDeferred = Q.defer()
    inviteID = req.session.inviter
    inviteDeferred = Q.defer()
    if inviteID?
        User.getByInviteID inviteID, (invitingUser) ->
            # Only count the invite if the inviting user has invites left
            if invitingUser? and invitingUser.info.invites > 0
                invitingUser.incrementInvites -1
                inviteDeferred.resolve(invitingUser)
            else
                inviteDeferred.resolve {error: 'expired'}
    else
        inviteDeferred.resolve()

    if referralID?
        inviteDeferred.promise.then (invitingUser) ->
            # If the user was invited, then we don't worry about referrals
            if invitingUser? and not invitingUser.error
                referDeferred.resolve()
            # Otherwise, do the referral stuff
            else
                User.getByReferralID referralID, (referringUser) ->
                    referDeferred.resolve(referringUser)
                    if referringUser then referringUser.redeemReferral()
        .done()
    else
        referDeferred.resolve()

    createUserAndSendResponse = (waiting) ->
        User.create waiting, (user) ->
            lengthPromise = User.waitingListLength()

            refLinkDeferred = Q.defer()
            inviteLinkDeferred = Q.defer()

            # Generate referral and invite links
            user.getReferralLink req, (err, link) ->
                if err? then refLinkDeferred.reject(err) else refLinkDeferred.resolve(link)
            user.getInviteLink req, (err, link) ->
                if err? then inviteLinkDeferred.reject(err) else inviteLinkDeferred.resolve(link)

            # Calculate the user's position the waiting list
            user.getRank (rank) ->
                # When everything is loaded, return the user
                Q.all([inviteDeferred.promise, referDeferred.promise,
                       refLinkDeferred.promise, inviteLinkDeferred.promise])
                .spread (invitingUser, referringUser, referralLink, inviteLink) ->
                    user.info.referredBy = referralID if referringUser?
                    user.info.invitedBy = inviteID if invitingUser? and not invitingUser.error
                    user.info.invites = 3
                    user.saveInfo()
                    req.session.id = user.id
                    req.session.referrer = null

                    data = {
                        id: user.id, rank: rank, waiting: waiting,
                        projectedSharingRank: user.projectedSharingRank,
                        referralLink: referralLink,
                        inviteLink: inviteLink,
                        referred: true if referringUser?,
                        invited: true if invitingUser? and not invitingUser.error,
                        error: invitingUser.error if invitingUser?
                    }
                    if waiting
                        lengthPromise.then (length) ->
                            data.waitingListLength = length
                            res.json data
                    else
                        res.json data

                .done()

    waiting = req.app.get('enabled')
    if not waiting
        createUserAndSendResponse(waiting)
    else
        inviteDeferred.promise.then (invitingUser) ->
            waiting = false if invitingUser? and not invitingUser.error
            createUserAndSendResponse(waiting)
        .done()

exports.checkSpot = (req, res) ->
    lengthPromise = User.waitingListLength()
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.getRank (rank) ->
                waiting = true
                if user.list is User.GRANTED_LIST_KEY then waiting = false
                data = {
                    id: user.id,
                    rank: rank,
                    waiting: waiting,
                    projectedSharingRank: user.projectedSharingRank
                }
                if waiting
                    lengthPromise.then (length) ->
                        data.waitingListLength = length
                        res.json data
                    .done()
                else
                    res.json data
                

exports.setEmail = (req, res) ->
    email = req.param('email')
    User.get req.param('id'), (user) ->
        if not user
            res.json 404, {error: 'User does not exist.'}
        else
            user.setEmail email, ->
                res.json {success: true}
