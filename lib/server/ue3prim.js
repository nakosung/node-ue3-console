(function() {
  var UEPrim, Vector3, from_unrealengine3, to_unrealengine3, _,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  _ = require('underscore');

  UEPrim = (function() {
    function UEPrim() {}

    UEPrim.prototype["export"] = function() {
      throw "NOTIMPL";
    };

    return UEPrim;

  })();

  Vector3 = (function(_super) {
    __extends(Vector3, _super);

    function Vector3(X, Y, Z) {
      this.X = X;
      this.Y = Y;
      this.Z = Z;
    }

    Vector3.prototype["export"] = function() {
      return "(X={@X},Y={@Y},Z={@Z})";
    };

    return Vector3;

  })(UEPrim);

  from_unrealengine3 = function(text, bridge, cb) {
    var num, vec3;

    if (text[0] === '#') {
      return bridge.access(text, function(o) {
        return cb(o);
      });
    } else {
      num = parseFloat(text);
      if (_.isNaN(num)) {
        vec3 = /\(X=([0-9]+\.[0-9]+),Y=([0-9]+\.[0-9]+),Z=([0-9]+\.[0-9]+)\)/.exec(text);
        console.log(vec3);
        if (vec3) {
          return cb(new Vector3(parseFloat(vec3[1]), parseFloat(vec3[2]), parseFloat(vec3[3])));
        } else {
          return cb(text);
        }
      } else {
        return cb(num);
      }
    }
  };

  to_unrealengine3 = function(value) {
    if (value instanceof UEPrim) {
      return value["export"]();
    } else {
      return value;
    }
  };

  exports.from = from_unrealengine3;

  exports.to = to_unrealengine3;

}).call(this);

/*
//@ sourceMappingURL=ue3prim.js.map
*/