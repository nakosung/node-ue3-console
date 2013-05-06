events = require('events')
_ = require('underscore')
Fiber = require('fibers')
async = require('async')
redis = require('redis')
fs = require('fs')
redisClient = redis.createClient()
coffeescript = require('coffee-script')

class ClientSideFiles extends events.EventEmitter
	constructor: ->
		tell = (e,f) =>
			if e
				console.log 'client file changed', e, f
				@emit 'change'
		fs.watch 'lib', tell
		fs.watch 'public', tell

clientFiles = new ClientSideFiles()

main = (bridge,main_cb) ->
	wko_names = 'LocalPC WorldInfo'
	wko = {}

	sequence = wko_names.split(' ').map (k) ->
		(cb) ->
			console.log 'querying wko!'
			bridge.access k, (o) ->
				wko[k] = o
				cb()

	class CodeDepot extends events.EventEmitter
		load : (key,cb) ->			
			async.parallel [
				(cb) -> redisClient.get "code-#{key}", cb,
				(cb) -> redisClient.get "title-#{key}", cb
			], (err,result) ->
				console.log result
				if err
					cb(err,result)
				else				
					[code,title] = result
					cb(null,{code:code,title:title or "untitled"})

		discard : (key,cb) ->			
			redisClient.lrem "code-list", 0, key			
			redisClient.del "code-#{key}"
			redisClient.del "title-#{key}"
			@emit 'invalidate'
			cb(null,null)

		save : (doc,cb) ->
			sha1 = require('sha1')
			key = sha1(doc.code)					
			redisClient.set "code-#{key}", doc.code
			redisClient.lrem "code-list", 0, key
			redisClient.lpush "code-list", key
			redisClient.set "title-#{key}", doc.title
			@emit 'invalidate'
			cb(null,key)

		delete : (key,cb) ->
			redisClient.lrem "code-list", 0, key
			@emit 'invalidate'
			cb()

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

	class SharedDevice extends events.EventEmitter
		log : (text) ->
			@emit 'data', text

	sharedDevice = new SharedDevice()

	depot = new CodeDepot()

	handler = (msg,cb) ->
		sleep = (msec) ->
			fiber = Fiber.current
			setTimeout (-> fiber.run()), msec			
			Fiber.yield()
		
		for k,v of msg			
			switch k		
				when 'run' 
					result = null			
					sandbox = 
						WorldInfo:wko.WorldInfo
						pc:wko.LocalPC
						access:(x) -> bridge.access(x)																				
						log:(args...) -> sharedDevice.log args.toString()
						sleep:(ms) -> sleep(ms)
					try
						result = String(coffeescript.eval(v,{sandbox:sandbox}))
					catch e						
						result = e.toString()
					cb null, {log:result}

				when 'save'
					depot.save v, (key) ->
						cb null, {log:"code saved",active:key}

				when 'discard' then depot.discard v, cb

				when 'load'
					depot.load v, (err,result) ->						
						if err 
							cb(err,result)
						else
							cb(null,{code:result.code,title:result.title,active:v})

				when 'delete'
					depot.delete v, (err,result) ->
						cb(err,{log:result})

				when 'list'
					depot.list v, (err,result) ->
						if err
							cb(err,result)
						else							
							cb(null,{list:result})

	async.waterfall sequence, ->		
		express = require('express')
		sockjs = require('sockjs')
		app = express()
		echo = sockjs.createServer()
		echo.on 'connection', (conn) ->
			send = (json) -> conn.write JSON.stringify(json)

			updateCodeList = -> send {invalidated:true}
			closeConnection = -> 
				send refresh:true
				conn.close()
			log = (text) -> send log:text			

			depot.on 'invalidate', updateCodeList			
			clientFiles.once 'change', closeConnection
			sharedDevice.on 'data', log

			conn.on 'close', ->
				sharedDevice.removeListener 'data', log
				clientFiles.removeListener 'change', closeConnection
				depot.removeListener 'invalidate', updateCodeList

			conn.on 'data', (msg) ->
				clientMain = ->					
					console.log 'received msg', msg					
					handler JSON.parse(msg), (err,result) ->
						if err
							send {log:err}
						else
							send result

				Fiber(clientMain).run()

		app = express()
		app.use '/', express.static(__dirname+'/public')
		app.use '/lib', express.static(__dirname+'/lib')

		http = require('http')
		server = http.createServer app
		echo.installHandlers server, {prefix:'/echo'}
		server.listen 3338

		console.log "SERVER STARTED"

		# when connection to unreal engine3 is lost, we're terminating the server and try to restart
		bridge.on 'close', -> server.close main_cb



ue3 = require('./ue3')

stub = ->
	ue3.init (err,bridge) ->
		if err
			console.log 'error occurred, retrying!!!'
			setTimeout (-> stub()), 1000
		else
			main bridge, ->
				console.log 'connection lost, retrying!!!'
				setTimeout (-> stub()), 1000

stub()