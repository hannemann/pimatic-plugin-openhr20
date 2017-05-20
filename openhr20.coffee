# #Plugin template

# This is an plugin template and mini tutorial for creating pimatic plugins. It will explain the 
# basics of how the plugin system works and how a plugin should look like.

# ##The plugin code

# Your plugin must export a single function, that takes one argument and returns a instance of
# your plugin class. The parameter is an envirement object containing all pimatic related functions
# and classes. See the [startup.coffee](http://sweetpi.de/pimatic/docs/startup.html) for details.
module.exports = (env) ->

  # ###require modules included in pimatic
  # To require modules that are included in pimatic use `env.require`. For available packages take 
  # a look at the dependencies section in pimatics package.json

  # Require the  bluebird promise library
  Promise = env.require 'bluebird'

  # Require the [cassert library](https://github.com/rhoot/cassert).
  assert = env.require 'cassert'

  # Include you own depencies with nodes global require function:
  #  
  sqlite3 = require('sqlite3')

  # ###MyPlugin class
  # Create a class that extends the Plugin class and implements the following functions:
  class Openhr20 extends env.plugins.Plugin

    # ####init()
    # The `init` function is called by the framework to ask your plugin to initialise.
    #  
    # #####params:
    #  * `app` is the [express] instance the framework is using.
    #  * `framework` the framework itself
    #  * `config` the properties the user specified as config for your plugin in the `plugins` 
    #     section of the config.json file 
    #     
    # 
    init: (app, @framework, @config) =>
      env.logger.info("database filename '#{@config.database}'")
      if @config.database
        @initDatabase()
        env.logger.info(@db)
        @getValves()
      else
        env.logger.info("Please specify database filename")
      env.logger.info("Hello World")

    initDatabase: () ->
      @db = new sqlite3.Database(@config.database)

    getValves: () ->
      sql = 'select * from log where id in (select id from log order by id desc, addr limit 200) group by addr order by addr;'
      @db.each(sql, @logValve)
      @

    logValve: (err, row) ->
      if not err
        env.logger.info(row.addr)
      @

  # ###Finally
  # Create a instance of my plugin
  openhr20 = new Openhr20
  # and return it to the framework.
  return openhr20
