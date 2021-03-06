module.exports = {
    title: "Openhr20Thermostat config options"
    type: "object"
    extensions: ["xLink"]
    properties:
      addr:
        description: "The device address"
        type: "number"
      sync_devices:
        description: "The devices to be synced with this device (comma seperated list of addresses)"
        type: "string",
        default: ""
      batteryType:
        description: "change to the used type of batteries"
        type: "string"
        enum: ["rechargeable", "non rechargeable"]
        default: "rechargeable"
      comfyTemp:
        description: "The defined comfy temperature"
        type: "number"
        default: 21
      ecoTemp:
        description: "The defined eco mode temperature"
        type: "number"
        default: 17
      guiShowValvePosition:
        description: "Show the valve position in the GUI"
        type: "boolean"
        default: true
      guiShowModeControl:
        description: "Show the mode buttons in the GUI"
        type: "boolean"
        default: true
      guiShowPresetControl:
        description: "Show the preset temperatures in the GUI"
        type: "boolean"
        default: true
      guiShowTemperatureInput:
        description: "Show the temperature input spinbox in the GUI"
        type: "boolean"
        default: true
      guiShowBatteryState:
        description: "Show the battery status in the GUI"
        type: "boolean"
        default: true
      guiShowRealTemperature:
        description: "Show the battery status in the GUI"
        type: "boolean"
        default: true
      guiShowVoltage:
        description: "Show the voltage of batteries in the GUI"
        type: "boolean"
        default: true
      guiShowError:
        description: "Show the error in the GUI"
        type: "boolean"
        default: true
      guiShowWindow:
        description: "Show the window state in the GUI"
        type: "boolean"
        default: true
}
