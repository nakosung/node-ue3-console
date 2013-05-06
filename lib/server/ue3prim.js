(function() {
  var Rotator, UEPrim, Vector3, from_unrealengine3, to_unrealengine3, _,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  _ = require('underscore');

  UEPrim = (function() {
    function UEPrim() {}

    UEPrim.prototype["export"] = function() {
      throw "NOTIMPL";
    };

    UEPrim.prototype.toString = function() {
      return this["export"]();
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
      return "(X=" + this.X + ",Y=" + this.Y + ",Z=" + this.Z + ")";
    };

    return Vector3;

  })(UEPrim);

  Rotator = (function(_super) {
    __extends(Rotator, _super);

    function Rotator(Pitch, Yaw, Roll) {
      this.Pitch = Pitch;
      this.Yaw = Yaw;
      this.Roll = Roll;
    }

    Rotator.prototype["export"] = function() {
      return "(Pitch=" + this.Pitch + ",Yaw=" + this.Yaw + ",Roll=" + this.Roll + ")";
    };

    return Rotator;

  })(UEPrim);

  from_unrealengine3 = function(text, bridge, cb) {
    var num, rot, vec3;

    if (text[0] === '#') {
      return bridge.access(text, function(o) {
        return cb(o);
      });
    } else {
      vec3 = /\(X=(\-?\d+(\.\d+)?),Y=(\-?\d+(\.\d+)?),Z=(\-?\d+(\.\d+)?)/.exec(text);
      if (vec3) {
        return cb(new Vector3(parseFloat(vec3[1]), parseFloat(vec3[3]), parseFloat(vec3[5])));
      } else {
        rot = /\(Pitch=(\d+),Yaw=(\d+),Roll=(\d+)\)/.exec(text);
        if (rot) {
          return cb(new Rotator(parseInt(rot[1]), parseInt(rot[2]), parseInt(rot[3])));
        } else {
          num = parseFloat(text);
          if (_.isNaN(num)) {
            return cb(text);
          } else {
            return cb(num);
          }
        }
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

  exports.Vector3 = Vector3;

  exports.Rotator = Rotator;

  exports.from = from_unrealengine3;

  exports.to = to_unrealengine3;

}).call(this);

/*
//@ sourceMappingURL=ue3prim.js.map
*/