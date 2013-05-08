(function() {
  var Bridge, ClientConnection, ClientSideFiles, CodeDepot, Fiber, Hosts, RichBridge, app, async, clientFiles, connections, depot, echo, events, express, fs, getAddresses, hosts, server, sockjs, vm, _, _ref, _ref1,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    __slice = [].slice;

  events = require('events');

  _ = require('underscore');

  Fiber = require('fibers');

  async = require('async');

  CodeDepot = require('./depot').CodeDepot;

  fs = require('fs');

  _ref = require('./ue3'), Bridge = _ref.Bridge, Hosts = _ref.Hosts;

  vm = require('vm');

  ClientSideFiles = (function(_super) {
    __extends(ClientSideFiles, _super);

    function ClientSideFiles() {
      var tell,
        _this = this;

      tell = function(e, f) {
        if (e) {
          console.log('client file changed', e, f);
          return _this.emit('change');
        }
      };
      fs.watch('lib/client', tell);
      fs.watch('public', tell);
    }

    return ClientSideFiles;

  })(events.EventEmitter);

  clientFiles = new ClientSideFiles();

  RichBridge = (function(_super) {
    __extends(RichBridge, _super);

    function RichBridge() {
      _ref1 = RichBridge.__super__.constructor.apply(this, arguments);
      return _ref1;
    }

    RichBridge.prototype.init = function(client, done) {
      var _this = this;

      return RichBridge.__super__.init.call(this, client, function() {
        var sequence, wko, wko_names;

        wko_names = 'LocalPC WorldInfo';
        wko = {};
        sequence = wko_names.split(' ').map(function(k) {
          return function(cb) {
            return _this.access(k, function(o) {
              wko[k] = o;
              return cb();
            });
          };
        });
        return async.parallel(sequence, function() {
          _this.sandbox = {
            WorldInfo: wko.WorldInfo,
            pc: wko.LocalPC,
            _: _,
            access: function(x) {
              return _this.access(x);
            },
            log: function() {
              var args;

              args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
              return _this.log(args.toString());
            },
            sleep: function(ms) {
              return sleep(ms);
            },
            chart: function(x, y) {
              if (!y) {
                y = x;
                x = wko.WorldInfo.TimeSeconds;
              }
              return _this.log(JSON.stringify({
                plot: {
                  x: x,
                  y: y
                }
              }));
            }
          };
          return done();
        });
      });
    };

    RichBridge.prototype.name = function() {
      return JSON.stringify(this.opts);
    };

    RichBridge.prototype.log = function(text) {
      return this.emit('data', text);
    };

    RichBridge.prototype.runScriptInFiber = function(v, cb) {
      var fiber, fiberMain, health, result, sandbox, timer,
        _this = this;

      health = true;
      sandbox = _.clone(this.sandbox);
      timer = fiber = null;
      sandbox.sleep = function(msec) {
        fiber = Fiber.current;
        timer = setTimeout((function() {
          return fiber.run();
        }), msec);
        Fiber["yield"]();
        timer = fiber = null;
        if (!health) {
          throw "User halted";
        }
      };
      result = null;
      fiberMain = function() {
        var e;

        try {
          result = String(vm.runInNewContext(v, sandbox));
        } catch (_error) {
          e = _error;
          result = "Exception:" + (e.toString());
        }
        return cb(null, {
          log: result
        });
      };
      Fiber(fiberMain).run();
      return {
        stop: function() {
          health = false;
          if (timer) {
            clearTimeout(timer);
            return fiber.run();
          }
        }
      };
    };

    return RichBridge;

  })(Bridge);

  hosts = new Hosts(RichBridge);

  depot = new CodeDepot();

  connections = [];

  ClientConnection = (function() {
    function ClientConnection(conn) {
      var closeConnection, invalidateHosts, updateCodeList,
        _this = this;

      this.conn = conn;
      connections.push(this);
      this.watches = [];
      this.watchValues = {};
      updateCodeList = function() {
        return _this.send({
          invalidated: true
        });
      };
      closeConnection = function() {
        _this.send({
          refresh: true
        });
        return _this.conn.close();
      };
      clientFiles.once('change', closeConnection);
      depot.on('invalidate', updateCodeList);
      invalidateHosts = function() {
        if (!_this.bridge) {
          _this.setBridge(null);
        }
        return _this.send({
          hosts: _this.getHostList()
        });
      };
      hosts.on('connect', invalidateHosts);
      hosts.on('disconnect', invalidateHosts);
      this.conn.on('close', function() {
        _this.setBridge(null);
        hosts.removeListener('connect', invalidateHosts);
        hosts.removeListener('disconnect', invalidateHosts);
        clientFiles.removeListener('change', closeConnection);
        depot.removeListener('invalidate', updateCodeList);
        return connections = _.without(connections, _this);
      });
      this.conn.on('data', function(msg) {
        console.log('received msg', msg);
        return _this.handleMessage(JSON.parse(msg), function(err, result) {
          if (err) {
            return _this.send({
              log: err
            });
          } else {
            return _this.send(result);
          }
        });
      });
      this.setBridge(null);
      hosts.on('connect', function() {
        if (!_this.bridge) {
          return _this.setBridge(null);
        }
      });
    }

    ClientConnection.prototype.setBridge = function(new_bridge) {
      var log, _ref2,
        _this = this;

      if (new_bridge == null) {
        new_bridge = hosts.bridges[0];
      }
      log = function(text) {
        return _this.send({
          log: text
        });
      };
      if (this.bridge) {
        this.bridge.removeListener('data', log);
      }
      this.bridge = new_bridge;
      if (this.bridge) {
        this.bridge.on('data', log);
        this.bridge.on('close', function() {
          return _this.setBridge(null);
        });
      }
      return this.send({
        host: ((_ref2 = this.bridge) != null ? _ref2.name() : void 0) || null
      });
    };

    ClientConnection.prototype.send = function(json) {
      return this.conn.write(JSON.stringify(json));
    };

    ClientConnection.prototype.handleMessage = function(msg, cb) {
      var code, i, index, k, v, _results,
        _this = this;

      _results = [];
      for (k in msg) {
        v = msg[k];
        switch (k) {
          case 'run':
            if (this.bridge) {
              this.send({
                running: true
              });
              code = require('coffee-script').compile(v);
              _results.push(this.script = this.bridge.runScriptInFiber(code, function(err, result) {
                _this.script = null;
                _this.send({
                  running: false
                });
                return cb(err, result);
              }));
            } else {
              _results.push(cb('no connection'));
            }
            break;
          case 'stop':
            if (this.script) {
              _results.push(this.script.stop());
            } else {
              _results.push(void 0);
            }
            break;
          case 'save':
            _results.push(depot.save(v, function(key) {
              return cb(null, {
                log: "code saved",
                active: key
              });
            }));
            break;
          case 'discard':
            _results.push(depot.discard(v, cb));
            break;
          case 'load':
            _results.push(depot.load(v, function(err, result) {
              if (err) {
                return cb(err, result);
              } else {
                return cb(null, {
                  code: result.code,
                  title: result.title,
                  active: v
                });
              }
            }));
            break;
          case 'list':
            _results.push(depot.list(v, function(err, result) {
              if (err) {
                return cb(err, result);
              } else {
                return cb(null, {
                  list: result
                });
              }
            }));
            break;
          case 'hosts':
            _results.push(cb(null, {
              hosts: this.getHostList()
            }));
            break;
          case 'host':
            i = this.getHostList().indexOf(v);
            if (i >= 0) {
              this.setBridge(hosts.bridges[i]);
              _results.push(cb(null, {
                log: 'switching host...'
              }));
            } else {
              _results.push(cb('invalid host'));
            }
            break;
          case 'connect':
            hosts = this.getHostList();
            index = hosts.indexOf(v);
            if (index < 0) {
              _results.push(cb('invalid host'));
            } else {
              this.setBridge(hosts.bridges[index]);
              _results.push(cb(null, "host seleceted"));
            }
            break;
          case 'watch':
            i = this.watches.indexOf(v);
            if (i < 0) {
              this.watches.push(v);
            }
            _results.push(cb(null, "ok"));
            break;
          case 'unwatch':
            this.watches = _.without(this.watches, v);
            _results.push(cb(null, "ok"));
            break;
          default:
            _results.push(void 0);
        }
      }
      return _results;
    };

    ClientConnection.prototype.tick = function() {
      var watch, _i, _len, _ref2, _results,
        _this = this;

      if (this.bridge) {
        _ref2 = this.watches;
        _results = [];
        for (_i = 0, _len = _ref2.length; _i < _len; _i++) {
          watch = _ref2[_i];
          _results.push((function(watch) {
            return _this.bridge.runScriptInFiber("" + watch, function(err, result) {
              var value;

              value = result.log;
              if (_this.watchValues[watch] !== value) {
                _this.watchValues[watch] = value;
                return _this.send({
                  watch: {
                    key: watch,
                    val: value
                  }
                });
              }
            });
          })(watch));
        }
        return _results;
      }
    };

    ClientConnection.prototype.getHostList = function() {
      return hosts.bridges.map(function(x) {
        return x.name();
      });
    };

    return ClientConnection;

  })();

  express = require('express');

  sockjs = require('sockjs');

  app = express();

  app.use('/', express["static"]('public'));

  app.use('/lib', express["static"]('lib/client'));

  server = require('http').createServer(app);

  echo = sockjs.createServer();

  echo.on('connection', function(conn) {
    return new ClientConnection(conn);
  });

  echo.installHandlers(server, {
    prefix: '/echo'
  });

  server.listen(3338);

  getAddresses = function() {
    var address, addresses, interfaces, k, k2, os, _i, _j, _len, _len1, _ref2;

    os = require('os');
    interfaces = os.networkInterfaces();
    addresses = [];
    for (_i = 0, _len = interfaces.length; _i < _len; _i++) {
      k = interfaces[_i];
      _ref2 = interfaces[k];
      for (_j = 0, _len1 = _ref2.length; _j < _len1; _j++) {
        k2 = _ref2[_j];
        address = interfaces[k][k2];
        addresses.push(address.address);
      }
    }
    return addresses;
  };

  console.log(getAddresses());

  hosts.connect({
    port: 1336
  });

  setInterval((function() {
    var connection, _i, _len, _results;

    _results = [];
    for (_i = 0, _len = connections.length; _i < _len; _i++) {
      connection = connections[_i];
      _results.push(connection.tick());
    }
    return _results;
  }), 100);

}).call(this);

/*
//@ sourceMappingURL=main.js.map
*/