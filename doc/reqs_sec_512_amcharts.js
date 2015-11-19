var chart = AmCharts.makeChart("chartdiv", {
  "type": "serial",
  "theme": "light",
  "marginRight": 70,
  "dataProvider": [{
    "server": "EVHTP",
    "reqs/sec": 215542.92,
    "color": "#FF0F00"
  }, {
    "server": "Starlet",
    "reqs/sec": 94178.97,
    "color": "#FF6600"
  }, {
    "server": "Gazelle",
    "reqs/sec": 128921.80,
    "color": "#FF9E01"
  }],
  "valueAxes": [{
    "axisAlpha": 0,
    "position": "left",
    "title": "Reqs/sec",
    "minimum": 0
  }],
  "startDuration": 1,
  "graphs": [{
    "balloonText": "<b>[[category]]: [[value]]</b>",
    "fillColorsField": "color",
    "fillAlphas": 0.9,
    "lineAlpha": 0.2,
    "type": "column",
    "valueField": "reqs/sec"
  }],
  "chartCursor": {
    "categoryBalloonEnabled": false,
    "cursorAlpha": 0,
    "zoomable": false
  },
  "categoryField": "server",
  "categoryAxis": {
    "gridPosition": "start",
    "labelRotation": 45
  },
  "export": {
    "enabled": true
  }

});
