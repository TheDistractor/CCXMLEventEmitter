###
v0.9.9beta
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
    2013-06-09 0.9.4beta - impulse bug fixes
    2013-06-11 0.9.5beta - bugfixes in impulse and spikes.
    2013-06-12 0.9.6beta - 'averages' events added for cummulative consumption information (impulse counters only) , 
                           events are issued hourly * 24, daily * 7, weekly * 1 and then recycled. 
    2013-06-12 0.9.7beta - better support for cc128 xml 'timestamp' support, now outputs a proper 'date/time' object when useOSTime=false. 
                           An attempt is made to work out the most appropriate 'date' to wrap around the 'time'
                           Can be manually improved by new 'vdate' parameter to seed an actual 'date' to relate to the time. 
    2013-06-13 0.9.8beta - 'file:' moniker added to support 'cc128 xml files' within 'device' parameter, 
                           to allow streaming from source xml files, should use useOSTime=false in these situations 
                           in order to make use of the xml files 'time' system in calculations, as events happen in 'faster than realtime'. 
    2013-06-15 0.9.9beta - 'inpulse-xxxx' events now supply the 'pseudo' channel '1' (should be a non breaking change for people using these events.
                           - 'averaging' events now include normal sensors (within channels). i.e use the 'channel' property to delineate.
                           - 'sensor' events now emit data for 'all' channels, whereas previously only the last channel encountered was used.(technically a bugfix!!)


                           
    TODO:                        
          Add better error handling                 
          Add non-impulse sensor average events                 
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


#small simple class to replay a text file, simulating serial input.
class SerialFile extends EventEmitter

  constructor: (@filename) ->

    options = { flags: 'r', encoding: 'utf-8', fd: null, mode: 666, bufferSize: 64 }  
    #options = {}
    stream = fs.createReadStream @filename, options
    
    self = this      
   
    stream.on 'open', () ->
      self.emit 'open'
      
    stream.on 'data' , (data) ->
      self.emit 'data', data
      
    stream.on 'error', (e) ->
      self.emit 'error', e
      
    stream.on 'end' , () ->
      console.log "Stream EOF" if debug
      self.emit 'end'

  pump: (data) ->
    @emit 'data' , data

  close: () ->



class CurrentCost128XMLBaseStation extends EventEmitter
  #state machine for CC128 (+ENVIR) XML output

  serialport : null  #error emitted to client
  reader     : null  #
  parser     : null  #error consumed to resume!

  ver : "0.9.9-beta"

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
    consumedAVG  : {}              #hold cummulative averages
    
    currHr       : -1              #the hour we are calculating averages for
    cycleHr      : -1              #marker for a full 24hr cycle
    cycleHrFlag  : -1              #flag for Hourly Cycle done
    currDy       : -1              #the day we are calculating averages for
    cycleDy      : -1              #marker for a full 7 day cycle
    cycleDyFlag  : -1              #flag for Daily Cycle done
    
  emitbase : true  #can we emit the next base message
  
  debugfile : "ccxmleventemitter.log" #we use this if debug is an integer (>1)
  
  
  #@device=an o/s specific serial moniker (e.g linux /dev/ttyUSB0, windows COM1, mac /dev/tty-usb14783)
  constructor : (@device, {@useOSTime, @emitBaseEvery, @spikeThreshold, @reading, @debug, @vdate, @logfile  } = {} ) ->
    @useOSTime ?= false #do we use the O/S time or emit the base stations 'string' time (which drifts)
    @emitBaseEvery ?= 60   #how often to emit the base message (contains temperature, days-since-birth, firmware rev etc)
    @spikeThreshold ?= 0   #the number of Impulses in a single event to treat as a 'spike' and flatten with an 'average'
    @reading ?= {} #hash of readings e.g. {'9':1000 #optismart on meter, '5':2300 #solar pv}
    @debug ?= false #NB: We also make use of debug=interger
    #@logfile ?= null #this now set only if debug and logfile is undefined 
    @vdate ?= null  #our virtual date/time for filesystem based events
    @emitAverages ?= true #do we emit cummulative average data.
      
    if @debug and (@logfile == undefined) #use unixtime (seconds since 1/1/1970) to generate incremental file.
      @logfile = "cc-#{((new Date()).getTime()/1000).toFixed()}.xml" #logfile default if debug and not a parameter. To override in debug, use logile: null parameter
    
    if @debug
      console.log "debug #{@debug}" 
      console.log "useOSTime #{@useOSTime}" 
      console.log "emitBaseEvery #{@emitBaseEvery}" 
      console.log "reading #{@reading}" 
      console.log "spikeThreshold #{@spikeThreshold}" 
      console.log "logfile #{@logfile}" 
      console.log "vdate #{@vdate}" 
      console.log "emitAverages #{@emitAverages}" 

    console.log "logfile #{@logfile}" 
    #process.exit 1

    self = this

    
    @parser = sax.createStream(false, {lowercasetags:true, trim:true})


    @parser.onerror = (e) ->
      console.error "parser error!", e if self.debug
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


        if self.useOSTime #we should only use this for realtime processing as it will cause problems on reprocessing file based input
          _s.time = new Date()
        else
          if self.vdate == null # a seed date was not supplied - so make a sensible-ish one
            _tmp = new Date(0) #system date/time
            _tmp.setHours new Date().getHours() 
            _tmp.setMinutes new Date().getMinutes() 
            _tmp.setSeconds new Date().getSeconds() 
          
            self.vdate = new Date(0) #derive from input source hours
            self.vdate.setHours( hms[0] )
            self.vdate.setMinutes( hms[1] )
            self.vdate.setSeconds( hms[2] )
            vdiff = self.vdate - _tmp #+ve if vdate ahead
          
            #check if our 'input' clock thinks its yesterday (we assumed this by it being ahead of realtime)
            if vdiff > 0
              ms = (1 * 24 * 60 * 60 * 1000) #1day
              self.vdate = new Date( (new Date()).getTime() - ms ) #put clock back  
            else
              self.vdate = new Date()

            self.vdate.setHours( hms[0] )
            self.vdate.setMinutes( hms[1] )
            self.vdate.setSeconds( hms[2] )
              
            _s.time = self.vdate

            #console.log "vdate init: #{self.vdate}" if self.debug          
            
          else #vdate is now a seed date for the time
            if _s.time == null #first time round and we have seeddate from user.
              _s.time = self.vdate
         
                   
            #_s.time = new Date(self.vdate)
            _s.time.setHours( hms[0] )
            _s.time.setMinutes( hms[1] )
            _s.time.setSeconds( hms[2] )

            #check if we tripped over to next day
            if _s.time.getHours() < self.vdate.getHours()
              ms = (1 * 24 * 60 * 60 * 1000) #1day
              self.vdate = new Date( self.vdate.getTime() + ms)
              _s.time = new Date( _s.time.getTime() + ms )
        
        
        #_s.time is now correct either for ostime or 'device time'.
        #clksrc = "dev" 
        #clksrc = "os" if self.useOSTime
        #console.log "Recorded time: #{_s.time} from #{clksrc}"        
        self.vdate = new Date(_s.time)

      if _s.inSENSORTYPE  #1=sensor-watts, 2=electricity-imp data 3=gas-imp data 4=water-imp data
        _s.sensortype = t 

      if _s.inIMP
        _s.imp = parseFloat(t)

      if _s.inIPU
        val = parseFloat(t)
        if val > 0
           _s.ipu = val

      if _s.inWATTS
        _s.watts = parseFloat(t)
  

    @parser.onopentag = (node) ->
      # opened a tag.  node has "name" and "attributes"
      _s = self._s

      if node.name == 'msg'
        _s.inMSG = true
        _s.inREALTIME = true
        _s.channel = '1' #default channel (for impulse)

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

      if tagName == 'time' #init time related averaging
            
        if self.emitAverages    
          #first time - seed our starting points
          if _s.currHr == -1
            _s.currHr = _s.time.getHours() #this is the hour we start processing 0-23.
            _s.cycleHr = _s.currHr         #this is our daily cycle point.
            _s.currDy = _s.time.getDay()   #the day point we start processing 0-6.
            _s.cycleDy = _s.currDy         #the weekly cycle point.              
  
        _s.inTIME = false
      
      
      if tagName.indexOf('ch') == 0
        unless _s.inHist
          if _s.sensortype == "1" #we are a normal sensor
            self.emit "sensor",  {time: _s.time, sensor: _s.sensor, id: _s.id, channel: _s.channel, watts: _s.watts}

            if self.emitAverages #store data
              #we store some data here
              avgdb = self.getAVGDb(_s.sensor, _s.channel)
              hrly = avgdb["hourly"][ _s.time.getHours().toString() ]["data"]              
              #add our average usage for this reporting period 
              hrly.push( _s.watts )
                
              self.putAVGDb( _s.sensor, _s.channel, avgdb )  
            
        _s.inCH = false
      
      
      
      if tagName == 'msg'


        #if _s.inHIST
        #  console.log "We ignore events in History sections..."

        unless _s.inHIST #only emit these events if not in history
          if self.emitbase
            self.emit "base", {time: _s.time, src: _s.src, dsb: _s.dsb, temp: _s.temp}
            if self.emitBaseEvery != 0 #only re-emit if asked       
              self.emitbase = false
              setTimeout ( -> self.emitbase = true ), 1000*self.emitBaseEvery

              
              
              
          #sensortype 1 emits on close channel
          #also stores avg data then
          
          
          if _s.sensortype == "2" #we are an impulse type
            self.processImpulse()  #this is simmulated channel 0

            
            
          #we now do time related processing
          if self.emitAverages
            #this section emits data and/or calculates summaries
            #console.log "averages:....." 

            #cycle for hourly
            if _s.currHr != _s.time.getHours() #time to emit some average data as our hour has moved on.
          
              
          
              #!mportant - array of hours to catch up on (diff between _s.currHr and _s.time.getHours()
              #as in [21,22,23,0,1]
              
              skippedhrs = []
              counter = _s.currHr
              while counter != _s.time.getHours()
                skippedhrs.push counter
                if counter < 23
                  counter++
                else
                  counter = 0
                  
              #console.log skippedhrs
              #process.exit 1
          
              for currHr in skippedhrs

                for k,v of  _s.consumedAVG

                  console.log "key:#{k} val #{v}"
                
                  for ck,cv of v
                    
                    channel = ck
            
                    avgdb = cv #channel avg
                    sensor = k
                    #process.exit 1

                    harr = avgdb["hourly"][ currHr.toString() ]["data"]
                    if harr?
                      if harr.length > 0
                        htot = harr.reduce (t,s) ->
                          t+s
                        
                        havg = htot / harr.length #the overall hourly average
                        
                        self.emit "average", {"sensor":sensor, "channel": channel, "type":"hourly", "period": currHr, "value": havg}
                        #console.log "havg: #{havg} @ #{currHr}hrs"
                        #console.log '\u0007\u0007'
                        
                        #reset this hour
                        #console.log "Hourly Data Used:", JSON.stringify avgdb["hourly"][ currHr.toString() ]["data"]
                        avgdb["hourly"][ currHr.toString() ]["data"] = []
                        #process.exit 1
                        
                        #accumulate hrly to day
                        darr = avgdb["daily"][ _s.currDy.toString() ]["data"]
                        darr.push havg 

                    #self.putAVGDb(sensor,avgdb)  


                #Are we at a daily cycle point?
                ##if _s.time.getHours() == _s.cycleHr 
                if currHr == _s.cycleHr
                  #cycle for daily        
                  for k,v of  _s.consumedAVG

                    for ck,cv of v
                      
                      channel = ck
              
                      avgdb = cv #channel avg
                    
                      sensor = k

                      darr = avgdb["daily"][ _s.currDy.toString() ]["data"]
                      
                      dtot = 0
                      if darr.length > 0
                        dtot = darr.reduce (t,s) ->
                          t+s
                                
                      #console.log "Daily Total: #{dtot}/#{darr.length}" if self.debug 
                      self.emit "average", {"sensor": sensor, "channel": channel, "type": "daily" , "period": _s.currDy  , "value": dtot }
                      avgdb["weekly"][ "0" ]["data"].push dtot #we will push 7 of these 
                      avgdb["daily"][ _s.currDy.toString() ]["data"] = [] #reset day once emitted

                      #self.putAVGDb(sensor,avgdb)

                  
                          
                  #move to next day
                  _s.currDy += 1
                  if _s.currDy > 6 
                    _s.currDy = 0
                

                
                  #are we also at a weekly cycle  
                  if _s.currDy == _s.cycleDy
                    #we have collected 7 days, so emit week and reset

                    #cycle for daily        
                    for k,v of  _s.consumedAVG

                      for ck,cv of v
                        
                        channel = ck
                
                        avgdb = cv #channel avg
                      
                        sensor = k


                        warr = avgdb["weekly"][ "0" ]["data"]
                        #wtot = 0
                        wtot = warr.reduce (t,s) ->
                          t+s
                              
                        self.emit "average", {"sensor": sensor, "channel": channel, "type": "weekly" , "period": 0  , "value": wtot }
                        avgdb["weekly"][ "0" ]["data"] = []
                  
                        #self.putAVGDb(sensor,avgdb)
            
               
              #END currHr catchup loop  


          #time related post-processing
          if self.emitAverages
            #reset the hour we are in.    
            _s.currHr = _s.time.getHours()
            
            
            
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



    @parser.onattribute = (attr) ->
      # an attribute.  attr has "name" and "value"

    @parser.onend = () ->
      # parser stream is done, and ready to have more stuff written to it.




    #this API only on node 0.10+
    @reader = new stream.Readable()

    @reader._read = (n) ->
      #no body
      
    @reader.pipe @parser #pipe all output we get into parse 

    console.log "creating:", @device if self.debug
    
    match = /(file:)(.*)/i.exec @device
    if match?
      @serialPort = new SerialFile match[2]
      console.log "File Device:", match[2]
    else
      @serialPort = new SerialPort.SerialPort @device, {baudrate: 57600, parser: SerialPort.parsers.raw}

    @serialPort.on "open", () ->

      console.log 'open' if self.debug

      @on 'data' , (data) ->
        if self.logfile? #if we are logging we make sure its written with sync
          fs.appendFileSync self.logfile, data.toString()            #do nothing stub

        #push all data from 'device' into reader, which itself supports the parser stream interface.
        self.reader.push data.toString()

      @on 'end', () ->
        console.log "END communications"
        self.emit 'end'

      @on 'error', (e) ->
        self.emit 'error', e      
        
  processImpulse : () ->

        #NOTE: impulse events contain the 'pseudo-channel' 1, but currently no data is stored on a per channel basis.
  
        self = this
        _s = self._s

        

        if _s.inREALTIME     #pseudo-realtime events

         
          curNow = _s.time

          self.emit "impulse", {time: _s.time, sensor: _s.sensor, channel: _s.channel, id: _s.id, type: _s.sensortype, value: _s.imp , ipu: _s.ipu}

       
          unless _s.impStart[_s.sensor]?  #first time init - so we skip initial event as itmakes no sense to emit it.
            #console.log "First time sensor seeding for sensor: #{_s.sensor}" if self.debug
            _s.impStart[_s.sensor] = _s.imp
            _s.impStartTime[_s.sensor] = new Date(curNow)
            _s.impTime[_s.sensor] = new Date(curNow)
            _s.impLast[_s.sensor] = 0
            self.reading[_s.sensor] ?= 0
            _s.readingBAK[_s.sensor] = self.reading[_s.sensor] #backup reading
            _s.impAvg[_s.sensor] = [] #new avg array
            #console.log "End First time sensor seeding for sensor: #{_s.sensor}" if self.debug
          else

            ###delta of impulse###
            curDelta = (_s.imp - _s.impLast[_s.sensor] )
            avgSecs = ((curNow - _s.impTime[_s.sensor] )/1000)
            #console.log "curNow: #{curNow} impTime: #{_s.impTime[_s.sensor]}"
            consumed = _s.imp - _s.impStart[_s.sensor] #impulses since we started collecting on this instance
            #console.log "consumed: #{consumed} impulses  since imp-start: #{_s.impStart[_s.sensor]}, imp-now: #{_s.imp} pre-reading: #{self.reading[_s.sensor]}" if self.debug
            ###detect and flatten spikes###
            doSpike = false

            if (self.spikeThreshold != 0) and (curDelta > self.spikeThreshold) 
  
              self.emit "impulse-spike", {time: _s.time, sensor: _s.sensor, channel: _s.channel, id: _s.id, type: _s.sensortype, spike: curDelta }
              data = "impulse-spike  #{_s.time.toLocaleTimeString()} prev: #{_s.impLast[_s.sensor]} curr: #{_s.imp} delta: #{curDelta}, tot-consumed: #{consumed}" if self.debug
              console.log data
              fs.appendFileSync debugfile, data + "\r\n"  if (self.debug > 1)         #temp debug


              #we have a spike but do we have enough data to smooth
              doSpike = true
		  
              if (_s.impAvg[_s.sensor].length >= 1) #even average of 1 is better than nothing!!
                
                tot = _s.impAvg[_s.sensor].reduce (t, s) -> 
                  t+s
				
                avg = tot / _s.impAvg[_s.sensor].length
                fs.appendFileSync debugfile,  avg + "\r\n"  if (self.debug > 2)                #temp debug



              if doSpike #take care of spike by using avg
                _s.impStart[_s.sensor] = _s.imp - avg #reset imps as they are no longer considered good
                _s.impLast[_s.sensor] = _s.imp - avg  #reset ditto
				
                curDelta = avg  #curDelta now reassigned to avg, from the normal imp calculation
                ###recalc consumed###
                consumed = avg
                oldRead = self.reading[_s.sensor] #our original old reading 
                self.reading[_s.sensor] = _s.readingBAK[_s.sensor] #restore prev backup
                #reading now contains last good read, hopefully the last event
                _s.impStartTime[_s.sensor] = new Date(curNow) #reset

                data = "reading reset to: #{self.reading[_s.sensor]} from #{oldRead} using average of: #{avg}" if self.debug
                #console.log data
                fs.appendFileSync debugfile, "Impulse correction: " + data + "\r\n"  if (self.debug > 2)              #temp debug
                self.emit "impulse-correction", {time: _s.time, sensor: _s.sensor, channel: _s.channel, id: _s.id, type: _s.sensortype,  oldReading: oldRead, newReading: self.reading[_s.sensor], newDelta: curDelta}
                
              else #we could not flatten spike so we dont generate messages
                _s.impStart[_s.sensor] = _s.imp  # this removes spike but ditches current read data
                _s.impLast[_s.sensor] = _s.imp   # this removes spike "
                _s.impTime[_s.sensor] = new Date(curNow)        #reset
                _s.impStartTime[_s.sensor] = new Date(curNow)   #reset
                self.reading[_s.sensor] = _s.readingBAK[_s.sensor] #we really need some avg adding here as we have 'lost' a reading cycle.
                self.emit "impulse-warning", {time: _s.time, sensor: _s.sensor, channel: _s.channel, id: _s.id, type: _s.sensortype,  newReading: self.reading[_s.sensor]}
                #console.log "skipping spiked events - no avg collected" if self.debug
                return #no events generated!!!
               
			   
              #have have processed a spike and not skipped events
			   

            else #no spike detected, take backup
              readinc = (consumed / _s.ipu) #total since reading last reset or startup
              _s.readingBAK[_s.sensor] = self.reading[_s.sensor] + readinc #and back this data up

             
            #what the meter dial typically shows if 'reading' has been set, otherwise we start from '0', however its decimalised so if your .dials are not 0-9 it will be a decimal representation            

            unless isFinite (curDelta/_s.ipu)  
              console.log "Infinity: #{curDelta} #{_s.ipu}" if self.debug 
              console.log "State: #{JSON.stringify(_s)}"
              throw new Error "Infinity Assertion"

            if doSpike #we calculate the incremental gain from just this event as normal impluses cummulate against a base reading  
              readinc = (curDelta/_s.ipu)
              console.log "Incrementing reading by #{readinc}" if self.debug
			  
            #readinc is either the total since last base reading, or incase of spike it is the 'delta/avg' since the backup was used.
            self.emit "impulse-reading", {time: _s.time, sensor: _s.sensor, channel: _s.channel, id: _s.id, type: _s.sensortype, reading: self.reading[_s.sensor] + readinc, timeFrom: _s.impStartTime[_s.sensor] }

            #keep tracking for average
            if _s.impAvg[_s.sensor].length == 3
              _s.impAvg[_s.sensor].pop()

            _s.impAvg[_s.sensor].push(curDelta)

            #only used for debug
            if self.debug
              tot = _s.impAvg[_s.sensor].reduce (t, s) -> 
                t+s

              #console.log "avgArraylen:#{_s.impAvg[_s.sensor].length} total:#{tot}" if self.debug

          
            #console.log "curDelta: #{curDelta} avgSecs: #{avgSecs} impPerInterval: #{impPerInterval}" if self.debug
            self.emit "impulse-delta", {time: _s.time, sensor: _s.sensor, channel: _s.channel, id: _s.id, type: _s.sensortype, delta: curDelta }

            impPerInterval = (curDelta/avgSecs)*60*60  #pulses per hour at current rate 

            #impulses per hour divide ipu = kwH * 1000 = watts per Hour.
            impavg = Math.floor( (impPerInterval/_s.ipu)*1000  )
            self.emit "impulse-avg", {time: _s.time, sensor: _s.sensor, channel: _s.channel, id: _s.id, type: _s.sensortype, avg: impavg }

            #if doSpike
              #console.log "Post spike calc terminate"
              #process.exit 1

              
              
            if self.emitAverages #we calculate, store and emit average data if appropriate
              #get our averageDB for this sensor
              #console.log "Getting avgobj for #{_s.sensor}"
              avgdb = self.getAVGDb(_s.sensor, _s.channel)
                            

              #collect data for averages
              #work out what hour we are in
              hrly = avgdb["hourly"][ _s.time.getHours().toString() ]["data"]              
              #add our average usage for this reporting period 
              hrly.push( impavg )
              #console.log "#{impavg} stored @ #{_s.time.getHours()}hrs"
                
              self.putAVGDb( _s.sensor, _s.channel, avgdb )  
              
            #emitAverages end  
              
          #always reset this data in loop
          _s.impLast[_s.sensor] = _s.imp
          _s.impTime[_s.sensor] = new Date(curNow)
          #console.log "Store Time: #{_s.impTime[_s.sensor]}" if self.debug
          
#TODO: support history
#        if _s.inHIST
#          #we do some history stuff
#          #but we'll do this later as I dont need it currently          


  getAVGDb : (sensor, channel) ->
    
    db = @_s.consumedAVG[sensor]
    unless db?
      @_s.consumedAVG[sensor] = {}
      
    avgdb = @_s.consumedAVG[sensor][channel]
      
    unless avgdb?
      #console.log "Creating avgobj for #{sensor}"
      avgdb = {
        "weekly":{"0":{"data":[]} },
        "daily":{"0":{"data":[]},"1":{"data":[]},"2":{"data":[]},"3":{"data":[]},"4":{"data":[]},"5":{"data":[]},"6":{"data":[]} }
        ,"hourly":{"0":{"data":[]},"1":{"data":[]},"2":{"data":[]},"3":{"data":[]},"4":{"data":[]},"5":{"data":[]},"6":{"data":[]},"7":{"data":[]},"8":{"data":[]},"9":{"data":[]},"10":{"data":[]},"11":{"data":[]},"12":{"data":[]},"13":{"data":[]},"14":{"data":[]},"15":{"data":[]},"16":{"data":[]}, "17":{"data":[]},"18":{"data":[]}, "19":{"data":[]},"20":{"data":[]},"21":{"data":[]},"22":{"data":[]},"23":{"data":[]} } 
      } 
      @_s.consumedAVG[sensor][channel] = avgdb
    
    #console.log "int avg...", @_s.consumedAVG[sensor]
    #process.exit 1
    return @_s.consumedAVG[sensor][channel]

  putAVGDb : (sensor, channel, db) ->
    @_s.consumedAVG[sensor][channel] = db  
      
      

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




  

