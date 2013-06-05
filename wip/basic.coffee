#example of using the ccxmleventemitter module
#see: https://github.com/TheDistractor/CC128EventEmitter for more information

fs = require 'fs'
ccSvc = require '../src/ccxmleventemitter'
logfile = "log.txt"

###
scenario:
---------
EnvIR with IAM's on sensor 1,2,3 and Optismart linked to 0 and 9 (data)
connected to linux usb serial port /dev/ttyUSB0
###

#create a new instance of the BaseStation on serial port /dev/ttyUSB0
#we will use the OS time for events instead of the base stations time
#we will report base messages every 30 secs (these contain temp etc)
#we will initialise sensor '9' with a reading of 1000.000 (this could represent the reading on a meter dial)
#we setup a spikeThreshold of 60 ipu's. If and imp sensor reports above this value we treat as spike and the module tries to flatten the reading and carry on recording

envir = new ccSvc.CurrentCost128XMLBaseStation '/dev/ttyUSB0', {useOSTime : true, debug: false, emitBaseEvery: 30, reading : {'9':1000.000}, spikeThreshold:60 }


envir.on 'base', (eventinfo) ->
  console.log "This base station is using #{eventinfo.src} firmware and has been running for #{eventinfo.dsb} days. The temperature is currently #{eventinfo.temp}"

#use this for IAM's and clamps etc.
envir.on 'sensor' , (eventinfo) ->
  console.log "Whole House consumption reported as  #{eventinfo.watts} watts" if eventinfo.sensor == '0'
  console.log "IAM #{eventinfo.sensor} reported as  #{eventinfo.watts} watts" if (eventinfo.sensor != '0') and (eventinfo.watts > 0) 

#use this for impulse sensors like optismart's - sensortype will report 2,3,4 etc elec, gas, water - see spec documents.
envir.on 'impulse', (eventinfo) ->
  console.log "There have been #{eventinfo.value} impulses on sensor #{eventinfo.sensor} since the sensor was powered on"

#this tries to keep a 'meter' reading, but can suffer with spikes.
envir.on 'impulse-reading' , (eventinfo) ->
  console.log "Sensor #{eventinfo.sensor} reports a reading of #{eventinfo.reading} accumulated since: #{(new Date(eventinfo.timeFrom)).toLocaleString()}"

#how many impulses since last time.
envir.on 'impulse-delta' , (eventinfo) ->
  console.log "There have been #{eventinfo.delta} impulses on sensor #{eventinfo.sensor} since the last reported event"

#basic attempt to report the average usage 
envir.on 'impulse-avg' , (eventinfo) ->
  console.log "Sensor #{eventinfo.sensor} reports an average consumption of #{eventinfo.avg} units since last reported event"

#we dont like spikes - but this tries to tell us we have had one.
envir.on 'impulse-spike', (eventinfo) ->
  data = "#{(new Date()).toLocaleTimeString()} Sensor #{eventinfo.sensor} Spiked with pulses of #{eventinfo.spike} units since last reported event"
  console.log data
  fs.appendFileSync logfile, data if logfile?

#this tells us we have tried to apply a spike correction - readings should continue 'almost' normally.  
envir.on 'impulse-correction', (eventinfo) ->
  data = "#{(new Date()).toLocaleTimeString()} Sensor #{eventinfo.sensor} has had a reading reset to #{eventinfo.newReading} and a new delta calculated of #{eventinfo.newDelta}"
  console.log data
  fs.appendFileSync logfile, data if logfile?

#we got a spike and could not recover as gracefully as we wanted, so data may be a little off - we will still report as if we started up again with a base reading.
envir.on 'impulse-warning', (eventinfo) ->
  data = "#{(new Date()).toLocaleTimeString()} Sensor #{eventinfo.sensor} has had a reading reset to last valid reading of #{eventinfo.newReading} due to spike with no correction data applied"
  console.log data
  fs.appendFileSync logfile, data if logfile?


    
process.on 'SIGINT', () ->
  console.log  "\ngracefully shutting down from  SIGINT (Crtl-C)" 
  
  envir.close()
  envir = null

  console.log "--EXIT--"
  process.exit 0






