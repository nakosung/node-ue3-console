	# client-side 
# angular.js 

app = angular.module('node',['ui','ui.bootstrap'])

app.directive 'xychart', ->
	margin = 20
	width = 200
	height = 200 - .5 - margin
	color = d3.interpolateRgb("#f77","#77f")

	restrict: 'E'
	terminal: true
	scope:
		val:'='
	link:(scope,element,attrs)->
		vis = d3.select(element[0])
			.append('svg')
			.attr('width', width)
			.attr('height', height + margin + 100)

		watchBody = (newVal,oldVal) ->			
			vis.selectAll('*').remove()			

			xx = _.pluck(newVal,'x').map parseFloat
			yy = _.pluck(newVal,'y').map parseFloat			

			x = d3.scale.linear().domain([d3.min(xx),d3.max(xx)]).range([0,width])
			y = d3.scale.linear().domain([d3.min(yy),d3.max(yy)]).range([height,0])			

			line = d3.svg.line()
				.x((d)->parseFloat x(d.x))
				.y((d)->parseFloat y(d.y))

			vis.append('svg:path').attr('d',line(newVal))

		scope.$watch 'val', watchBody,true


app.factory 'node', ($rootScope) ->		
	class Server
		constructor : ->			
			@plot = []
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
			@print 'Connected to node.js'
			@send list:null						
			@send hosts:null
			
			@sock.onmessage = (e) =>
				data = JSON.parse(e.data)
				for k,v of data
					switch k
						when "refresh" then window.location.reload() 
						when "log" 			
							plotted = false
							try				
								o = JSON.parse(v)
								if o.plot								
									@plot.push(o.plot) 									
									plotted = true
							catch e
							@print v unless plotted
						when "code", "title", "active", "list", "hosts", "host" then @[k] = v
						when "invalidated" then @send list:null						
				@updateAngularJs()				

		refresh : -> window.location.refresh()
		send : (json) -> @sock.send JSON.stringify(json)
		load : (target) -> @send {load:target}		
		discard : (target) -> @send {discard:target}
		save : -> @send {save:{code:@code,title:@title}}
		run : -> 
			@plot = []
			@updateAngularJs()
			@send {run:this.code}
		print : (msg) ->	
			console.log msg
			@logs += msg + "\n"
			@updateAngularJs()

	new Server()

app.controller 'CodeCtrl', ($scope,node) ->
	$scope.server = node		
	$scope.status = ->
		if node.online then "ONLINE" else "OFFLINE"
	
	# I couldn't make this key binding to work with angular-ui
	$(document).keydown (e) ->		
		if e.keyCode == 66 and e.ctrlKey
			node.run()
			false
		
		if e.keyCode == 83 and e.ctrlKey
			node.save()
			false
