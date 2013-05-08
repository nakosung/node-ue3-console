(function() {
  var CodeDepot, async, events, redis, redisClient, _, _ref,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  _ = require('underscore');

  events = require('events');

  async = require('async');

  redis = require('redis');

  redisClient = redis.createClient();

  redisClient.on('error', function() {
    return console.error('redis is not accessible, please run redis at localhost');
  });

  CodeDepot = (function(_super) {
    __extends(CodeDepot, _super);

    function CodeDepot() {
      _ref = CodeDepot.__super__.constructor.apply(this, arguments);
      return _ref;
    }

    CodeDepot.prototype.load = function(key, cb) {
      var _this = this;

      return async.parallel([
        function(cb) {
          return redisClient.get("code-" + key, cb);
        }, function(cb) {
          return redisClient.get("title-" + key, cb);
        }
      ], function(err, result) {
        var code, title;

        if (err) {
          return cb(err, result);
        } else {
          code = result[0], title = result[1];
          return cb(null, {
            code: code,
            title: title || "untitled"
          });
        }
      });
    };

    CodeDepot.prototype.discard = function(key, cb) {
      var _this = this;

      return async.parallel([
        function(cb) {
          return redisClient.lrem("code-list", 0, key, cb);
        }, function(cb) {
          return redisClient.del("code-" + key, cb);
        }, function(cb) {
          return redisClient.del("title-" + key, cb);
        }
      ], function(err, result) {
        _this.emit('invalidate');
        return cb(null, null);
      });
    };

    CodeDepot.prototype.save = function(doc, cb) {
      var key, sha1,
        _this = this;

      sha1 = require('sha1');
      key = sha1(doc.code);
      return async.parallel([
        function(cb) {
          return redisClient.set("code-" + key, doc.code, cb);
        }, function(cb) {
          return redisClient.lrem("code-list", 0, key, cb);
        }, function(cb) {
          return redisClient.lpush("code-list", key, cb);
        }, function(cb) {
          return redisClient.set("title-" + key, doc.title || "untitled", cb);
        }
      ], function(err, result) {
        _this.emit('invalidate');
        return cb(null, key);
      });
    };

    CodeDepot.prototype.list = function(options, cb) {
      var end, start;

      start = (options != null ? options.start : void 0) || 0;
      end = (options != null ? options.end : void 0) || 10;
      return redisClient.lrange("code-list", start, end, function(err, ids) {
        if (err) {
          return cb(err, ids);
        } else {
          return async.map(ids, (function(key, cb) {
            return redisClient.get("title-" + key, cb);
          }), function(err, titles) {
            if (err) {
              return cb(err, titles);
            } else {
              return cb(null, _.zip(ids, titles).map(function(x) {
                var id, title;

                id = x[0], title = x[1];
                return {
                  id: id,
                  title: title || "untitled"
                };
              }));
            }
          });
        }
      });
    };

    return CodeDepot;

  })(events.EventEmitter);

  exports.CodeDepot = CodeDepot;

}).call(this);

/*
//@ sourceMappingURL=depot.js.map
*/