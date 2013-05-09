_ = require('underscore')
async = require 'async'

# primitives
class Vector3 
	constructor:(@X,@Y,@Z) ->
	toString:->"(X=#{@X},Y=#{@Y},Z=#{@Z})"

class Rotator 
	constructor:(@Pitch,@Yaw,@Roll) ->
	toString:->"(Pitch=#{@Pitch},Yaw=#{@Yaw},Roll=#{@Roll})"	

parsers = 
[
	p:/^None/
	fn:(args...,cb)->cb null
,
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
			(cb) -> from e, bridge, (result) ->
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
	if _.isNaN(num)	then cb(text) else cb(num)

to = (value) -> (value)

exports.Vector3 = Vector3
exports.Rotator = Rotator
exports.from = from
exports.to = to
exports.name = "UnrealEngine3"