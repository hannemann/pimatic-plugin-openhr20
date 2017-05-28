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

The battery icon is computed by the plugin shows empty when rechargeable batteries reach a voltage level below 1.05V per cell so one should have a few days time before the voltage drops below 0.9V/cell and the battery could be damaged.
The 'Bat. warn' and 'Bat. low' error messages are computed by the valve itself and can be configured within the openhr20 web frontend.

