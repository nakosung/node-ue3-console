	# client-side 
# angular.js 

app = angular.module('node',['ui','ui.bootstrap'])

# For chart :)
app.directive 'xychart', ->
	margin = 20
	width = 200
	height = 200 - .5 - margin	

	# this is an element!
	restrict: 'E'
	terminal: true

	# 'val' is the model :)
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

# to catch blur event
app.directive 'ngBlur', ['$parse', ($parse) ->
	(scope, element, attr) ->
    	fn = $parse(attr['ngBlur'])
    	element.bind 'blur', (event) ->
      		scope.$apply ->
        		fn(scope, {$event:event})      
]
 
# hover-only-visible :)
app.directive 'showonhoverparent', ->      
 	link : (scope, element, attrs) -> 		 		
        element.parent().bind 'mouseenter', -> element.show()
        element.parent().bind 'mouseleave', -> element.hide()
        element.hide()

# main proxy
app.factory 'node', ($rootScope) ->		
	class Server
		constructor : ->			
			@inspectId = 0
			@inspectCallbacks = {}
			@plot = []
			@watches = {}
			@code = "log 'Hello world'"
			@logs = "Connecting...\n"

			@handleConnectionLost()

		updateAngularJs : ->			
			!$rootScope.$$phase && $rootScope.$apply()

		handleConnectionLost : ->
			for k, v of @inspectCallbacks
				v('connection lost')
			@inspectCallbacks = {}
			@list = null
			@active = null
			@online = false
			@hosts = []
			@host = null

			@print "Trying to connect"			
			@sock = new SockJS('/echo')
			@sock.onopen = => @initSock()
			@sock.onclose = => setTimeout (=> @handleConnectionLost()), 250				

		initSock : () ->	
			@online = true					
			@print 'Connected to node.js'

			# first packet. grab list of codes, list of hosts and watch some expression
			@send {list:null,hosts:null,watch:'pc.Pawn.Location'}
			
			# message handler
			@sock.onmessage = (e) =>
				try
					data = JSON.parse(e.data)
					for k,v of data
						switch k
							when "refresh" then @refresh()

							when "log" 			
								plotted = false
								try				
									o = JSON.parse(v)
									if o.plot								
										@plot.push(o.plot) 									
										plotted = true
								catch e
								@print v unless plotted

							# just pass thru
							when "code", "title", "active", "list", "hosts", "host", "running" then @[k] = v

							# value of watch target changed
							when "watch" then @watches[v.key] = v.val

							# inspect!
							when "inspect"  
								try
									@inspectCallbacks[v.id]? v.err, JSON.parse(v.result)
								catch e
								delete @inspectCallbacks[v.id]

							# previous code-list was invalidated.
							when "invalidated" then @send list:null
				catch exception
					console.log exception, e

				@updateAngularJs()				

		inspect : (target,cb) ->
			iid = @inspectId++	
			@inspectCallbacks[iid] = cb		
			@send inspect:{id:iid,target:target}

		refresh : -> window.location.reload()

		send : (json) -> @sock.send JSON.stringify(json)

		load : (target) -> @send {load:target}		

		discard : (target) -> @send {discard:target}

		save : -> @send {save:{code:@code,title:@title}}

		switchHost : (host) -> @send {host:host}

		run : (opts) -> 
			@plot = []
			@updateAngularJs()
			if opts?.stop
				@send {stop:true}
			else
				@send {run:this.code}

		print : (msg) ->	
			console.log msg
			@logs += msg + "\n"
			@updateAngularJs()

		watch : (key) ->
			@send {watch:key}
			@watches[key] = '..pending..'
			@updateAngularJs()

		unwatch : (key) ->
			delete @watches[key]
			@send {unwatch:key}
			@updateAngularJs()

	new Server()

app.controller 'InspectTargetDialogCtrl', ($scope, dialog, node) ->
	$scope.data = null
	$scope.$watch 'target', (newVal,oldVal) ->
		if newVal and newVal != ''
			node.inspect newVal, (err,result) ->
				$scope.$apply ->
					$scope.data = {}
					$scope.data[newVal] = result
		else
			$scope.data = null			
	$scope.close = () ->
		dialog.close()

app.controller 'CodeCtrl', ($scope,node,$dialog) ->
	$scope.server = node		
	$scope.status = ->
		if node.online then "ONLINE" else "OFFLINE"
	$scope.addWatch = (val) ->		
		node.watch(val)
		$scope.cancelEdit()		

	$scope.edit = (key,value) ->
		$scope.edit_target = key
		$scope.edit_value = value
		
	$scope.save = (key,value) ->
		node.send {run:"#{key} = #{value}"}
		$scope.edit_target = null

	$scope.cancelEdit = ->
		$scope.edit_target = null 

	$scope.run_action = ->
		if node.running then "Stop" else "Run"

	$scope.discard = (id) ->
		title = "Please confirm"
		msg = "Do you really want to delete?"
		btns = [{result:'cancel',label:'Cancel'},{result:'ok',label:'ok',cssClass:'btn-danger'}]
		$dialog.messageBox(title, msg, btns)
			.open()
			.then (result)->
				if result == 'ok'
					node.discard(id)

	$scope.inspect = ->
		title = "Inspect"
		d = $dialog.dialog 
			backdrop:true
			keyboard:true
			backdropClick:true
			templateUrl:'template/inspectTarget.html'
			controller:'InspectTargetDialogCtrl'
		d.open()

	
	# I couldn't make this key binding to work with angular-ui
	$(document).keydown (e) ->		
		if e.keyCode == 66 and e.ctrlKey
			node.run()
			false
		
		if e.keyCode == 83 and e.ctrlKey
			node.save()
			false

		if e.keyCode == 81 and e.ctrlKey
			$scope.$apply ->
				$scope.inspect()
			false
