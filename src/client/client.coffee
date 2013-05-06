# client-side 
# angular.js 

app = angular.module('node',['ui','ui.bootstrap'])

app.factory 'node', ($rootScope) ->		
	class Server
		constructor : ->			
			@code = "log 'Hello world'"
			@logs = "Connecting...\n"

			@handleConnectionLost()		

		updateAngularJs : ->			
			!$rootScope.$$phase && $rootScope.$apply()

		handleConnectionLost : ->
			@list = null
			@active = null
			@online = false

			@print "Trying to connect"			
			@sock = new SockJS('/echo')
			@sock.onopen = => @initSock()
			@sock.onclose = => @handleConnectionLost()			

		initSock : () ->	
			@online = true					
			@print 'Connected to UnrealEngine3'
			@send list:null						
			
			@sock.onmessage = (e) =>
				data = JSON.parse(e.data)
				for k,v of data
					switch k
						when "refresh" then window.location.reload() 
						when "log" then @print v
						when "code", "title", "active", "list" then @[k] = v
						when "invalidated" then @send list:null
				@updateAngularJs()

		refresh : -> window.location.refresh()
		send : (json) -> @sock.send JSON.stringify(json)
		load : (target) -> @send {load:target}		
		discard : (target) -> @send {discard:target}
		save : -> @send {save:{code:@code,title:@title}}
		run : -> @send {run:this.code}
		print : (msg) ->	
			console.log msg
			@logs += msg + "\n"
			@updateAngularJs()

	new Server()

app.controller 'CodeCtrl', ($scope,node) ->
	$scope.server = node		
	$scope.status = ->
		if node.online then "ONLINE" else "OFFLINE"

