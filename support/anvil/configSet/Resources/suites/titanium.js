/*
 * Appcelerator Titanium Mobile
 * Copyright (c) 2011-2012 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
 
module.exports = new function() {
	var finish;
	var valueOf;
	this.init = function(testUtils) {
		finish = testUtils.finish;
		valueOf = testUtils.valueOf;
	}

	this.name = "titanium";
	this.tests = [
		{name: "buildHash"},
		{name: "userAgent"},
		{name: "analytics"}
	]

	this.buildHash = function(testRun) {
		valueOf(testRun, Titanium.buildHash.length).shouldBe(7);

		finish(testRun);
	}

	this.userAgent = function(testRun) {
		valueOf(testRun, Titanium.userAgent).shouldBeString();
		valueOf(testRun, Titanium.userAgent.indexOf("Titanium")).shouldBeNumber();

		finish(testRun);
	}

	//TIMOB-1915
	this.analytics = function(testRun) {
		valueOf(testRun, function(){
			Ti.Analytics.featureEvent("myevent1");
			Ti.Analytics.featureEvent("myevent2", {extraData: "test"});
		}).shouldNotThrowException();
		
		finish(testRun);
	}
}
