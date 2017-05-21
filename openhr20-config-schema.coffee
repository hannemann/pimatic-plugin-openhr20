# #my-plugin configuration options
# Declare your config option for your plugin here. 
module.exports = {
  title: "openhr20 config options"
  type: "object"
  properties:
    database:
      description: "Path to database file"
      type: "string"
      default: ""
    update_interval:
      description: "The Update interval in milliseconds"
      type: "number"
      default: 15000
    boost_temperature:
      description: "The boost temperature"
      type: "number"
      default: 30
    boost_duration:
      description: "The boost mode duration in minutes"
      type: "number"
      default: 5
    debug:
      doc: "Enabled debug messages"
      type: "boolean"
      default: false
}
