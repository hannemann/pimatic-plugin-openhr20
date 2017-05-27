pimatic-plugin-openhr20
=======================

control openhr20 devices from within pimatic

### Configuration
* path to database file

### Device Configuration
* addr: address of device
* batteryType: choose rechargeable or non rechargeable. Used to display the battery status. Non rechargeable batteries discharge linear, rechargeable stay mostly at 1.2V. Hence the display has to be handled different and i recommend to set the correct value here. 
* sync_devices: addresses of devices to be synced with this device on change (comma seperated list e.g 11,12)
* further configuration not necessary and self explanatory
