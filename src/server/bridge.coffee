net = require('net')
events = require('events')
_ = require('underscore')
Fiber = require('fibers')
async = require('async')

class Bridge extends events.EventEmitter
	constructor : (@translator) ->
		@objects = {}		

	init: (transport,done) ->
		@transport = transport
		transport.on 'close', => @emit 'close'
		done()

	send : (args...,cb) -> @transport.send(args...,cb)
	read : (target,field,cb) -> @send target, 'read', field, cb
	write : (target,field,value,cb) -> @send target, 'write', field, value, cb
	exec : (target,command,cb) -> @send target, 'exec', command..., cb
	list : (cmd,classId,cb) -> @send classId, cmd, (result) -> cb(_.without result.split(','), '')

	getSuperClassOfClass : (classId,cb) ->
		@send classId, 'super', (superClassId) =>			
			o = @objects[superClassId]			
			if o or superClassId is "None"
				cb(o)
			else
				@readClass superClassId, cb
	readClass : (classId,cb) ->		
		@getSuperClassOfClass classId, (superClass) =>						
			adaptor = (cb) -> (result) -> cb(null,result)
			async.parallel [
				(cb) => @read classId,'name', adaptor(cb)
				(cb) => @list 'listprop', classId, adaptor(cb)
				(cb) => @list 'listfunc', classId, adaptor(cb)
			], (err,results) =>
				if err
					cb err,results
				else
					[className,props,funcs] = results					
					cb new Class(@,classId,className,superClass,props,funcs)					
	getClass : (id,cb) ->
		@send id,'class', (classId) =>
			cls = @objects[classId]
			if cls
				cb(cls) 
			else	
				@readClass classId,cb
		
	access : (id,cb) ->				
		o = @objects[id]
		if o
			cb(o)
		else
			@getClass id, (result) =>
				cb @create(result,id)		

	create : (classObject,id) -> 
		o = new classObject.hostObjectClass(@,id)
		@objects[id] = o
		o

class Object
	constructor : (@bridge,@id,@classObject) ->				

	# if cb is null and running within a fiber, call would be blocked! 
	would_block : (body,cb) ->
		unless _.isFunction(cb)						
			fiber = Fiber.current
			if fiber
				out_result = null
				done = false
				waiting = false

				# body function can exit immediately
				body (result) ->
					out_result = result

					# mark we're done
					done = true		

					# if we are waiting, resume the fiber		
					fiber.run() if waiting			

				# if body didnt' exit, pause the fiber!
				unless done
					waiting = true
					Fiber.yield()

				out_result
			else
				throw "callback should be specified outside a fiber"
		else
			body(cb)

	# low-level accessor
	read : (field,cb) ->
		body = (cb) =>
			@bridge.read @id, field, (result) =>				
				@bridge.translator.from(result,@bridge,cb)
				
		@would_block body, cb

	# low-level accessor
	write : (field,value,cb) -> 
		body = (cb) =>
			@bridge.write @id, field, @bridge.translator.to(value), cb

		@would_block body, cb

	# low-level accessor
	exec : (command,cb) -> 
		body = (cb) =>
			@bridge.exec @id, command, (result) =>
				@bridge.translator.from(result,@bridge,cb)

		@would_block body, cb

class Class extends Object
	constructor : (@bridge, @id,@name,@superClass,@props,@funcs) ->		
		super @bridge, @id, null	

		self = @

		# this is the real reflected class!
		BaseClass = @superClass?.hostObjectClass or Object
		class HostObject extends BaseClass
			constructor : (@bridge, @id, @classObject = self) ->
			toString : -> @id

		@hostObjectClass = HostObject				

		# declare methods and properties within its prototype
		@declareMethodsAndProperties(@hostObjectClass.prototype)

	declareMethodsAndProperties : (target) ->		
		for prop in @props			
			do (prop) ->
				target.__defineGetter__ prop, -> @read prop
				target.__defineSetter__ prop, (value) -> @write prop, value

		for func in @funcs
			do (func) ->				
				target[func] = (args...) ->
					args = args.map @bridge.translator.to
					@exec [func,args...]

class Hosts extends events.EventEmitter
	constructor: (@opts)->		
		@bridges = []

	connect: (opts) ->		
		reconnect = =>
			console.log 'trying to reconnect'
			setTimeout (=> @connect opts), 1000
		
		host = opts?.host or "localhost"
		port = opts?.port or 1337
		trans = opts?.transport or "text"

		transportClass = @opts.transport[trans]
		throw "unsupported transport" unless transportClass

		client = net.connect {host:host,port:port}, =>
			transport = new transportClass(client)
			transport.send 'helo', (result) =>
				bridgeClass = @opts.bridge[result]
				unless bridgeClass
					transport.send 'unsupported bridge type'
					client.close()
					throw "Unsupported"

				bridge = new bridgeClass()
				bridge.opts = {host:host,port:port,transport:trans}
				bridge.init transport, =>
					console.log 'connected'
					@bridges.push bridge			

					bridge.on 'close', =>
						@bridges = _.without @bridges, bridge
						@emit 'disconnect', bridge

					@emit 'connect', bridge

		client.on 'error', (err) =>			
			reconnect()
		

exports.Hosts = Hosts					
exports.Bridge = Bridge
exports.Object = Object