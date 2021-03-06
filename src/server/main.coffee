events = require('events')
_ = require('underscore')
Fiber = require('fibers')
async = require('async')
{CodeDepot} = require('./depot')
{Bridge,Hosts,Object} = require('./bridge')
vm = require('vm')

class ClientSideFiles extends events.EventEmitter
	constructor: ->
		fs = require('fs')

		tell = (e,f) =>
			if e
				console.log 'client file changed', e, f
				@emit 'change'
		fs.watch 'lib/client', tell
		fs.watch 'public', tell

clientFiles = new ClientSideFiles()

class RichBridge extends Bridge
	constructor:->
		super require './ue3prim'

	init:(client,done) ->
		super client, =>
			wko_names = 'LocalPC WorldInfo'
			wko = {}

			sequence = wko_names.split(' ').map (k) =>
				(cb) =>					
					@access k, (o) ->
						wko[k] = o
						cb()	

			async.parallel sequence, =>
				@sandbox = 
					WorldInfo:wko.WorldInfo
					pc:wko.LocalPC
					_:_
					access:(x) => @access(x)																				
					log:(args...) => @log args.toString()
					sleep:(ms) => sleep(ms)				
					inspect:(v) =>
						val = String(v)
						meta = {}						
						if v instanceof Object
							meta.type = v.classObject?.name
							for prop in v.classObject?.props
								meta[prop] = String(v[prop])						
						val:val
						meta:meta
					chart:(x,y) => 
						unless y
							y = x
							x = wko.WorldInfo.TimeSeconds
						@log JSON.stringify plot:{x:x,y:y}

				done()

	name : -> 		
		"#{@translator.name} #{@opts.transport}:#{@opts.host}:#{@opts.port}"

	log : (text) ->
		@emit 'data', text
	
	runScriptInFiber : (v,cb) ->
		health = true	

		sandbox = _.clone(@sandbox)

		# to kill timer immediately, we keep timer and fiber objects locally.
		timer = fiber = null

		sandbox.sleep = (msec) ->
			# save fiber and timer for halting the timer!
			fiber = Fiber.current
			timer = setTimeout (-> fiber.run()), msec

			# we now go to sleep.
			Fiber.yield()

			# clearing is always good. :)
			timer = fiber = null

			# we're interrupted?
			throw "User halted" unless health

		result = null
		
		fiberMain = =>			
			try
				result = String(vm.runInNewContext(v,sandbox))
			catch e						
				result = "Exception:#{e.toString()}"
			cb null, {log:result}

		Fiber(fiberMain).run()

		# to halt execution, stop method is provided. :)
		stop: ->
			# tell them we are sick.
			health = false

			# if we have a running timer?
			if timer
				# clear the timer
				clearTimeout timer 

				# and resume the fiber
				fiber.run()

class Transport extends events.EventEmitter
	constructor:(@client) ->
		@trid = 0
		@buffer = ""

		# packet may be split
		@client.on 'data', (data) =>
			@buffer += data.toString()			
			while true
				str = @getLine()
				break unless str

				i = str.indexOf(' ')
				trid = parseInt(str.substr(0,i))
				@emit trid, str.substr(i+1)

		@client.on 'close', => @emit 'close'

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

		@once my_trid, cb 
		@client.write buf

hosts = new Hosts 
	bridge:
		UnrealEngine3:RichBridge
	transport:
		text:Transport

depot = new CodeDepot()

connections = []

class ClientConnection
	constructor : (@conn) ->
		connections.push @		

		@watches = []
		@watchValues = {}

		updateCodeList = => @send {invalidated:true}
		closeConnection = => 
			@send refresh:true
			@conn.close()		
		
		clientFiles.once 'change', closeConnection
		depot.on 'invalidate', updateCodeList

		invalidateHosts = =>			
			@setBridge null unless @bridge
			@send {hosts:@getHostList()}

		hosts.on 'connect', invalidateHosts
		hosts.on 'disconnect', invalidateHosts
		
		@conn.on 'close', =>
			@setBridge null
			hosts.removeListener 'connect', invalidateHosts
			hosts.removeListener 'disconnect', invalidateHosts
			clientFiles.removeListener 'change', closeConnection
			depot.removeListener 'invalidate', updateCodeList
			connections = _.without connections, @

		@conn.on 'data', (msg) =>
			console.log 'received msg', msg					
			@handleMessage JSON.parse(msg), (err,result) =>
				if err
					@send {log:err}
				else
					@send result				

		@setBridge null
		hosts.on 'connect', =>			
			@setBridge null unless @bridge

	setBridge : (new_bridge) ->
		new_bridge ?= hosts.bridges[0]
		
		log = (text) => @send log:text			

		@bridge.removeListener 'data', log if @bridge
		@bridge = new_bridge
		if @bridge
			@bridge.on 'data', log 
			@bridge.on 'close', =>
				@setBridge null

		@send 
			host:@bridge?.name() or null			


	send : (json) -> @conn.write JSON.stringify(json)

	handleMessage : (msg,cb) ->		
		for k,v of msg			
			switch k		
				when 'run' 
					if @bridge
						@send {running:true}
						try
							code = require('coffee-script').compile(v)
							@script = @bridge.runScriptInFiber code, (err,result) =>
								@script = null
								@send {running:false}
								cb(err,result)
						catch e
							cb e.error

					else
						cb('no connection')

				when 'inspect'
					if @bridge
						code = "JSON.stringify(inspect(#{v.target}))"
						try							
							@bridge.runScriptInFiber code, (err,result) =>								
								cb null, inspect:{id:v.id,err:err,result:result?.log}
						catch e
							cb e.error
					else
						cb('no connection')

				when 'stop'
					@script.stop() if @script

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

				when 'list'
					depot.list v, (err,result) ->
						if err
							cb(err,result)
						else							
							cb(null,{list:result})			

				when 'hosts'					
					cb(null,{hosts:@getHostList()})		

				when 'host'
					i = @getHostList().indexOf(v)
					if i >= 0
						@setBridge hosts.bridges[i]
						cb(null,{log:'switching host...'})
					else
						cb('invalid host')				

				when 'watch'
					i = @watches.indexOf v
					if i < 0
						@watches.push v
					cb(null,"ok")

				when 'unwatch'
					@watches = _.without @watches, v
					cb(null,"ok")

	tick : ->
		if @bridge
			for watch in @watches
				do (watch) =>
					@bridge.runScriptInFiber "#{watch}", (err,result) =>
						value = result.log
						if @watchValues[watch] != value
							@watchValues[watch] = value
							@send watch:{key:watch,val:value}

	getHostList : ->
		hosts.bridges.map (x)->x.name()

express = require('express')
sockjs = require('sockjs')

app = express()		
app.use '/', express.static('public')
app.use '/lib', express.static('lib/client')

# workaround for sock.js + express impedence mismatch
server = require('http').createServer app

echo = sockjs.createServer()
echo.on 'connection', (conn) -> new ClientConnection(conn)
echo.installHandlers server, {prefix:'/echo'}

server.listen 3338

# trying to connect local unreal engine3
getAddresses = ->
	os = require('os')

	interfaces = os.networkInterfaces()
	addresses = []
	for k,v of interfaces
	    for address in v
	        if address.family == 'IPv4' and not address.internal
	            addresses.push(address.address)
	addresses
	        
console.log getAddresses()	      
hosts.connect port:1336, transport:'text'

setInterval (->
	for connection in connections
		connection.tick()
	), 100

