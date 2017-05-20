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
}
