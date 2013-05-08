_ = require('underscore')
events = require('events')
async = require('async')
redis = require('redis')
redisClient = redis.createClient()
redisClient.on 'error', ->
	console.error 'redis is not accessible, please run redis at localhost'

class CodeDepot extends events.EventEmitter
	load : (key,cb) ->			
		async.parallel [
			(cb) -> redisClient.get "code-#{key}", cb,
			(cb) -> redisClient.get "title-#{key}", cb
		], (err,result) =>			
			if err
				cb(err,result)
			else				
				[code,title] = result
				cb(null,{code:code,title:title or "untitled"})

	discard : (key,cb) ->			
		async.parallel [
			(cb) -> redisClient.lrem "code-list", 0, key, cb
			(cb) -> redisClient.del "code-#{key}", cb
			(cb) -> redisClient.del "title-#{key}", cb
		], (err,result) =>
			@emit 'invalidate'
			cb(null,null)

	save : (doc,cb) ->
		sha1 = require('sha1')
		key = sha1(doc.code)					
		async.parallel [
			(cb) -> redisClient.set "code-#{key}", doc.code, cb
			(cb) -> redisClient.lrem "code-list", 0, key, cb
			(cb) -> redisClient.lpush "code-list", key, cb
			(cb) -> redisClient.set "title-#{key}", doc.title or "untitled", cb
		], (err,result) =>			
			@emit 'invalidate'
			cb(null,key)	

	list : (options,cb) ->
		start = options?.start or 0
		end = options?.end or 10
		redisClient.lrange "code-list", start, end, (err,ids) ->
			if err
				cb(err,ids)
			else
				async.map ids, ((key,cb) -> redisClient.get "title-#{key}", cb), (err,titles) ->
					if err
						cb(err,titles)
					else
						cb null, _.zip(ids,titles).map (x) -> 
							[id,title] = x
							id:id
							title:title or "untitled"

exports.CodeDepot = CodeDepot