(function() {
  var app;

  app = angular.module('node', ['ui', 'ui.bootstrap']);

  app.directive('xychart', function() {
    var color, height, margin, width;

    margin = 20;
    width = 200;
    height = 200 - .5 - margin;
    color = d3.interpolateRgb("#f77", "#77f");
    return {
      restrict: 'E',
      terminal: true,
      scope: {
        val: '='
      },
      link: function(scope, element, attrs) {
        var vis, watchBody;

        vis = d3.select(element[0]).append('svg').attr('width', width).attr('height', height + margin + 100);
        watchBody = function(newVal, oldVal) {
          var line, x, xx, y, yy;

          vis.selectAll('*').remove();
          xx = _.pluck(newVal, 'x').map(parseFloat);
          yy = _.pluck(newVal, 'y').map(parseFloat);
          x = d3.scale.linear().domain([d3.min(xx), d3.max(xx)]).range([0, width]);
          y = d3.scale.linear().domain([d3.min(yy), d3.max(yy)]).range([height, 0]);
          line = d3.svg.line().x(function(d) {
            return parseFloat(x(d.x));
          }).y(function(d) {
            return parseFloat(y(d.y));
          });
          return vis.append('svg:path').attr('d', line(newVal));
        };
        return scope.$watch('val', watchBody, true);
      }
    };
  });

  app.factory('node', function($rootScope) {
    var Server;

    Server = (function() {
      function Server() {
        this.plot = [];
        this.code = "log 'Hello world'";
        this.logs = "Connecting...\n";
        this.handleConnectionLost();
      }

      Server.prototype.updateAngularJs = function() {
        return !$rootScope.$$phase && $rootScope.$apply();
      };

      Server.prototype.handleConnectionLost = function() {
        var _this = this;

        this.list = null;
        this.active = null;
        this.online = false;
        this.print("Trying to connect");
        this.sock = new SockJS('/echo');
        this.sock.onopen = function() {
          return _this.initSock();
        };
        return this.sock.onclose = function() {
          return _this.handleConnectionLost();
        };
      };

      Server.prototype.initSock = function() {
        var _this = this;

        this.online = true;
        this.print('Connected to node.js');
        this.send({
          list: null
        });
        this.send({
          hosts: null
        });
        return this.sock.onmessage = function(e) {
          var data, k, o, plotted, v;

          data = JSON.parse(e.data);
          for (k in data) {
            v = data[k];
            switch (k) {
              case "refresh":
                window.location.reload();
                break;
              case "log":
                plotted = false;
                try {
                  o = JSON.parse(v);
                  if (o.plot) {
                    _this.plot.push(o.plot);
                    plotted = true;
                  }
                } catch (_error) {
                  e = _error;
                }
                if (!plotted) {
                  _this.print(v);
                }
                break;
              case "code":
              case "title":
              case "active":
              case "list":
              case "hosts":
              case "host":
                _this[k] = v;
                break;
              case "invalidated":
                _this.send({
                  list: null
                });
            }
          }
          return _this.updateAngularJs();
        };
      };

      Server.prototype.refresh = function() {
        return window.location.refresh();
      };

      Server.prototype.send = function(json) {
        return this.sock.send(JSON.stringify(json));
      };

      Server.prototype.load = function(target) {
        return this.send({
          load: target
        });
      };

      Server.prototype.discard = function(target) {
        return this.send({
          discard: target
        });
      };

      Server.prototype.save = function() {
        return this.send({
          save: {
            code: this.code,
            title: this.title
          }
        });
      };

      Server.prototype.run = function() {
        this.plot = [];
        this.updateAngularJs();
        return this.send({
          run: this.code
        });
      };

      Server.prototype.print = function(msg) {
        console.log(msg);
        this.logs += msg + "\n";
        return this.updateAngularJs();
      };

      return Server;

    })();
    return new Server();
  });

  app.controller('CodeCtrl', function($scope, node) {
    $scope.server = node;
    $scope.status = function() {
      if (node.online) {
        return "ONLINE";
      } else {
        return "OFFLINE";
      }
    };
    return $(document).keydown(function(e) {
      if (e.keyCode === 66 && e.ctrlKey) {
        node.run();
        false;
      }
      if (e.keyCode === 83 && e.ctrlKey) {
        node.save();
        return false;
      }
    });
  });

}).call(this);
