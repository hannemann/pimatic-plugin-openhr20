# #Plugin template

# This is an plugin template and mini tutorial for creating pimatic plugins. It will explain the 
# basics of how the plugin system works and how a plugin should look like.

# ##The plugin code

# Your plugin must export a single function, that takes one argument and returns a instance of
# your plugin class. The parameter is an envirement object containing all pimatic related functions
# and classes. See the [startup.coffee](http://sweetpi.de/pimatic/docs/startup.html) for details.
module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  sqlite3 = require('sqlite3')
  
  class Openhr20 extends env.plugins.Plugin
    # #####params:
    #  * `app` is the [express] instance the framework is using.
    #  * `framework` the framework itself
    #  * `config` the properties the user specified as config for your plugin in the `plugins` 
    #     section of the config.json file 
    #     
    # 
    init: (app, @framework, @config) =>
      env.logger.info("Hello World")

      @db = new sqlite3.Database(@config.database)
      @db.on("error", (err) -> env.logger.error("Openhr20: Database error occured"))
      @devices = {}
      @deviceAddrs = []
      
      deviceConfigDef = require("./openhr20-device-config-schema")
        
      @framework.deviceManager.registerDeviceClass('Openhr20Thermostat', {
        configDef: deviceConfigDef,
        createCallback: (deviceConfig, lastState) => new Openhr20Thermostat(deviceConfig, lastState, this)
      })
      
      @updateInterval = setInterval(@getAttributes.bind(this), 5000)
      
    addDevice: (device) ->
      @devices[device.addr] = device
      @deviceAddrs.push(device.addr)
      
    getAttributes: () ->
      limit = @deviceAddrs.length
      addr = @deviceAddrs.join(',')
      sql = "SELECT * FROM log 
            WHERE addr IN (#{addr})
            AND id IN (
              select id from log
              order by id desc, addr limit 200
            )
            GROUP BY addr;"
      @db.all(sql, @updateAttributes.bind(this))
      @
      
    updateAttributes: (err, rows) ->
      if not err
        for row in rows
          @devices[row.addr].updateAttributes(row)
      @
      

  class Openhr20Thermostat extends env.devices.HeatingThermostat
  
    error_mask:
      0x01: "NA1"
      0x02: "NA2"
      0x04: "MONTAGE"
      0x08: "MOTOR"
      0x10: "RFM_SYNC"
      0x20: "NA5"
      0x40: "BAT_W"
      0x80: "BAT_E"
      
    modes:
      manu: "manu"
      auto: "auto"
      boost: "boost"
      undef: "-"

    constructor: (@config, lastState, @plugin) ->
      @id = @config.id
      @name = @config.name
      @addr = @config.addr
      @db = @plugin.db
      super(@config, lastState)
      @plugin.addDevice(this)
      @syncValue = null
      
      @config.ecoTemp = @config.ecoTemp or 17
      @config.comfyTemp = @config.comfyTemp or 21
      @boostTemp = 30
      @boostDuration = 2 # minutes

    updateAttributes: (row) ->

      if not @syncValue or @syncValue == 'setPoint'
        switch row.mode
          when @modes.manu.toUpperCase() then @_setMode("manu")
          when @modes.auto.toUpperCase() then @_setMode("auto")
          else @_setMode(@modes.undef)
      if not @syncValue or @syncValue == 'mode'
        @_setSetpoint(row.wanted/100)
      
      @_setValve(row.valve)
      @_setBattery(row.battery/1000)
        
      @_setSynced(@isSynced(row))
      
      env.logger.info "#{@name}: #{@_mode}, #{@_temperatureSetpoint}, #{@_valve}%, #{@_synced}"

    isSynced: (row) ->
      @modeSynced(row.mode) and @setPointSynced(row.wanted/100)
      
    modeSynced: (mode) ->
      mode.toLowerCase() == @_mode or @_mode == @modes.boost and mode.toLowerCase() == @modes.manu
      
    setPointSynced: (setPoint) ->
      setPoint == @_temperatureSetpoint

    changeModeTo: (mode) ->
      env.logger.info mode
    
      if not @_synced
        oldMode = @_mode
        @_setMode mode
        @_setMode oldMode
        env.logger.info("Openhr20: Current command pending...")
        return Promise.reject
      env.logger.info("Set mode: #{mode} on #{@name}")
      if @_mode is mode then return Promise.resolve true
      if mode is @modes.auto or @modes.manu
        if @boostTimeout
          clearTimeout(@boostTimeout)
          @boostTimeout = undefined
        @_setMode mode
        @writeMode mode
        @syncValue = 'mode'
        @getStatus()
        @_setSynced false
      if mode is @modes.boost
        @modeBeforeBoost = @_mode
        @setPointBeforeBoost = @_temperatureSetpoint
        @_setMode @modes.boost
        @writeMode @modes.manu
        @writeTemperature(@getParsedTemperature(@boostTemp))
        @getStatus()
        @boostTimeout = setTimeout(@resetFromBoost.bind(this), @boostDuration * 60 * 1000)
      return Promise.resolve true

    writeMode: (mode) ->
      time = @getTime()
      cmd = @getParsedMode(mode)
      sql = "INSERT INTO command_queue (addr, time, send, data) VALUES(#{@addr}, #{time}, 0, 'M0#{cmd}');"
      @db.exec(sql)
        
    getParsedMode: (mode) ->
      return (if mode is @modes.auto then 1 else 0).toString()

    changeTemperatureTo: (temperatureSetpoint) ->
      env.logger.info temperatureSetpoint
      if not @_synced
        oldTemp = @_temperatureSetpoint
        @_setSetpoint temperatureSetpoint
        @_setSetpoint oldTemp
        env.logger.info("Openhr20: Current command pending...")
        return Promise.reject
      env.logger.info("Set temperature: #{temperatureSetpoint} on #{@name}")
      if temp = @getParsedTemperature temperatureSetpoint
        if @boostTimeout
          clearTimeout(@boostTimeout)
          @boostTimeout = undefined
        @_setSetpoint temperatureSetpoint
        @writeTemperature temp
        @writeMode @modes.manu
        @syncValue = 'setPoint'
        @getStatus()
        @_setSynced false
        return Promise.resolve true
      else
        env.logger.info("Temperature: #{temperatureSetpoint} not within allowed interval")
        return Promise.reject "Temperature not within allowed interval"

    getParsedTemperature: (temp) ->
      temp = parseFloat(temp) * 2
      if 9 < temp < 61
        temp.toString(16)
      else
        false

    writeTemperature: (temp) ->
      time = @getTime()
      sql = "INSERT INTO command_queue (addr, time, send, data) VALUES(#{@addr}, #{time}, 0, 'A#{temp}');"
      @db.exec(sql)
      
    resetFromBoost: () ->
      @_setMode @modeBeforeBoost
      @writeMode @modeBeforeBoost
      @_setSetpoint @setPointBeforeBoost
      @writeTemperature @getParsedTemperature(@setPointBeforeBoost)
      
    getTime: () ->
      parseInt(Date.now() / 1000)
      
    getStatus: () ->
      time = @getTime()
      sql = "INSERT INTO command_queue (addr, time, send, data) VALUES(#{@addr}, #{time}, 0, 'D');"
      @db.exec(sql)

    destroy: () ->
      super()
      

  # ###Finally
  # Create a instance of my plugin
  openhr20 = new Openhr20
  # and return it to the framework.
  return openhr20
