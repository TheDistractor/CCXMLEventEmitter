#example of using the ccxmleventemitter module
#see: https://github.com/TheDistractor/CC128EventEmitter for more information

ccSvc = require '../lib/ccxmleventemitter'

#create a new instance of the BaseStation on serial port /dev/ttyUSB0
#we will use the OS time for events instead of the base stations time
#we will report base messages every 30 secs (these contain temp etc)
#we will initialise sensor '9' with a reading of 1100.000 (this could represent the reading on a meter dial)

envir = new ccSvc.CurrentCost128XMLBaseStation '/dev/ttyUSB0', {useOSTime : true, debug: false, emitBaseEvery: 30, reading : {'9':1100.000} }



envir.on 'base', (eventinfo) ->
  console.log "This base station is using #{eventinfo.src} firmware and has been running for #{eventinfo.dsb} days. The temperature is currently #{eventinfo.temp}"

envir.on 'sensor' , (eventinfo) ->
  console.log "Whole House consumption reported as  #{eventinfo.watts} watts" if eventinfo.sensor == '0'

envir.on 'impulse', (eventinfo) ->
  console.log "There have been #{eventinfo.value} impulses on sensor #{eventinfo.sensor} since the sensor was powered on"

envir.on 'impulse-reading' , (eventinfo) ->
  console.log "Sensor #{eventinfo.sensor} reports a reading of #{eventinfo.reading}"

envir.on 'impulse-delta' , (eventinfo) ->
  console.log "There have been #{eventinfo.delta} impulses on sensor #{eventinfo.sensor} since the last reported event"

envir.on 'impulse-avg' , (eventinfo) ->
  console.log "Sensor #{eventinfo.sensor} reports an average consumption of #{eventinfo.avg} units since last reported event"


    
process.on 'SIGINT', () ->
  console.log  "\ngracefully shutting down from  SIGINT (Crtl-C)" 
  
  envir.close()
  envir = null

  console.log "--EXIT--"
  process.exit 0






