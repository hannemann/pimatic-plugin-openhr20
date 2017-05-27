
module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  sqlite3 = require('sqlite3')
  
  class Openhr20 extends env.plugins.Plugin
  
    init: (app, @framework, @config) =>

      @db = new sqlite3.Database(@config.database)
      @db.on("error", @dbErrorHandler.bind(this))
      @update_interval = @config.update_interval
      @devices = {}
      @deviceAddrs = []
      
      deviceConfigDef = require("./openhr20-device-config-schema")
        
      @framework.deviceManager.registerDeviceClass('Openhr20Thermostat', {
        configDef: deviceConfigDef,
        createCallback: (deviceConfig, lastState) => new Openhr20Thermostat(deviceConfig, lastState, this)
      })
      
      @framework.on "after init", =>
        # Check if the mobile-frontent was loaded and get a instance
        mobileFrontend = @framework.pluginManager.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js', "pimatic-plugin-openhr20/app/js/openhr20-thermostat.coffee"
          mobileFrontend.registerAssetFile 'css', "pimatic-plugin-openhr20/app/css/openhr20-thermostat.css"
          mobileFrontend.registerAssetFile 'html', "pimatic-plugin-openhr20/app/views/openhr20-thermostat.jade"
        else
          env.logger.warn "your plugin could not find the mobile-frontend. No gui will be available"
          
      @getAttributes()
      @updateInterval = setInterval(@getAttributes.bind(this), @update_interval)
      
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
  
    errors:
      "NA1"       : 0x01
      "NA2"       : 0x02
      "MONTAGE"   : 0x04
      "MOTOR"     : 0x08
      "RFM_SYNC"  : 0x10
      "NA5"       : 0x20
      "BAT_W"     : 0x40
      "BAT_E"     : 0x80
      
    modes:
      manu: "manu"
      auto: "auto"
      boost: "boost"
      undef: "-"
      
    template: "openhr20-thermostat"
    
    _realTemperature: null
    _voltage: null
    _error: null
    _errorlevel: null
    _window: null

    constructor: (@config, lastState, @plugin) ->
      @id = @config.id
      @name = @config.name
      @addr = @config.addr
      @sync_devices = @config.sync_devices.split(',')
                        .map((v) -> v.replace /^\s+|\s+$/g, "")
                        .filter((v) -> v != '')
      @db = @plugin.db
      
      @attributes.realTemperature = {
        label: "Real Temperature"
        description: "The real temperature"
        type: "number"
        acronym: "T"
        unit: "°C"
      }
      
      @attributes.voltage = {
        label: "Voltage"
        description: "The battery voltage"
        type: "number"
        unit: "V"
        acronym: ""
      }
      
      @attributes.window = {
        label: "Window"
        description: "The window state"
        type: "string"
        acronym: "W"
      }
      
      @attributes.error = {
        label: "Error"
        description: "The error"
        type: "string"
        acronym: ""
      }
      
      @attributes.errorLevel = {
        label: "Errorlevel"
        description: "The errorlevel"
        type: "string"
        acronym: ""
      }
      
      @attributes.battery = {
        description: "the battery status"
        type: "string"
        #enum: [100, 80, 64, 48, 32, 16, 0]
        label: ["full", "low"]
        icon:
          noText: true
          mapping: {
            'icon-battery-fuel-5': "100"
            'icon-battery-fuel-4': "80"
            'icon-battery-fuel-3': "64"
            'icon-battery-fuel-2': "48"
            'icon-battery-fuel-1': "32"
            'icon-battery-empty': "16"
          }
      }
      
      super(@config, lastState)
      @plugin.addDevice(this)
      @syncValue = null
      
      @config.ecoTemp = @config.ecoTemp or 17
      @config.comfyTemp = @config.comfyTemp or 21
      @boostTemp = @plugin.config.boost_temperature
      @boostDuration = @plugin.config.boost_duration # minutes

    update: (row) ->

      if not @syncValue or @syncValue == 'setPoint'
        switch row.mode
          when @modes.manu.toUpperCase() then @_setMode("manu")
          when @modes.auto.toUpperCase() then @_setMode("auto")
          else @_setMode(@modes.undef)
      if not @syncValue or @syncValue == 'mode'
        @_setSetpoint(row.wanted/100)
      
      @_setValve(row.valve)
        
      @_setBattery(row.battery)
      @_setSynced(row.synced == 1)
      @_setRealTemperature(row.real/100)
      @_setVoltage(row.battery/1000)
      @_setError(row.error)
      @_setErrorLevel(row.error)
      @_setWindow(row.window)
      
      if @_synced and @_mode == @modes.boost and not @boostTimeout
        env.logger.info "#{@name}: reset in #{@boostDuration} minutes"
        @boostTimeout = setTimeout(
          @resetFromBoost.bind(this),
          @boostDuration * 60 * 1000
        )
      
      env.logger.debug "#{@name}: #{@_mode}, #{@_temperatureSetpoint},
                        #{@_valve}%, #{@_synced}, V: #{row.battery}
                        Battery #{@_battery}, Error code: #{row.error}, E-Level #{@_errorLevel}, Bat.: #{@config.batteryType}"

    getRealTemperature: () -> Promise.resolve(@_realTemperature)
    getVoltage: () -> Promise.resolve(@_voltage)
    getError: () -> Promise.resolve(@_error)
    getErrorLevel: () -> Promise.resolve(@_errorLevel)
    getWindow: () -> Promise.resolve(@_window)
    
    _setBattery: (battery) ->
      
      battery /= 1000
      if @config.batteryType is "rechargeable"
        if battery > 2.6
          battery = "100"
        else if battery > 2.5
          battery = "80"
        else if battery > 2.45
          battery = "64"
        else if battery > 2.4
          battery = "48"
        else if battery > 2.35
          battery = "32"
        else
          battery = "16"
      else
        if battery > 2.8333333
          battery = "100"
        else if battery > 2.6666666
          battery = "80"
        else if battery > 2.5
          battery = "64"
        else if battery > 2.33333333
          battery = "48"
        else if battery > 2.16666666
          battery = "32"
        else
          battery = "16"
      super(battery)
      

    _setRealTemperature: (realTemperature) ->
      if @_realTemperature is realTemperature then return
      @_realTemperature = realTemperature
      @emit 'realTemperature', realTemperature

    _setVoltage: (voltage) ->
      if @_voltage is voltage then return
      @_voltage = voltage
      @emit 'voltage', voltage

    _setWindow: (window) ->
      window = if window is 1 then "O" else "C"
      if @_window is window then return
      @_window = window
      @emit 'window', window
      
    _setError: (error) ->
      if @_error is error then return
      if error & @errors.MONTAGE
        error = "Montage"
      else if error & @errors.MOTOR
        error = "Motor"
      else if error & @errors.RFM_SYNC
        error = "RFM sync"
      else if error & @errors.BAT_W
        error = "Bat. warn"
      else if error & @errors.BAT_E
        error = "Bat. low"
      else 
        error = ""
        
      @_error = error
      @emit 'error', error
      
      
    _setErrorLevel: (error) ->
      if @_error is error then return
      if error > 0 
        if error & @errors.BAT_W
          errorLevel = "warn"
        else
          errorLevel = "error"
      else 
        errorLevel = ""
        
      if @_errorLevel is errorLevel then return
      @_errorLevel = errorLevel
      @emit 'errorLevel', errorLevel

    changeModeTo: (mode, is_origin = true) ->
      
      if is_origin
        for addr in @sync_devices
          @plugin.devices[addr].changeModeTo(mode, false)
      
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
      @writeTemperature(@getTemperatureCmd(@boostTemp))
      
    isValidMode: (mode) ->
      mode == @modes.auto or mode == @modes.manu or mode = @modes.boost

    writeMode: (mode) ->
      time = @getTime()
      cmd = @getModeCmd(mode)
      sql = "INSERT INTO 
              command_queue (addr, time, send, data)
              VALUES(#{@addr}, #{time}, 0, 'M0#{cmd}');"
      @db.exec(sql)
        
    getModeCmd: (mode) ->
      return (if mode is @modes.auto then 1 else 0).toString()

    changeTemperatureTo: (temperatureSetpoint, is_origin = true) ->
      
      if is_origin
        for addr in @sync_devices
          @plugin.devices[addr].changeTemperatureTo(
            temperatureSetpoint, false
          )
    
      if not @_synced
        oldTemp = @_temperatureSetpoint
        @_setSetpoint temperatureSetpoint
        @_setSetpoint oldTemp
        env.logger.info("#{@name}: Current command pending...")
        return Promise.reject
      env.logger.info("#{@name}: set #{temperatureSetpoint}°")
      if temp = @getTemperatureCmd temperatureSetpoint
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
        env.logger.info("#{@name}: #{temperatureSetpoint}
                        not within allowed interval")
        return Promise.reject "Temperature not within allowed interval"

    getTemperatureCmd: (temp) ->
      temp = parseFloat(temp) * 2
      if 9 < temp < 61
        temp.toString(16)
      else
        false

    writeTemperature: (temp) ->
      time = @getTime()
      sql = "INSERT INTO
              command_queue (addr, time, send, data)
              VALUES(#{@addr}, #{time}, 0, 'A#{temp}');"
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
      @writeTemperature @getTemperatureCmd(@setPointBeforeBoost)
      @syncValue = 'mode'
      @_setSynced false
      @boostTimeout = undefined
      
    getTime: () ->
      parseInt(Date.now() / 1000)
      
    getStatus: () ->
      time = @getTime()
      sql = "INSERT INTO
              command_queue (addr, time, send, data)
              VALUES(#{@addr}, #{time}, 0, 'D');"
      @db.exec(sql)

    destroy: () ->
      super()
      
  openhr20 = new Openhr20
  return openhr20
