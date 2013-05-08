_ = require('underscore')
async = require 'async'

# primitives
class UEPrim
	export:-> throw "NOTIMPL"
	toString:->@export()

class Vector3 extends UEPrim
	constructor:(@X,@Y,@Z) ->
	export:->"(X=#{@X},Y=#{@Y},Z=#{@Z})"

class Rotator extends UEPrim
	constructor:(@Pitch,@Yaw,@Roll) ->
	export:->"(Pitch=#{@Pitch},Yaw=#{@Yaw},Roll=#{@Roll})"	

from_unrealengine3 = (text,bridge,cb) ->
	vec3 = /^\(X=(\-?\d+(\.\d+)?),Y=(\-?\d+(\.\d+)?),Z=(\-?\d+(\.\d+)?)/.exec(text)						
	if vec3							
		cb new Vector3(parseFloat(vec3[1]),parseFloat(vec3[3]),parseFloat(vec3[5]))
	else
		rot = /^\(Pitch=(\d+),Yaw=(\d+),Roll=(\d+)\)/.exec(text)			
		if rot					
			cb new Rotator(parseInt(rot[1]),parseInt(rot[2]),parseInt(rot[3]))
		else				
			array = /^\((.*)\)/.exec(text)
			if array
				elems = array[1].split(',')
				seq = elems.map (e) -> 
					(cb) -> from_unrealengine3 e, bridge, (result) ->
						cb(null,result)
				async.parallel seq, (err,result) ->
					cb(result)
			else
				obj = /^([a-zA-Z][A-Z0-9a-z_]+)'([a-zA-Z\-][\-A-Z0-9a-z_\.\:]+)'/.exec(text)
				if obj			
					bridge.access text, (o) ->
						cb(o)
				else
					num = parseFloat(text) 
					if _.isNaN(num)			
						cb(text)
					else 			
						cb(num)

to_unrealengine3 = (value) ->
	if value instanceof UEPrim
		value.export()
	else
		value.toString()

exports.Vector3 = Vector3
exports.Rotator = Rotator
exports.from = from_unrealengine3
exports.to = to_unrealengine3