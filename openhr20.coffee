
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

      @db = new sqlite3.Database(@config.database)
      @db.on("error", @dbErrorHandler.bind(this))
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
      sql = "SELECT *,
            NOT EXISTS
              (SELECT * FROM command_queue WHERE addr = log.addr) synced
            FROM log 
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
          @devices[row.addr].update(row)
      @
      
    dbErrorHandler: (err) ->
      env.logger.error("Openhr20: Database error occured", err)
      

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
      @boostTemp = 25
      @boostDuration = 2 # minutes

    update: (row) ->

      if not @syncValue or @syncValue == 'setPoint'
        switch row.mode
          when @modes.manu.toUpperCase() then @_setMode("manu")
          when @modes.auto.toUpperCase() then @_setMode("auto")
          else @_setMode(@modes.undef)
      if not @syncValue or @syncValue == 'mode'
        @_setSetpoint(row.wanted/100)
      
      @_setValve(row.valve)
      @_setBattery(row.battery/1000)
      @_setSynced(row.synced == 1)
      
      if @_synced and @_mode == @modes.boost and not @boostTimeout
        env.logger.info "#{@name}: reset in #{@boostDuration} minutes"
        @boostTimeout = setTimeout(@resetFromBoost.bind(this), @boostDuration * 60 * 1000)
      
      env.logger.info "#{@name}: #{@_mode}, #{@_temperatureSetpoint}, #{@_valve}%, #{@_synced}"

    changeModeTo: (mode) ->
      
      if @isValidMode(mode)
    
        if not @_synced
          oldMode = @_mode
          @_setMode mode
          @_setMode oldMode
          env.logger.info("#{@name}: Current command pending...")
          return Promise.reject
          
        env.logger.info("#{@name}: set mode '#{mode}'")
        
        if @_mode is mode then return Promise.resolve true
        
        if mode == @modes.boost
          @setBoostMode()
        else
          @cancelBoostMode()
          @writeMode mode
          
        @_setMode mode
        @syncValue = 'mode'
        @getStatus()
        @_setSynced false
        return Promise.resolve true
        
      return Promise.reject
      
    setBoostMode: () ->
      @modeBeforeBoost = @_mode
      @setPointBeforeBoost = @_temperatureSetpoint
      @writeTemperature(@getParsedTemperature(@boostTemp))
      
    isValidMode: (mode) ->
      mode == @modes.auto or mode == @modes.manu or mode = @modes.boost

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
        env.logger.info("#{@name}: Current command pending...")
        return Promise.reject
      env.logger.info("#{@name}: set #{temperatureSetpoint}°")
      if temp = @getParsedTemperature temperatureSetpoint
        @cancelBoostMode()
        @_setSetpoint temperatureSetpoint
        @writeTemperature temp
        if @_mode == @modes.auto
          @_setMode @modes.undef
        @syncValue = 'setPoint'
        @getStatus()
        @_setSynced false
        return Promise.resolve true
      else
        env.logger.info("#{@name}: #{temperatureSetpoint} not within allowed interval")
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
      
    cancelBoostMode: () ->
      if @boostTimeout
        clearTimeout(@boostTimeout)
        @boostTimeout = undefined
      @
      
    resetFromBoost: () ->
      env.logger.info "#{@name}: reset from boost mode"
      @_setMode @modeBeforeBoost
      @writeMode @modeBeforeBoost
      @_setSetpoint @setPointBeforeBoost
      @writeTemperature @getParsedTemperature(@setPointBeforeBoost)
      @syncValue = 'mode'
      @_setSynced false
      @boostTimeout = undefined
      
    getTime: () ->
      parseInt(Date.now() / 1000)
      
    getStatus: () ->
      time = @getTime()
      sql = "INSERT INTO command_queue (addr, time, send, data) VALUES(#{@addr}, #{time}, 0, 'D');"
      @db.exec(sql)

    destroy: () ->
      super()
      
  openhr20 = new Openhr20
  return openhr20
