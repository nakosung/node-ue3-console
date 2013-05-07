{from,to,Vector3,Rotator} = require '../lib/server/ue3prim'
assert = require 'assert'
async = require 'async'

describe 'ue3prim', ->
	check = (cases,done,type) ->
		jobs = cases.map (src) -> 
			(cb) -> 
				from src, null, (out) ->
					assert.ok out instanceof type, out
					assert.equal src, to out
					cb()			
		async.parallel jobs, done

	it 'should parse and build vec3 correctly', (done) ->
		cases = [
			"(X=380.680908,Y=-179.647812,Z=268.144135)",
			"(X=1,Y=1,Z=1)",
			"(X=-1,Y=-1,Z=-1)"			
		]

		check cases, done, Vector3
		
	it 'should parse and build rot correctly', (done) ->
		cases = [
			"(Pitch=1,Yaw=1,Roll=1)"
		]

		check cases, done, Rotator

	