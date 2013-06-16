#CCXMLEventEmitter
=================

###Latest News on features and development of this module.
[Can be found here] (https://github.com/TheDistractor/CCXMLEventEmitter/wiki/latestnews)

####Request 2013-06-15
I am looking for more cc128 xml output files. If you can supply any large xml output files with at least 8 days or more cummulative data collection, or any
files with specific anomalies (like spikes), or new devices, like 'GasSmart' transmitters etc, please pass them on so I can use them for testing.
ps: you can now use CCXMLEventEmitter class to record (or re-record) your cc128 output, using the 'logfile' parameter.


###Changelog ([Issue List](https://github.com/TheDistractor/CCXMLEventEmitter/issues))

    * 2013-06-08 for 0.9.3beta - corrected 'impulse-reading'. Added new impulse-spike, impulse-correction, impulse-warning events. updated package.json version deps.
 
    * 2013-06-08 for 0.9.4beta  - corrected history interleave problem. 

    * 2013-05-30 0.9.0beta - initial upload to github @0.9.0
    * 2013-06-05 0.9.1beta - added impulse spike behaviour and coping policy @0.9.1
    * 2013-06-06 0.9.2beta - corrections
    * 2013-06-08 0.9.3beta - impulse-reading correction, refactored to fully evaluate msg before emitting events - this seperated history tag leakage.
    * 2013-06-09 0.9.4beta - impulse bug fixes
    * 2013-06-11 0.9.5beta - bugfixes in impulse and spikes.
    * 2013-06-12 0.9.6beta - 'averages' events added for cummulative consumption information (impulse counters only) , 
                           events are issued hourly * 24, daily * 7, weekly * 1 and then recycled. 
    * 2013-06-12 0.9.7beta - better support for cc128 xml 'timestamp' support, now outputs a proper 'date/time' object when useOSTime=false. 
                           An attempt is made to work out the most appropriate 'date' to wrap around the 'time'
                           Can be manually improved by new 'vdate' parameter to seed an actual 'date' to relate to the time. 
    * 2013-06-13 0.9.8beta - 'file:' moniker added to support 'cc128 xml files' within 'device' parameter ('file:/var/log/currentcost/cc128.xml' [absolute] or 'file:mydata/cc128.xml' [relative] ), 
                           to allow streaming from source xml files, should use useOSTime=false in these situations 
                           in order to make use of the xml files 'time' system in calculations, as events happen in 'faster than realtime'. 
    * 2013-06-15 0.9.9beta - 'inpulse-xxxx' events now supply the 'pseudo' channel '1' (should be a non breaking change for people using these events).
                           - 'averaging' events now include normal sensors (within channels). i.e use the 'channel' property to delineate.
                           - 'sensor' events now emit data for 'all' channels, whereas previously only the last channel encountered was used.(technically a bugfix!!)


##Overview

Connects the CurrentCost (EnvIR) basestation (CC128) XML output with node.js EventEmitter.

I wanted to be able to deal with my EnvIR basestation XML output within node, but 
using node's EventEmitter rather than having to deal with the XML directly. As the EnvIR mostly conforms 
to the CC128 specification, this should work with other devices (like the original CC128), so if you use this on 
another device successfully please drop me a line (or [update the github wiki](https://github.com/TheDistractor/CCXMLEventEmitter/wiki/Devices-Checked) ) with the device name/type and if 
possible the 'src' property from the 'base' message.

There are a few node/currentcost implementations out there, but they did not seem as simple
to interface with as I had envisaged. I'll list some I looked at below as they may be a better fit for others.

This module is initialised with a 'device' parameter representing the serial port  
your currentcost basestation is connected to, or a filesystem file (if the latter, prepend 'file:' to the device parameter, as in 'file:/yourfile.xml'). 
Additional options can be provided as a second hash set.

Once you have instantiated an instance of 'CurrentCost128XMLBaseStation' it will emit various messages with relevant 
data that your implementation can listen to and act upon. I will add history events shortly (as I have no current use for them).

I use coffee-script, so examples are coffee-script

    ccSvc = require 'cc128EventSvc'

    options = {emitBaseEvery: 60} #default

    envir = new ccSvc.CurrentCost128XMLBaseStation '/dev/ttyUSB0', options  #or whatever your usb device is.

    #you can then listen to those events you want
    envir.on 'sensor', (eventinfo) ->
      console.log "whole house using:#{eventinfo.watts} watts" if eventinfo.sensor == 0   


You can also use the module to process an existing xml source file

    ccSvc = require 'cc128EventSvc'

    options = {emitBaseEvery: 60} #default

    envir = new ccSvc.CurrentCost128XMLBaseStation 'file:~/mycurrentcostdata.xml', options  #or whereever your file resides.

    #you can then listen to those events you want
    envir.on 'sensor', (eventinfo) ->
      console.log "whole house using:#{eventinfo.watts} watts" if eventinfo.sensor == 0 


*See the examples folder for more information*

Information on {options} will be expanded shortly:

  * device         - default: undefined - path to serial port or a filesystem entry.
    (e.g '/dev/ttyUSB0' or 'file:~/myccfile.xml' ) 
  * useOSTime      - default: false     - do we use the O/S time or emit the base stations 'string' time (which drifts)
  * emitBaseEvery  - default: 60        - how often to emit the base message (contains temperature, days-since-birth, firmware rev etc)
  * spikeThreshold - default: 0         - the number of Impulses in a single event to treat as a 'spike' and flatten with an 'average', 0 disables detection.
  * reading        - default: {}        - hash of readings e.g. {'9':1000 #optismart on meter, '5':2300 #solar pv}
  * debug          - default: false     - NB: We also make use of debug=interger
  * logfile        - default: null      - filename to log input data. This now only set automatically if debug=true and logfile is undefined, pass your own filename here to capture input data.
  * vdate          - default: null      - our virtual date/time for filesystem based events, if you have a large input file created 15 days ago, you would use now-15 to seed a date for events.
  * emitAverages   - default: true      - do we emit cummulative average data.


#Note:
The newly added feature to process existing captured current cost xml output (via 'file:' device) allows the (re)processing of this data into the events generated as if the device
has been connect for the duration. The side effect is that events are generated rather faster than 'real-time', however the event data does capture the correct 'times' of the events, and 
if the correct 'vdate' parameter is chosen, the dates will follow the data patterns, and also produce averaging data for these past events.

I have run some large captures on my raspberry pi, and whilst I am happy with the features and benefits be aware that it does 
impact the little devices' performance, as the pi is rather disk i/o constrained. I can see a few ways to 'lighten' the load, but would
all impact the duration of the run. I'll post a 'largish' test file shortly.


The following events are emitted (descriptions below):
 * 'base', (baseinfo)
 * 'sensor', (sensorinfo)
 * 'impulse', (impulseinfo)
 * 'impulse-reading', (impulsereadinginfo)
 * 'impulse-avg', (impulseavginfo)
 * 'impulse-spike', (impulsespikeinfo)^
 * 'impulse-correction', (impulsecorrectioninfo)^
 * 'impulse-warning', (impulsewarninginfo)^ 
 * 'average', (averageinfo)^^

 nb: ^ = new for 0.9.3beta
     ^^ = new for 0.9.8beta

The following events are planned:
 * 'history', (historyinfo)



###base###
'base' events are generated every {emitBaseEvery} seconds (default = 60). They contain information relating
to the basestation itself. Internally these messages are generated very frequently but they contain very little useful 
information except perhaps temperature of the base station itself, and are hence reported every 60 seconds by 
default. This can be changed by the {emitBaseEvery} parameter.

parameters: baseinfo


###sensor###
This is emitted every time a normal sensor reading is generated, sensors are 0-9 with 0 normally being 'Whole house' 
and 9 normally being a 'data' channel. If a 'data' channel is detected, it is actually generated as a set of
'impulse' events as they carry additional information, in which case a 'sensor' event will NOT be generated. 

parameters: sensorinfo
              

###impulse
This event is emitted everytime a 'data' channel is encountered. So if you have configured one of your EnvIR 
channels as a 'data' channel it will be reported as 'impulse' rather than 'sensor', as impulse events have 
additional information.

parameters: impilseinfo

###impulse-reading###
This event represents the 'reading' that would be present on your meter dials if you initialised the class with your 
current meter reading. It should track your meter within a reasonable margin of error. These events seem to be 
generated less often than 'sensor' events, approx every 27.5 seconds on my unit.

parameters: impulsereadinginfo

###impulse-avg###
This event represents the average consumption of (elec/gas/water) during the reporting periods. As the period is 
less often than 'sensor' events it may not seem to 'follow' your use pattern, but as it is based on 'pulses' it should 
be more accurate than those reported by 'sensor' events for overall consumption reporting.

parameters: impulseavginfo

###impulse-spike###
Sometimes your impulse sensor (optismart etc) can produce 'false' impulses that I like to call 'spikes', this maybe due to
other IR interference, sensor movement due to environmental conditions, bright glare from sun etc etc.
You can now use the option: spikeThreshold = ipu to setup 'spike' detection.
e.g spikeThreshold = 60 would set anything above 60 ipu's per detection period to be treated as a spike, in which case a simple
averaging algorithm is used to 'flatten' out the spike reading. A 'flattening' condition is known as a 'correction', in which case
a further 'impulse-correction' event will be generated - see below.
By default, spikes are NOT detected/reported/flattened (equivalent to spikeThreshold = 0).


parameters: impulsespikeinfo

###impulse-correction###
Occurs when a 'spike' event has been 'flattened'.

parameters: impulsecorrectioninfo

###impulse-warning###
Occurs when a 'flattening' condition could not be made.

parameters: impulsewarninginfo

###average###
This event is generated when the engine is able to produce averaging data. 
If enabled, events for each sensor/channel are produced hourly * 24, Daily * 7 and weekly * 1.
So, assuming that some data has been seen for sensor '0' during 16:00-16:59:59 hrs, we will get an hourly average event
produced at the point the engine sees the hour cycle to 17:00 (whhich is only when the next event record is processed).
This is generally very soon after the cycle period (within say 5 seconds), but could be longer.
NB: if you are replaying history via an input file, the averages will be emitted within the 'pseduo-clock' that exists within the datastream, 
but again only when the next record causes the detection of a cycle event.


parameters: averageinfo







##WIKI
[module wiki](https://github.com/TheDistractor/CCXMLEventEmitter/wiki)


##Additional implementations of current cost processors I have seen##
* https://github.com/robrighter/node-currentcost

Emits JSON data representing the underlying XML source message. 
