events = require('events')
_ = require('underscore')
Fiber = require('fibers')
async = require('async')
{CodeDepot} = require('./depot')
fs = require('fs')
{Bridge,Hosts} = require('./ue3')

class ClientSideFiles extends events.EventEmitter
	constructor: ->
		tell = (e,f) =>
			if e
				console.log 'client file changed', e, f
				@emit 'change'
		fs.watch 'lib/client', tell
		fs.watch 'public', tell

clientFiles = new ClientSideFiles()

class RichBridge extends Bridge
	init:(client,done) ->
		super client, =>
			wko_names = 'LocalPC WorldInfo'
			wko = {}

			sequence = wko_names.split(' ').map (k) =>
				(cb) =>
					console.log 'querying wko!'
					@access k, (o) ->
						wko[k] = o
						cb()	

			async.parallel sequence, =>
				sleep = (msec) ->
					fiber = Fiber.current
					setTimeout (-> fiber.run()), msec			
					Fiber.yield()

				@sandbox = 
					WorldInfo:wko.WorldInfo
					pc:wko.LocalPC
					access:(x) => @access(x)																				
					log:(args...) => @log args.toString()
					sleep:(ms) => sleep(ms)				

				done()

	log : (text) ->
		@emit 'data', text

	runCoffeeScriptInFiber : (v,cb) ->
		coffeescript = require('coffee-script')

		result = null						
		
		fiberMain = =>
			try
				result = String(coffeescript.eval(v,{sandbox:_.clone(@sandbox)}))
			catch e						
				result = e.toString()
			cb null, {log:result}

		Fiber(fiberMain).run()

hosts = new Hosts(RichBridge)
depot = new CodeDepot()

connections = []

class ClientConnection
	constructor : (@conn) ->
		connections.push @		

		updateCodeList = => @send {invalidated:true}
		closeConnection = => 
			@send refresh:true
			@conn.close()		
		
		clientFiles.once 'change', closeConnection
		depot.on 'invalidate', updateCodeList
		
		@conn.on 'close', =>
			@setBridge null
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

		@setBridge hosts.bridges[0]		
		hosts.on 'connect', =>			
			@setBridge null unless @bridge

	setBridge : (new_bridge) ->
		log = (text) => @send log:text			

		@bridge.removeListener 'data', log if @bridge
		@bridge = new_bridge
		if @bridge
			@bridge.on 'data', log 
			@bridge.on 'close', =>
				@setBridge null

	send : (json) -> @conn.write JSON.stringify(json)

	handleMessage : (msg,cb) ->		
		for k,v of msg			
			switch k		
				when 'run' 
					if @bridge
						@bridge.runCoffeeScriptInFiber(v,cb) 
					else
						cb('no connection')

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
hosts.connect port:1336


