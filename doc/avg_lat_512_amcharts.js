var chart = AmCharts.makeChart("chartdiv", {
  "type": "serial",
  "theme": "light",
  "marginRight": 70,
  "dataProvider": [{
    "server": "EVHTP",
    "latency": 3.27,
    "color": "#FF0F00"
  }, {
    "server": "Starlet",
    "latency": 0.08273,
    "color": "#FF6600"
  }, {
    "server": "Gazelle",
    "latency": 4.44,
    "color": "#FF9E01"
  }],
  "valueAxes": [{
    "axisAlpha": 0,
    "position": "left",
    "title": "Avg latency (ms)",
    "minimum": 0
  }],
  "startDuration": 1,
  "graphs": [{
    "balloonText": "<b>[[category]]: [[value]]</b>",
    "fillColorsField": "color",
    "fillAlphas": 0.9,
    "lineAlpha": 0.2,
    "type": "column",
    "valueField": "latency"
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
