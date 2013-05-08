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

parsers = 
[
	p:/^\(X=(\-?\d+(\.\d+)?),Y=(\-?\d+(\.\d+)?),Z=(\-?\d+(\.\d+)?)/
	fn:(vec3,bridge,cb)->cb new Vector3(parseFloat(vec3[1]),parseFloat(vec3[3]),parseFloat(vec3[5]))
,
	p:/^\(Pitch=(\d+),Yaw=(\d+),Roll=(\d+)\)/
	fn:(rot,bridge,cb)->cb new Rotator(parseInt(rot[1]),parseInt(rot[2]),parseInt(rot[3]))
,
	p:/^\((.*)\)/
	fn:(array,bridge,cb)->
		elems = array[1].split(',')
		seq = elems.map (e) -> 
			(cb) -> from_unrealengine3 e, bridge, (result) ->
				cb(null,result)
		async.parallel seq, (err,result) ->
			cb(result)
,
	p:/^([a-zA-Z][A-Z0-9a-z_]+)'([a-zA-Z\-][\-A-Z0-9a-z_\.\:]+)'/
	fn:(obj,bridge,cb)-> bridge.access obj[0], cb	
]

from = (text,bridge,cb) ->
	for d in parsers		
		x = d.p.exec(text)
		if x
			d.fn(x,bridge,cb)
			return
	
	num = parseFloat(text) 
	if _.isNaN(num)			
		cb(text)
	else 			
		cb(num)

to = (value) ->
	if value instanceof UEPrim
		value.export()
	else
		value.toString()

exports.Vector3 = Vector3
exports.Rotator = Rotator
exports.from = from
exports.to = to
exports.name = "UnrealEngine3"