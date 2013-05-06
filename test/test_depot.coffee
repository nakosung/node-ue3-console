{CodeDepot} = require '../lib/server/depot'
assert = require 'assert'

describe 'CodeDepot', ->
	depot = null
	before ->
		depot = new CodeDepot()

	key = null
	doc = 
		code:"SomeRandomText"
		title:"SomeRandomeTitle"

	it 'should save doc', (done) ->		
		depot.save doc, (err,result) ->
			assert.equal err,null
			key = result
			done()

	it 'should list', (done) ->
		depot.list null, (err,result) ->
			assert.equal err,null
			done()

	it 'should load saved doc', (done) ->
		depot.load key, (err,result) ->
			assert.equal err,null
			assert.equal result.code, doc.code
			assert.equal result.title, doc.title
			done()

	it 'should discard doc', (done) ->
		depot.discard key, done

