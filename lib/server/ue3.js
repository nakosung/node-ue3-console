(function() {
  var Bridge, Class, Fiber, Hosts, Object, async, events, fiber_exec, net, ue3prim, _,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    __slice = [].slice;

  net = require('net');

  events = require('events');

  _ = require('underscore');

  Fiber = require('fibers');

  async = require('async');

  ue3prim = require('./ue3prim');

  fiber_exec = function(body, cb) {
    var done, fiber, out_result, waiting;

    if (!_.isFunction(cb)) {
      fiber = Fiber.current;
      if (fiber) {
        out_result = null;
        done = false;
        waiting = false;
        body(function(result) {
          out_result = result;
          done = true;
          if (waiting) {
            return fiber.run();
          }
        });
        waiting = true;
        if (!done) {
          Fiber["yield"]();
        }
        return out_result;
      } else {
        return null;
      }
    } else {
      return body(cb);
    }
  };

  Bridge = (function(_super) {
    __extends(Bridge, _super);

    function Bridge(trid) {
      this.trid = trid != null ? trid : 0;
      this.objects = {};
      this.buffer = "";
    }

    Bridge.prototype.init = function(client, done) {
      var _this = this;

      this.client = client;
      client.on('data', function(data) {
        var i, str, trid, _results;

        _this.buffer += data.toString();
        _results = [];
        while (true) {
          str = _this.getLine();
          if (!str) {
            break;
          }
          i = str.indexOf(' ');
          trid = parseInt(str.substr(0, i));
          _results.push(_this.emit(trid, str.substr(i + 1)));
        }
        return _results;
      });
      client.on('close', function() {
        return _this.emit('close');
      });
      return done();
    };

    Bridge.prototype.getLine = function() {
      var i, result;

      i = this.buffer.indexOf("\r\n");
      if (i < 0) {
        return null;
      } else {
        result = this.buffer.substr(0, i);
        this.buffer = this.buffer.substr(i + 2);
        return result;
      }
    };

    Bridge.prototype.send = function() {
      var args, body, buf, cb, command, my_trid, _i,
        _this = this;

      args = 2 <= arguments.length ? __slice.call(arguments, 0, _i = arguments.length - 1) : (_i = 0, []), cb = arguments[_i++];
      command = args.join(' ');
      my_trid = this.trid++;
      buf = "" + my_trid + " " + command + "\r\n";
      body = function(cb) {
        _this.once(my_trid, cb);
        return _this.client.write(buf);
      };
      return fiber_exec(body, cb);
    };

    Bridge.prototype.read = function(target, field, cb) {
      return this.send(target, 'read', field, cb);
    };

    Bridge.prototype.write = function(target, field, value, cb) {
      return this.send(target, 'write', field, value, cb);
    };

    Bridge.prototype.exec = function(target, command, cb) {
      return this.send(target, 'exec', command, cb);
    };

    Bridge.prototype.getSuperClassOfClass = function(classId, cb) {
      var _this = this;

      return this.send(classId, 'super', function(superClassId) {
        var o;

        o = _this.objects[superClassId];
        if (o || superClassId === "#-1") {
          return cb(o);
        } else {
          return _this.readClass(superClassId, cb);
        }
      });
    };

    Bridge.prototype.readClass = function(classId, cb) {
      var _this = this;

      return this.getSuperClassOfClass(classId, function(superClass) {
        var adaptor;

        adaptor = function(cb) {
          return function(result) {
            return cb(null, result);
          };
        };
        return async.parallel([
          function(cb) {
            return _this.read(classId, 'name', adaptor(cb));
          }, function(cb) {
            return _this.send(classId, 'listprop', adaptor(cb));
          }, function(cb) {
            return _this.send(classId, 'listfunc', adaptor(cb));
          }
        ], function(err, results) {
          var className, cls, funcs, props;

          className = results[0], props = results[1], funcs = results[2];
          props = _.without(props.split(','), '');
          funcs = _.without(funcs.split(','), '');
          cls = new Class(_this, classId, className, superClass, props, funcs);
          return cb(cls);
        });
      });
    };

    Bridge.prototype.getClass = function(id, cb) {
      var _this = this;

      return this.send(id, 'class', function(classId) {
        var cls;

        cls = _this.objects[classId];
        if (cls) {
          return cb(cls);
        } else {
          return _this.readClass(classId, cb);
        }
      });
    };

    Bridge.prototype.access = function(id, cb) {
      var body,
        _this = this;

      body = function(cb) {
        var o;

        if (id === "#-1") {
          return cb(null);
        } else {
          o = _this.objects[id];
          if (o) {
            return cb(o);
          } else {
            return _this.getClass(id, function(result) {
              return cb(_this.create(result, id));
            });
          }
        }
      };
      return fiber_exec(body, cb);
    };

    Bridge.prototype.create = function(classObject, id) {
      var o;

      o = new classObject.UEObjectClass(this, id);
      this.objects[id] = o;
      return o;
    };

    return Bridge;

  })(events.EventEmitter);

  Object = (function() {
    function Object(bridge, id, _class) {
      this.bridge = bridge;
      this.id = id;
      this["class"] = _class;
    }

    Object.prototype.read = function(field, cb) {
      var body,
        _this = this;

      body = function(cb) {
        return _this.bridge.read(_this.id, field, function(result) {
          return ue3prim.from(result, _this.bridge, cb);
        });
      };
      return fiber_exec(body, cb);
    };

    Object.prototype.write = function(field, value, cb) {
      return this.bridge.write(this.id, field, ue3prim.to(value), cb);
    };

    Object.prototype.exec = function(command, cb) {
      return this.bridge.exec(this.id, command, cb);
    };

    return Object;

  })();

  Class = (function(_super) {
    __extends(Class, _super);

    function Class(bridge, id, name, superClass, props, funcs) {
      var BaseClass, UEObject, self, _ref;

      this.bridge = bridge;
      this.id = id;
      this.name = name;
      this.superClass = superClass;
      this.props = props;
      this.funcs = funcs;
      Class.__super__.constructor.call(this, this.bridge, this.id, null);
      self = this;
      BaseClass = ((_ref = this.superClass) != null ? _ref.UEObjectClass : void 0) || Object;
      UEObject = (function(_super1) {
        __extends(UEObject, _super1);

        function UEObject(bridge, id, _class) {
          this.bridge = bridge;
          this.id = id;
          this["class"] = _class;
        }

        UEObject.prototype.toString = function() {
          return "" + self.name + "_" + this.id;
        };

        return UEObject;

      })(BaseClass);
      this.UEObjectClass = UEObject;
      this.declareMethodsAndProperties(this.UEObjectClass.prototype);
    }

    Class.prototype.declareMethodsAndProperties = function(target) {
      var func, prop, _fn, _i, _j, _len, _len1, _ref, _ref1, _results;

      _ref = this.props;
      _fn = function(prop) {
        target.__defineGetter__(prop, function() {
          return this.read(prop);
        });
        return target.__defineSetter__(prop, function(value) {
          return this.write(prop, value);
        });
      };
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        prop = _ref[_i];
        _fn(prop);
      }
      _ref1 = this.funcs;
      _results = [];
      for (_j = 0, _len1 = _ref1.length; _j < _len1; _j++) {
        func = _ref1[_j];
        _results.push((function(func) {
          return target[func] = function() {
            var args;

            args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
            args = args.map(ue3prim.to);
            return this.exec([func, args.join(' ')].join(' '));
          };
        })(func));
      }
      return _results;
    };

    return Class;

  })(Object);

  Hosts = (function(_super) {
    __extends(Hosts, _super);

    function Hosts(BridgeClass) {
      this.BridgeClass = BridgeClass != null ? BridgeClass : Bridge;
      this.bridges = [];
    }

    Hosts.prototype.connect = function(opts) {
      var client, reconnect,
        _this = this;

      reconnect = function() {
        console.log('trying to reconect');
        return setTimeout((function() {
          return _this.connect(opts);
        }), 1000);
      };
      client = net.connect(opts, function() {
        var bridge;

        bridge = new _this.BridgeClass();
        bridge.opts = opts;
        return bridge.init(client, function() {
          console.log('connected');
          _this.bridges.push(bridge);
          bridge.on('close', function() {
            _this.bridges = _.without(_this.bridges, bridge);
            _this.emit('disconnect', bridge);
            return reconnect();
          });
          return _this.emit('connect', bridge);
        });
      });
      return client.on('error', function(err) {
        return reconnect();
      });
    };

    return Hosts;

  })(events.EventEmitter);

  exports.Hosts = Hosts;

  exports.Bridge = Bridge;

}).call(this);

/*
//@ sourceMappingURL=ue3.js.map
*/