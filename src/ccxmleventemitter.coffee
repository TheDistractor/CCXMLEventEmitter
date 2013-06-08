###
v0.9.3beta
Copyright 2013, Andy Spencer < lightbulb a-t laughlinez {dot} com >
###

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
    2013-05-30 0.9.0beta - initial upload to github @0.9.0
    2013-06-05 0.9.1beta - added impulse spike behaviour and coping policy @0.9.1
    2013-06-06 0.9.2beta - corrections
    2013-06-08 0.9.3beta - impulse-reading correction, refactored to fully evaluate msg before emitting events - this seperated history tag leakage.
###





#requires
{EventEmitter} = require 'events'
SerialPort = require 'serialport'
sax = require 'sax'
stream = require 'stream'
fs = require 'fs'

###
#My EnvIR's native TIME support is very dubious, loosing 2hrs in 400 days (approx 18secs per day)
#so for pseudo-realtime events I have an option to override XML time from base with OS time (useOSTime : true) in options.
#If useOSTime is false, time is as reported by base and is HH:MM:SS string format (i.e its NOT a number) - I therefore classify that as useless and urge you to use useOSTime = true.   
#I *may* look at determining this rubbish time as a rolling 'offset' to place a date part on it shortly - but I seriously think it may be flawed to spend the time.
###

###
#TODO: Add some error handling
#TODO: Add test cases
#TODO: General tidy up 
#TODO: Add 'history' event support for those who may want it.
#TODO: Add a runtime manual 'reading' update to allow an external process like a GUI input to rebase the reading's.
#I'll transfer these to an issue tracker shortly.
###

class CurrentCost128XMLBaseStation extends EventEmitter
  #state machine for CC128 (+ENVIR) XML output

  serialport : null
  reader     : null
  parser     : null

  ver : "0.9.3-beta"

  #the state data
  #some shortcuts for closing-out and reporting events are made instead
  #of waiting for closing tags (this should be safe)
  #Note: not all data is 'sensor' persisted - this will be added next release.

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

    #sensor persisted data
    impStart     : {}              #the 'first' impulse reading for relevant sensor - nb: this can be reset on spike recovery 
    impStartTime : {}              #the date/time of that 'first' reading
    impLast      : {}              #delta impulse for relevant sensor
    impTime      : {}              #time used for delta for relevant sensor
    impAvg       : {}              #rolling average impules
    readingBAK   : {}              #hold backup readings 
  
  emitbase : true  #can we emit the next base message

  #@device=an o/s specific serial moniker (e.g linux /dev/ttyUSB0, windows COM1, mac /dev/tty-usb14783)
  constructor : (@device, {@useOSTime, @emitBaseEvery, @spikeThreshold, @reading, @debug  } = {} ) ->
    @useOSTime ?= false #do we use the O/S time or emit the base stations 'string' time (which drifts)
    @emitBaseEvery ?= 60   #how often to emit the base message (contains temperature, days-since-birth, firmware rev etc)
    @spikeThreshold ?= 0   #the number of Impulses in a single event to treat as a 'spike' and flatten with an 'average'
    @reading ?= {} #hash of readings e.g. {'9':1000 #optismart on meter, '5':2300 #solar pv}
    @debug ?= false
    @logfile = "cc.xml"

    if @debug
      console.log "debug #{@debug}" 
      console.log "useOSTime #{@useOSTime}" 
      console.log "emitBaseEvery #{@emitBaseEvery}" 
      console.log "reading #{@reading}" 
      console.log "spikeThreshold #{@spikeThreshold}" 


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

      if _s.inID
        _s.id = t

      if _s.inDSB
        _s.dsb = t

      if _s.inSRC
        _s.src = t 

      if _s.inTMPR
        _s.temp = parseFloat(t)

      if _s.inTIME
        hms = t.split ':'
        _s.time = new Date()
        if ! self.useOSTime
          _s.time.setHours( hms[0] )
          _s.time.setMinutes( hms[1] )
          _s.time.setSeconds( hms[2] )

      if _s.inSENSORTYPE  #1=sensor-watts, 2=electricity-imp data 3=gas-imp data 4=water-imp data
        _s.sensortype = t 

      if _s.inIMP
        _s.imp = parseFloat(t)

      if _s.inIPU
        _s.ipu = parseFloat(t)

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


        #if _s.inHIST
        #  console.log "We ignore events in History sections..."

        unless _s.inHIST #only emit these events if not in history
          if self.emitbase
            self.emit "base", {time: _s.time, src: _s.src, dsb: _s.dsb, temp: _s.temp}
            if self.emitBaseEvery != 0 #only re-emit if asked       
              self.emitbase = false
              setTimeout ( -> self.emitbase = true ), 1000*self.emitBaseEvery


          if _s.sensortype == "1" #we are a normal sensor
            self.emit "sensor",  {time: _s.time, sensor: _s.sensor, id: _s.id, channel: _s.channel, watts: _s.watts}

          if _s.sensortype == "2" #we are an impulse type
            self.processImpulse()  


        _s.inMSG = false
        _s.inREALTIME = false
        _s.inHIST = false


      if tagName == 'sensor'
        _s.inSENSOR = false

      if tagName == 'id'
        _s.inID = false

      if tagName == 'dsb'
        _s.inDSB = false

      if tagName == 'tmpr'
        _s.inTMPR = false

      if tagName == 'time'
        _s.inTIME = false

      if tagName == 'src'
        _s.inSRC = false

      if tagName == 'type'
        _s.inSENSORTYPE = false

      if tagName == 'imp'
        _s.inIMP = false

      if tagName == 'ipu'
        _s.inIPU = false

  
      if tagName == 'hist'
        #we only close of history on /msg
        console.log ">>OUT HIST" if self.debug

      if tagName == 'watts'
        _s.inWATTS = false

      if tagName.indexOf('ch') == 0
        _s.inCH = false


    @parser.onattribute = (attr) ->
      # an attribute.  attr has "name" and "value"

    @parser.onend = () ->
      # parser stream is done, and ready to have more stuff written to it.




    #console.log "I am here"
    #this API only on node 0.10+
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
        if self.logfile? #if we are logging we make sure its written with sync
          fs.appendFileSync self.logfile, data.toString()            #do nothing stub


  processImpulse : () ->

        self = this
        _s = self._s

        #console.log "processImplulse a", _s

        if _s.inREALTIME     #pseudo-realtime events


          self.emit "impulse", {time: _s.time, sensor: _s.sensor, id: _s.id, type: _s.sensortype, value: _s.imp , ipu: _s.ipu}

          curNow = Date.now()

       
          unless _s.impStart[_s.sensor]?  #first time init - so we skip initial event as itmakes no sense to emit it.
            console.log "First time sensor seeding for sensor: #{_s.sensor}" if self.debug
            _s.impStart[_s.sensor] = _s.imp
            _s.impStartTime[_s.sensor] = curNow
            _s.impTime[_s.sensor] = curNow
            _s.impLast[_s.sensor] = 0
            self.reading[_s.sensor] ?= 0
            _s.readingBAK[_s.sensor] = self.reading[_s.sensor] #backup reading
            _s.impAvg[_s.sensor] = [] #new avg array
            console.log "End First time sensor seeding for sensor: #{_s.sensor}" if self.debug
          else

            #delta of impulse
            curDelta = (_s.imp - _s.impLast[_s.sensor] )
            avgSecs = ((curNow - _s.impTime[_s.sensor] )/1000)

            consumed = _s.imp - _s.impStart[_s.sensor] #impulses since we started collecting on this instance
            console.log "consumed: #{consumed} impulses  since imp-start: #{_s.impStart[_s.sensor]}, imp-now: #{_s.imp} pre-reading: #{self.reading[_s.sensor]}" if self.debug
            #detect and flatten spikes
            doSpike = false
            if (self.spikeThreshold != 0) and (curDelta > self.spikeThreshold) 
  
              self.emit "impulse-spike", {time: _s.time, sensor: _s.sensor, id: _s.id, type: _s.sensortype, spike: curDelta }
              console.log "impulse-spike  #{(new Date()).toLocaleTimeString()} prev: #{_s.impLast[_s.sensor]} curr: #{_s.imp} delta: #{curDelta}, tot-consumed: #{consumed}" if self.debug
              #we have a spike but do we have enough data to smooth
              if (_s.impAvg[_s.sensor].length >= 1) #even average of 1 is better than nothing!!
                doSpike = true
                tot = _s.impAvg[_s.sensor].reduce (t, s) -> 
                  #console.log "avg data: #{t} #{s}"
                  t+s
				
                avg = tot / _s.impAvg[_s.sensor].length


              if doSpike #take care of spike by using avg
                _s.impStart[_s.sensor] = _s.imp - avg #reset
                _s.impLast[_s.sensor] = _s.imp - avg  #reset
                curDelta = avg
                #recalc consumed
                consumed = avg
                oldRead = self.reading[_s.sensor]
                self.reading[_s.sensor] = _s.readingBAK[_s.sensor] #restore prev backup
                _s.impStartTime[_s.sensor] = curNow #reset

                console.log "reading reset to: #{self.reading[_s.sensor]} from #{oldRead} using average of: #{avg}" if self.debug
                self.emit "impulse-correction", {time: _s.time, sensor: _s.sensor, id: _s.id, type: _s.sensortype,  oldReading: oldRead, newReading: self.reading[_s.sensor], newDelta: curDelta}
              else #we could not flatten spike so we dont generate messages
                _s.impStart[_s.sensor] = _s.imp  # this removes spike but ditches current read data
                _s.impLast[_s.sensor] = _s.imp   # this removes spike "
                _s.impTime[_s.sensor] = curNow        #reset
                _s.impStartTime[_s.sensor] = curNow   #reset
                self.reading[_s.sensor] = _s.readingBAK[_s.sensor] #we really need some avg adding here as we have 'lost' a reading cycle.
                self.emit "impulse-warning", {time: _s.time, sensor: _s.sensor, id: _s.id, type: _s.sensortype,  newReading: self.reading[_s.sensor]}
                console.log "skipping spiked events - no avg collected" if self.debug
                return #no events generated!!!
               

            else #no spike detected, take backup
              _s.readingBAK[_s.sensor] = self.reading[_s.sensor] + (consumed / _s.ipu)

             
            #what the meter dial typically shows if 'reading' has been set, otherwise we start from '0', however its decimalised so if your .dials are not 0-9 it will be a decimal representation            

            unless isFinite (curDelta/_s.ipu)  
              console.log "Infinity: #{curDelta} #{_s.ipu}" if self.debug 
              throw new Error "Infinity Assertion"

            readinc = (curDelta/_s.ipu)
            console.log "Incrementing reading by #{readinc}" if self.debug

            self.emit "impulse-reading", {time: _s.time, sensor: _s.sensor, id: _s.id, type: _s.sensortype, reading: self.reading[_s.sensor] + readinc , timeFrom: _s.impStartTime[_s.sensor] }

            #keep tracking for average
            if _s.impAvg[_s.sensor].length == 3
              _s.impAvg[_s.sensor].pop()

            _s.impAvg[_s.sensor].push(curDelta)

            #only used for debug
            if self.debug
              tot = _s.impAvg[_s.sensor].reduce (t, s) -> 
                 #console.log "avg data: #{t} #{s}"
                 t+s

              console.log "avgArraylen:#{_s.impAvg[_s.sensor].length} total:#{tot}" if self.debug

          
            impPerInterval = (curDelta/avgSecs)*60*60  #pulses per hour at current rate 

            self.emit "impulse-delta", {time: _s.time, sensor: _s.sensor, id: _s.id, type: _s.sensortype, delta: curDelta }

            #impulses per hour divide ipu = kwH / 1000 = watts
            self.emit "impulse-avg", {time: _s.time, sensor: _s.sensor, id: _s.id, type: _s.sensortype, avg: Math.floor( (impPerInterval/_s.ipu)*1000  ) }

            #if doSpike
              #console.log "Post spike calc terminate"
              #process.exit 1


          #always reset this data in loop
          _s.impLast[_s.sensor] = _s.imp
          _s.impTime[_s.sensor] = curNow

#TODO: support history
#        if _s.inHIST
#          #we do some history stuff
#          #but we'll do this later as I dont need it currently          


  version : () ->
    return @ver


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





