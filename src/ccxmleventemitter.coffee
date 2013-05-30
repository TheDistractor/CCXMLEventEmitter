#v0.9.0
#Copyright 2013, Andy Spencer thedistractor a-t the-spencers {dot} co -dot- uk

###
    This file is part of ccXmlEventEmitter.

    ccXmlEventEmitter is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Foobar is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Foobar.  If not, see <http://www.gnu.org/licenses/>.
###

###
    CHANGELOG
    2013-05-30 initial upload to github @0.9.0
###





#requires
{EventEmitter} = require 'events'
SerialPort = require 'serialport'
sax = require 'sax'
stream = require 'stream'

#My EnvIR's native TIME support is very dubious, loosing 2hrs in 400 days (approx 18secs per day)
#so for pseudo-realtime events I have an option to override XML time from base with OS time (useOSTime : true) in options.
#If useOSTime is false, time is as reported by base and is HH:MM:SS string format (i.e its NOT a number) - I therefore classify that as useless and urge you to use useOSTime = true.   
#I *may* look at determining this rubbish time as a rolling 'offset' to place a date part on it shortly - but I seriously think it may be flawed to spend the time.

#TODO: Add some error handling
#TODO: Add test cases
#TODO: General tidy up 
#TODO: Add 'history' event support for those who may want it.

class CurrentCost128XMLBaseStation extends EventEmitter
  #state machine for CC128 (+ENVIR) XML output

  serialport : null
  reader     : null
  parser     : null

  #the state data
  _s : 
    inMSG        : false           #we are in a msg
    inREALTIME   : false           #we are in live data
    inHIST       : false           #hist section
    inID         : false           #id tag
    id           : null            #id of sensor
    inSRC        : false           #src tag
    src          : null            #src of data
    inDSB        : false           #dsb tag
    dsb          : null            #days since poweron
    inSENSOR     : false           #sensor section
    sensor       : ""              #sensor value
    inTMPR       : false           #temp section
    temp         : 0               #the temp value
    inCH         : false           #in channel section
    channel      : 0               #channel number
    inWATTS      : false           #in watts section
    watts        : 0               #watts value
    inTIME       : false           #in time section
    time         : null            #time value
    inSENSORTYPE : false           #in type section
    sensortype   : null            #type value  (1=sensor, 2=elec, 3=gas, 4=water) note: the ipu's all derive different units.
    inIMP        : false           #in imp section (sensor 9 data!!)
    imp          : null            #imp value
    inIPU        : false           #ipu section
    ipu          : null            #ipu value

    impStart     : {}              #the first impulse reading for relevant sensor 
    impLast      : {}              #delta impulse for relevant sensor
    impTime      : {}              #time used for delta for relevant sensor
    #reading      : {}              #the meter reading when instanced for sensor

    #useOSTime    : true
  
  emitbase : true  #can we emit the next base message

  #@device=an o/s specific serial moniker (e.g linux /dev/ttyUSB0, windows COM1, mac /dev/tty-usb14783)
  constructor : (@device, {@useOSTime, @emitBaseEvery, @debug, @reading } = {} ) ->
    @useOSTime ?= false
    @emitBaseEvery ?= 60   
    @debug ?= false
    @reading ?= {} #hash of readings e.g. {'9':1000}

    if @debug
      console.log "useOSTime #{@useOSTime}" 
      console.log "emitBaseEvery #{@emitBaseEvery}" 
      console.log "debug #{@debug}" 
      console.log "reading #{@reading}" 

    self = this

    
    @parser = sax.createStream(false, {lowercasetags:true, trim:true})

    @parser.onerror = (e) ->
      console.error "error!", e if self.debug
      # clear the error
      @error = null
      @resume()

    @parser.ontext =  (t) ->
      # got some text.  t is the string of text.
      _s = self._s
      if _s.inSENSOR
        _s.sensor = t
        _s.inSENSOR = false

      if _s.inID
        _s.id = t
        _s.inID = false

      if _s.inDSB
        _s.dsb = t
        _s.inDSB = false

      if _s.inSRC
        _s.src = t 
        _s.inSRC = false

      if _s.inTMPR
        _s.temp = parseFloat(t)
        _s.inTMPR = false

      if _s.inTIME
        hms = t.split ':'
        _s.time = new Date()
        if ! self.useOSTime
          _s.time.setHours( hms[0] )
          _s.time.setMinutes( hms[1] )
          _s.time.setSeconds( hms[2] )
        _s.inTIME = false

      if _s.inSENSORTYPE  #1=sensor-watts, 2=electricity-imp data 3=gas-imp data 4=water-imp data
        _s.sensortype = t 
        _s.inSENSORTYPE = false

      if _s.inIMP
        _s.imp = parseFloat(t)
        _s.inIMP = false

      if _s.inIPU
        _s.ipu = parseFloat(t)
        _s.inIPU = false

      if _s.inWATTS
        _s.watts = parseFloat(t)
  

    @parser.onopentag = (node) ->
      # opened a tag.  node has "name" and "attributes"
      _s = self._s

      if node.name == 'msg'
        _s.inMSG = true
        _s.inREALTIME = true

      if _s.inMSG
      
        if node.name == 'hist'
          _s.inHIST = true
          _s.inREALTIME = false
          console.log ">>IN HIST" if self.debug

        if node.name == 'dsb'
          _s.inDSB = true
        if node.name == 'src'
          _s.inSRC = true
        if node.name == 'id'
          _s.inID = true
        if node.name == 'sensor'
          _s.inSENSOR = true

        if node.name == 'tmpr'
          _s.inTMPR = true

        if node.name == 'time'
          _s.inTIME = true

        if node.name == 'type'
          _s.inSENSORTYPE = true

        if node.name == 'imp'
          _s.inIMP = true

        if node.name == 'ipu'
          _s.inIPU = true

        match = /^ch(\d)/.exec node.name
        if match
          _s.inCH = true
          _s.channel = match[1]

        if _s.inCH
          if node.name == 'watts'
            _s.inWATTS = true
        


    @parser.onclosetag = (tagName) ->

      _s = self._s

      if tagName == 'msg'
        _s.inMSG = false
        _s.inREALTIME = false

        if self.emitbase
          self.emit "base", {time: _s.time, src: _s.src, dsb: _s.dsb, temp: _s.temp}
          self.emitbase = false
          setTimeout ( -> self.emitbase = true ), 1000*self.emitBaseEvery
  
      if tagName == 'hist'
        _s.inHIST = false
        _s.inREALTIME = true
        console.log ">>OUT HIST" if self.debug

      if tagName == 'watts'
        _s.inWATTS = false

      if tagName.indexOf('ch') == 0
        _s.inCH = false
        self.emit "sensor",  {time: _s.time, sensor: _s.sensor, id: _s.id, channel: _s.channel, watts: _s.watts}

      if (tagName == 'ipu')

        if _s.inREALTIME     #pseudo-realtime events


          self.emit "impulse", {time: _s.time, sensor: _s.sensor, id: _s.id, type: _s.sensortype, value: _s.imp , ipu: _s.ipu}

          curNow = Date.now()
        
          if _s.impStart[_s.sensor]  == undefined #first time init - so we skip initial event as itmakes no sense to emit it.
            _s.impStart[_s.sensor] = _s.imp
            _s.impTime[_s.sensor] = curNow
            _s.impLast[_s.sensor] = 0
            self.reading[_s.sensor] ?= 0
          else
            consumed = _s.imp - _s.impStart[_s.sensor] #impulses since we started collecting on this instance

            #what the meter dial typically shows if 'reading' has been set, otherwise we start from '0', however its decimalised so if your .dials are not 0-9 it will be a decimal representation
            self.emit "impulse-reading", {time: _s.time, sensor: _s.sensor, id: _s.id, type: _s.sensortype, reading: self.reading[_s.sensor] + (consumed/_s.ipu) }

            #delta of impulse
            curDelta = (_s.imp - _s.impLast[_s.sensor] )
            avgSecs = ((curNow - _s.impTime[_s.sensor] )/1000)
          
            impPerInterval = (curDelta/avgSecs)*60*60  #pulses per hour at current rate 

            self.emit "impulse-delta", {time: _s.time, sensor: _s.sensor, id: _s.id, type: _s.sensortype, delta: curDelta }

            #impulses per hour divide ipu = kwH / 1000 = watts
            self.emit "impulse-avg", {time: _s.time, sensor: _s.sensor, id: _s.id, type: _s.sensortype, avg: Math.floor( (impPerInterval/_s.ipu)*1000  ) }

          _s.impLast[_s.sensor] = _s.imp
          _s.impTime[_s.sensor] = curNow

#TODO: support history
#        if _s.inHIST
#          #we do some history stuff
#          #but we'll do this later as I dont need it currently          


    @parser.onattribute = (attr) ->
      # an attribute.  attr has "name" and "value"

    @parser.onend = () ->
      # parser stream is done, and ready to have more stuff written to it.





    @reader = new stream.Readable()
    @reader._read = (n) ->
      #no body
    @reader.pipe @parser #pipe all output we get into parse 


    console.log "creating:", @device if self.debug

    @serialPort = new SerialPort.SerialPort @device, {baudrate: 57600, parser: SerialPort.parsers.raw}

    @serialPort.on "open", () ->

      console.log 'open' if self.debug

      @on 'data' , (data) ->
        self.reader.push data.toString()

  close : () ->
    @serialPort.close()
    @parser.end()
    @serialPort = null
    @reader = null
    @parser = null
    @removeAllListeners('sensor').removeAllListeners('impulse').removeAllListeners('impulse-reading').removeAllListeners('impulse-delta').removeAllListeners('impulse-avg')
    console.log "base --end--" if @debug
    return

module.exports.CurrentCost128XMLBaseStation = CurrentCost128XMLBaseStation
#we could support additional types of base station if we had any to test





