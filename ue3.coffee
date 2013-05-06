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

	