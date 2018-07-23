#!/bin/bash

var fs = require("fs");
//console.log("Please store the write-waiting-times-file as tmp.csv in current folder");

var d = fs.readFileSync("tmp.csv").toString().split("\n");
var times = [];

for(var i = 0; i < d.length-1; i += 3) {
  var t1 = new Date(d[i].split(" IST ")[0]);
  var t2 = new Date(d[i+1].split(" IST ")[0]);
  var diff = t2-t1;
  var blockingReaders1 = d[i].match(/BlockingR: (\d+)/)[1];
  var blockedReaders1 = d[i].match(/BlockedR: (\d+)/)[1];
  var blockingReaders2 = d[i+1].match(/BlockingR: (\d+)/)[1];
  var blockedReaders2 = d[i+1].match(/BlockedR: (\d+)/)[1];
  console.log(t1, +blockingReaders1, diff);
  times.push({t1, t2, diff, blockingReaders1, blockingReaders2, blockedReaders1, blockedReaders2});
}

times.sort((a,b)=>a.diff-b.diff);
//console.log(JSON.stringify(times));
