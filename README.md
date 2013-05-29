#CC128EventEmitter
=================

Connects the CurrentCost [basestation] (CC128) XML output with node.js EventEmitter.

I wanted to be able to deal with my EnvIR basestation XML output within node, but 
using node's EventEmitter rather than having to deal with the XML directly. 
There are a few node/currentcost implementations out there, but they did not seem so simple
to interface with as I envisage. I'll list some I looked at below as they may be a better fit for others.

This module is initialised with a 'device' parameter representing the serial port 
your currentcost basestation is connected to.

Once you have instantiated an instance of '' it will emit various messages with relevant data that your 
implementation can listen to and act upon. I will add history events shortly (as I have no current use for them).

I use coffee-script, so examples are coffee-script

    ccSvc = require 'cc128EventSvc'

    options = {baseEventRepeatEvery: 60} #default

    envir = new ccSvc.basestation '/dev/ttyUSB3', options  #or whatever your usb device is.

    #you can this listen to those events you want
    envir.on 'data' (einfo) ->
      einfo.sensor == 0 then console.log "whole house using:#{einfo.watts} watts" 



The following events are emitted (descriptions below):
*'data' (eventinfo)
*'impulse' (eventinfo)
*'impulse-reading' (eventinfo)
*'impulse-avg' (eventinfo)

The following events are planned:
*'history' (eventinfo)



##data
This is emitted every time a normal sensor reading is generated, sensors are 0-9 with 0 being while house 
and 9 normally being a 'data' channel. If a 'data' channel is detected, it is actually generated as a set of
'impulse' events as thay carry additional information. 

parameters: eventinfo
              



