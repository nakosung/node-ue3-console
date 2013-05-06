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