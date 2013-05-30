// Generated by CoffeeScript 1.6.2
/*
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
*/

/*
    CHANGELOG
    2013-05-30 initial upload to github @0.9.0
*/

var CurrentCost128XMLBaseStation, EventEmitter, SerialPort, sax, stream,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

EventEmitter = require('events').EventEmitter;

SerialPort = require('serialport');

sax = require('sax');

stream = require('stream');

CurrentCost128XMLBaseStation = (function(_super) {
  __extends(CurrentCost128XMLBaseStation, _super);

  CurrentCost128XMLBaseStation.prototype.serialport = null;

  CurrentCost128XMLBaseStation.prototype.reader = null;

  CurrentCost128XMLBaseStation.prototype.parser = null;

  CurrentCost128XMLBaseStation.prototype._s = {
    inMSG: false,
    inREALTIME: false,
    inHIST: false,
    inID: false,
    id: null,
    inSRC: false,
    src: null,
    inDSB: false,
    dsb: null,
    inSENSOR: false,
    sensor: "",
    inTMPR: false,
    temp: 0,
    inCH: false,
    channel: 0,
    inWATTS: false,
    watts: 0,
    inTIME: false,
    time: null,
    inSENSORTYPE: false,
    sensortype: null,
    inIMP: false,
    imp: null,
    inIPU: false,
    ipu: null,
    impStart: {},
    impLast: {},
    impTime: {}
  };

  CurrentCost128XMLBaseStation.prototype.emitbase = true;

  function CurrentCost128XMLBaseStation(device, _arg) {
    var self, _ref, _ref1, _ref2, _ref3, _ref4;

    this.device = device;
    _ref = _arg != null ? _arg : {}, this.useOSTime = _ref.useOSTime, this.emitBaseEvery = _ref.emitBaseEvery, this.debug = _ref.debug, this.reading = _ref.reading;
    if ((_ref1 = this.useOSTime) == null) {
      this.useOSTime = false;
    }
    if ((_ref2 = this.emitBaseEvery) == null) {
      this.emitBaseEvery = 60;
    }
    if ((_ref3 = this.debug) == null) {
      this.debug = false;
    }
    if ((_ref4 = this.reading) == null) {
      this.reading = {};
    }
    if (this.debug) {
      console.log("useOSTime " + this.useOSTime);
      console.log("emitBaseEvery " + this.emitBaseEvery);
      console.log("debug " + this.debug);
      console.log("reading " + this.reading);
    }
    self = this;
    this.parser = sax.createStream(false, {
      lowercasetags: true,
      trim: true
    });
    this.parser.onerror = function(e) {
      if (self.debug) {
        console.error("error!", e);
      }
      this.error = null;
      return this.resume();
    };
    this.parser.ontext = function(t) {
      var hms, _s;

      _s = self._s;
      if (_s.inSENSOR) {
        _s.sensor = t;
        _s.inSENSOR = false;
      }
      if (_s.inID) {
        _s.id = t;
        _s.inID = false;
      }
      if (_s.inDSB) {
        _s.dsb = t;
        _s.inDSB = false;
      }
      if (_s.inSRC) {
        _s.src = t;
        _s.inSRC = false;
      }
      if (_s.inTMPR) {
        _s.temp = parseFloat(t);
        _s.inTMPR = false;
      }
      if (_s.inTIME) {
        hms = t.split(':');
        _s.time = new Date();
        if (!self.useOSTime) {
          _s.time.setHours(hms[0]);
          _s.time.setMinutes(hms[1]);
          _s.time.setSeconds(hms[2]);
        }
        _s.inTIME = false;
      }
      if (_s.inSENSORTYPE) {
        _s.sensortype = t;
        _s.inSENSORTYPE = false;
      }
      if (_s.inIMP) {
        _s.imp = parseFloat(t);
        _s.inIMP = false;
      }
      if (_s.inIPU) {
        _s.ipu = parseFloat(t);
        _s.inIPU = false;
      }
      if (_s.inWATTS) {
        return _s.watts = parseFloat(t);
      }
    };
    this.parser.onopentag = function(node) {
      var match, _s;

      _s = self._s;
      if (node.name === 'msg') {
        _s.inMSG = true;
        _s.inREALTIME = true;
      }
      if (_s.inMSG) {
        if (node.name === 'hist') {
          _s.inHIST = true;
          _s.inREALTIME = false;
          if (self.debug) {
            console.log(">>IN HIST");
          }
        }
        if (node.name === 'dsb') {
          _s.inDSB = true;
        }
        if (node.name === 'src') {
          _s.inSRC = true;
        }
        if (node.name === 'id') {
          _s.inID = true;
        }
        if (node.name === 'sensor') {
          _s.inSENSOR = true;
        }
        if (node.name === 'tmpr') {
          _s.inTMPR = true;
        }
        if (node.name === 'time') {
          _s.inTIME = true;
        }
        if (node.name === 'type') {
          _s.inSENSORTYPE = true;
        }
        if (node.name === 'imp') {
          _s.inIMP = true;
        }
        if (node.name === 'ipu') {
          _s.inIPU = true;
        }
        match = /^ch(\d)/.exec(node.name);
        if (match) {
          _s.inCH = true;
          _s.channel = match[1];
        }
        if (_s.inCH) {
          if (node.name === 'watts') {
            return _s.inWATTS = true;
          }
        }
      }
    };
    this.parser.onclosetag = function(tagName) {
      var avgSecs, consumed, curDelta, curNow, impPerInterval, _base, _name, _ref5, _s;

      _s = self._s;
      if (tagName === 'msg') {
        _s.inMSG = false;
        _s.inREALTIME = false;
        if (self.emitbase) {
          self.emit("base", {
            time: _s.time,
            src: _s.src,
            dsb: _s.dsb,
            temp: _s.temp
          });
          self.emitbase = false;
          setTimeout((function() {
            return self.emitbase = true;
          }), 1000 * self.emitBaseEvery);
        }
      }
      if (tagName === 'hist') {
        _s.inHIST = false;
        _s.inREALTIME = true;
        if (self.debug) {
          console.log(">>OUT HIST");
        }
      }
      if (tagName === 'watts') {
        _s.inWATTS = false;
      }
      if (tagName.indexOf('ch') === 0) {
        _s.inCH = false;
        self.emit("sensor", {
          time: _s.time,
          sensor: _s.sensor,
          id: _s.id,
          channel: _s.channel,
          watts: _s.watts
        });
      }
      if (tagName === 'ipu') {
        if (_s.inREALTIME) {
          self.emit("impulse", {
            time: _s.time,
            sensor: _s.sensor,
            id: _s.id,
            type: _s.sensortype,
            value: _s.imp,
            ipu: _s.ipu
          });
          curNow = Date.now();
          if (_s.impStart[_s.sensor] === void 0) {
            _s.impStart[_s.sensor] = _s.imp;
            _s.impTime[_s.sensor] = curNow;
            _s.impLast[_s.sensor] = 0;
            if ((_ref5 = (_base = self.reading)[_name = _s.sensor]) == null) {
              _base[_name] = 0;
            }
          } else {
            consumed = _s.imp - _s.impStart[_s.sensor];
            self.emit("impulse-reading", {
              time: _s.time,
              sensor: _s.sensor,
              id: _s.id,
              type: _s.sensortype,
              reading: self.reading[_s.sensor] + (consumed / _s.ipu)
            });
            curDelta = _s.imp - _s.impLast[_s.sensor];
            avgSecs = (curNow - _s.impTime[_s.sensor]) / 1000;
            impPerInterval = (curDelta / avgSecs) * 60 * 60;
            self.emit("impulse-delta", {
              time: _s.time,
              sensor: _s.sensor,
              id: _s.id,
              type: _s.sensortype,
              delta: curDelta
            });
            self.emit("impulse-avg", {
              time: _s.time,
              sensor: _s.sensor,
              id: _s.id,
              type: _s.sensortype,
              avg: Math.floor((impPerInterval / _s.ipu) * 1000)
            });
          }
          _s.impLast[_s.sensor] = _s.imp;
          return _s.impTime[_s.sensor] = curNow;
        }
      }
    };
    this.parser.onattribute = function(attr) {};
    this.parser.onend = function() {};
    this.reader = new stream.Readable();
    this.reader._read = function(n) {};
    this.reader.pipe(this.parser);
    if (self.debug) {
      console.log("creating:", this.device);
    }
    this.serialPort = new SerialPort.SerialPort(this.device, {
      baudrate: 57600,
      parser: SerialPort.parsers.raw
    });
    this.serialPort.on("open", function() {
      if (self.debug) {
        console.log('open');
      }
      return this.on('data', function(data) {
        return self.reader.push(data.toString());
      });
    });
  }

  CurrentCost128XMLBaseStation.prototype.close = function() {
    this.serialPort.close();
    this.parser.end();
    this.serialPort = null;
    this.reader = null;
    this.parser = null;
    this.removeAllListeners('sensor').removeAllListeners('impulse').removeAllListeners('impulse-reading').removeAllListeners('impulse-delta').removeAllListeners('impulse-avg');
    if (this.debug) {
      console.log("base --end--");
    }
  };

  return CurrentCost128XMLBaseStation;

})(EventEmitter);

module.exports.CurrentCost128XMLBaseStation = CurrentCost128XMLBaseStation;