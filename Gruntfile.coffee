module.exports = (grunt) ->
	grunt.initConfig
		pkg : grunt.file.readJSON 'package.json'
		coffee :
			server :
				options:
					sourceMap:true
				files:
					'lib/server/main.js' : 'src/server/main.coffee'
					'lib/server/ue3.js' : 'src/server/ue3.coffee'
					'lib/server/ue3prim.js' : 'src/server/ue3prim.coffee'
					'lib/server/depot.js' : 'src/server/depot.coffee'
			client :
				files:
					'lib/client/client.js' : ['src/client/*.coffee']				
		uglify :
			client : 
				files:
					'lib/client/client.min.js' : 'lib/client/client.js'
		mochaTest :
			all : ['test/**/*.*']		

	grunt.loadNpmTasks 'grunt-contrib-coffee'
	grunt.loadNpmTasks 'grunt-contrib-uglify'
	grunt.loadNpmTasks 'grunt-mocha-test'	
		
	grunt.registerTask 'default', ['coffee']
	grunt.registerTask 'prod', ['coffee','uglify']
	grunt.registerTask 'test', ['mochaTest']
	