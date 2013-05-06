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
			redisClient.set "title-#{key}", doc.title or "untitled"
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
					
					fiberMain = ->
						try
							result = String(coffeescript.eval(v,{sandbox:sandbox}))
						catch e						
							result = e.toString()
						cb null, {log:result}

					Fiber(fiberMain).run()										

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
				console.log 'received msg', msg					
				handler JSON.parse(msg), (err,result) ->
					if err
						send {log:err}
					else
						send result				

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


net = require('net')
events = require('events')
_ = require('underscore')
Fiber = require('fibers')
async = require('async')
ue3prim = require './ue3prim'

# if cb is null and running within a fiber, call would be blocked! 
fiber_exec = (body,cb) ->
	unless _.isFunction(cb)						
		fiber = Fiber.current
		if fiber
			out_result = null
			done = false
			waiting = false
			body (result) ->
				out_result = result
				done = true				
				fiber.run() if waiting			
			waiting = true
			Fiber.yield() unless done			
			out_result
		else
			null
	else
		body(cb)

class Bridge extends events.EventEmitter
	constructor : (@trid=0) ->
		@objects = {}
		@buffer = ""

	init: (client) ->
		@client = client

		# packet may be split
		client.on 'data', (data) =>
			@buffer += data.toString()			
			while true
				str = @getLine()
				break unless str
				i = str.indexOf(' ')
				trid = parseInt(str.substr(0,i))
				@emit trid, str.substr(i+1)

		client.on 'close', =>
			@emit 'close'

	getLine : ->
		i = @buffer.indexOf("\r\n")
		if i<0
			null
		else
			result = @buffer.substr(0,i)
			@buffer = @buffer.substr(i+2)
			result

	send : (args...,cb) ->
		command = args.join(' ')
		my_trid = @trid++
		buf = "#{my_trid} #{command}\r\n"

		body = (cb) =>			
			@once my_trid, cb 
			@client.write buf	

		fiber_exec body, cb

	read : (target,field,cb) -> @send target, 'read', field, cb
	write : (target,field,value,cb) -> @send target, 'write', field, value, cb
	exec : (target,command,cb) -> @send target, 'exec', command, cb
	getSuperClassOfClass : (classId,cb) ->
		@send classId, 'super', (superClassId) =>			
			o = @objects[superClassId]			
			if o or superClassId is "#-1"
				cb(o)
			else
				@readClass superClassId, cb
	readClass : (classId,cb) ->		
		@getSuperClassOfClass classId, (superClass) =>						
			adaptor = (cb) -> (result) -> cb(null,result)
			async.parallel [
				(cb) => @read classId,'name', adaptor(cb)
				(cb) => @send classId, 'listprop', adaptor(cb)
				(cb) => @send classId, 'listfunc', adaptor(cb)
			], (err,results) =>
				[className,props,funcs] = results
				props = props.split(',')
				funcs = funcs.split(',')
				cls = new Class(classId,className,superClass,props,funcs)
				cb(cls)
	getClass : (id,cb) ->
		@send id,'class', (classId) =>
			cls = @objects[classId]
			if cls
				cb(cls) 
			else	
				@readClass classId,cb
		
	access : (id,cb) ->
		body = (cb) =>
			if (id == "#-1")
				cb(null)
			else
				o = @objects[id]
				if o
					cb(o)
				else
					@getClass id, (result) =>
						cb @create(result,id)
		fiber_exec body, cb

	create : (classObject,id) -> 
		o = new classObject.UEObjectClass(id)				
		@objects[id] = o
		o

bridge = new Bridge()

class Object
	constructor : (@id,@class) ->				

	# low-level accessor
	read : (field,cb) ->
		body = (cb) =>
			bridge.read @id, field, (result) ->
				ue3prim.from(result,bridge,cb)
				
		fiber_exec body, cb

	# low-level accessor
	write : (field,value,cb) -> bridge.write @id, field, ue3prim.to(value), cb

	# low-level accessor
	exec : (command,cb) -> bridge.exec @id, command, cb

class Class extends Object
	constructor : (@id,@name,@superClass,@props,@funcs) ->		
		super @id, null	

		self = @

		# this is the real reflected class!
		BaseClass = @superClass?.UEObjectClass or Object
		class UEObject extends BaseClass
			constructor : (@id, @class) ->

		@UEObjectClass = UEObject				

		# declare methods and properties within its prototype
		@declareMethodsAndProperties(@UEObjectClass.prototype)

	declareMethodsAndProperties : (target) ->
		for prop in @props			
			do (prop) ->
				target.__defineGetter__ prop, -> @read prop
				target.__defineSetter__ prop, (value) -> @write prop, value

		for func in @funcs
			do (func) ->				
				target[func] = (args...) ->
					args = args.map ue3prim.to
					@exec [func,args.join(' ')].join(' ')

exports.init = (cb) ->
	client = net.connect {port:1336}, ->	
		console.log 'connected'
		bridge.init(client)	
		cb(null,bridge)

	client.on 'error', (err) ->
		cb(err)

	
_ = require('underscore')

# primitives
class UEPrim
	export:-> throw "NOTIMPL"

class Vector3 extends UEPrim
	constructor:(@X,@Y,@Z) ->
	export:->
		"(X={@X},Y={@Y},Z={@Z})"

from_unrealengine3 = (text,bridge,cb) ->
	if text[0] == '#'
		bridge.access text, (o) ->						
			cb(o)
	else
		num = parseFloat(text) 
		if _.isNaN(num)
			vec3 = /\(X=([0-9]+\.[0-9]+),Y=([0-9]+\.[0-9]+),Z=([0-9]+\.[0-9]+)\)/.exec(text)
			console.log vec3
			if vec3
				cb new Vector3(parseFloat(vec3[1]),parseFloat(vec3[2]),parseFloat(vec3[3]))
			else
				cb(text)
		else 			
			cb(num)

to_unrealengine3 = (value) ->
	if value instanceof UEPrim
		value.export()
	else
		value

exports.from = from_unrealengine3
exports.to = to_unrealengine3