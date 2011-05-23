/*
Quantcast Flash Tracking ActionScript 3 API.
    Revision 2.1.1 Date Sept 3, 2008.

    Example Usage:  
        var qc = new Quantcast({publisherId: "publisher-id", videoId: "video-id", media:"video"}, this);
		qc.trackMovie(<target>);
    
    Explanation: 
        Creates a new Quantcast video tracker object, and gives us minimal data,
		simply that the movie was loaded and the frame on which you instantiated
		our object loaded.
		
        Calling trackMovie and passing a reference to the video you want to track
		allows the tracker object to listen for events (playheadUpdate, stateChange,
		cuePoint, complete) automatically and pass that information on to the server. 
		
		You may also track events independently, if you like, and call the public 
		methods explicitly.
        

*/

/*	The following changes were made for the JW Player plugin:
	-	All mentions of FLVPlayback have been commented out. They were throwing a compilation error,
		and we're not using trackMovie() anyway, so they're not necessary.
*/


package com.quantcast.as3{
	public class Quantcast {
		import flash.system.*;
		import flash.display.*;
		import flash.net.LocalConnection;
		import flash.net.SharedObject;
		import flash.net.ObjectEncoding;
		import flash.net.URLRequest;
		import flash.net.URLRequestMethod;
		import flash.net.URLVariables;
		import flash.events.NetStatusEvent;
		import flash.events.Event;
		import flash.system.Capabilities;
		import flash.external.ExternalInterface;
/*		import fl.video.FLVPlayback;*/

		private var _rootMC:Object;
		private static var _lcClient:Object = {};
		private var _opts:Object = {};
		private static var _so:SharedObject;

		private var last_PlayheadTime:Number;
		private var last_state:String;

		// For basic tracking, simply call this and pass a reference to your FLVPlayback instance
/*		public function trackMovie(m:FLVPlayback):void {
			m.addEventListener("playheadUpdate", videoPlayheadUpdate);
			m.addEventListener("complete", videoComplete);
			m.addEventListener("stateChange", videoStateChange);
			m.addEventListener("cuePoint", videoCuePoint);
			resetVideo();
		}*/
		//Public Event Methods:
		// These may be used instead of trackMovie, if you wish to do your own event handling
		public function embedded(overrides:Object=null):void{
			qcEvent("embedded",overrides);
		}
		public function played(overrides:Object=null):void{
			qcEvent("played",overrides);
		}
		public function progress(overrides:Object=null):void{
			qcEvent("progress",overrides);
		}
		public function seeked(overrides:Object=null):void{
			qcEvent("seeked",overrides);
		}
		public function clicked(overrides:Object=null):void{
			qcEvent("clicked",overrides);
		}
		public function paused(overrides:Object=null):void{
			qcEvent("paused",overrides);
		}
		public function resumed(overrides:Object=null):void{
			qcEvent("resumed",overrides);
		}
		public function refresh(overrides:Object=null):void{
			qcEvent("refresh",overrides);
		}
		public function update(overrides:Object=null):void{
			qcEvent("update",overrides);
		}
		public function finished(overrides:Object=null):void{
			qcEvent("finished",overrides);
		}
		///////////////////////////////
		// Quantcast API functions ///
		public function Quantcast(options:Object, rtMC:Object) {
			_rootMC = rtMC;// a reference to the main timeline
			var pURL:String = getLocation();// the URL of the page in which the root swf is embedded
			var playerVersion:String = Capabilities.version;// the Flash player version and OS 
			var rootUrl:String = _rootMC.loaderInfo.loaderURL;// the URL of the main SWF
			var qcVersion:String = getQCVersion();// version number of this API
			if (options.server == undefined) {
				options.server = "http://flash.quantserve.com";
			}

			var DEFAULTS:Object = new Object();
			DEFAULTS._clip = rtMC;
			DEFAULTS._com_server = options.server;
			DEFAULTS._com_path = "quant.swf";
			DEFAULTS.url = rootUrl;
			DEFAULTS.qcv = qcVersion;
			DEFAULTS.pageURL = pURL;
			DEFAULTS.allowTrace = false;
			DEFAULTS.flashPlayer = playerVersion;
			DEFAULTS.media = "default";

			_opts = parseOptions(options, DEFAULTS);
			setTrace(_opts, false);
			// set the ObjectEncoding to AMF0, just in case AS2 SWFs need to read 
			// the shared object someday.
			SharedObject.defaultObjectEncoding = ObjectEncoding.AMF0;
			read_so();
			loadCommunicator(_opts);
			embedded(null);
		}
		//// video listening functions //////////////////
		private function videoStateChange(event:Object):void {
			var targ:Object = event.target;
			var dur:Number = Math.floor(targ.totalTime);
			if (targ.state == "playing" && last_state == "paused") {
				// state changed from paused to playing, send resumed event
				last_state = "playing";
				resumed({time:targ.playheadTime*1000, duration:dur});
			} else if (targ.state == "paused" && last_state == "playing") {
				// state changed to paused, send paused event
				paused({time:targ.playheadTime*1000, duration:dur});
				last_state = "paused";
			}
		}
		private function videoPlayheadUpdate(event:Object):void {
			var targ:Object = event.target;
			var dur:Number = Math.floor(targ.totalTime);
			if (targ.state == "buffering") {
				return;
			}
			if (targ.state == "seeking") {
				seeked({time:targ.playheadTime*1000});
				return;
			}
			if (targ.playheadTime > last_PlayheadTime) {
				if (last_PlayheadTime == -1) {
					// send a "played" event if this is the first time 
					// videoPlayheadUpdate has been called
					if (last_state != "playing") {
						played({time:targ.playheadTime*1000, duration:dur});
						last_state = "playing";
					}
				} else {
					// send a progress event
					progress({time:targ.playheadTime*1000, duration:dur});
				}
				last_PlayheadTime = targ.playheadTime;
			}
		}
		private function videoCuePoint(event:Object):void {
			// a cue point has been passed, get the name and send progress event with name (frame)
			var targ:Object = event.target;
			var cuePointName:String = event.info.name.toString();
			progress({time:targ.playheadTime*1000,frame:cuePointName});
		}
		private function videoComplete(event:Object):void {
			var duration:Number = event.target.totalTime;
			finished({duration:duration*1000});
			resetVideo();
		}
		private function resetVideo():void {
			last_PlayheadTime = -1;
			last_state = "";
		}

		private function qcEvent(evname:String, overrides:Object=null):void{
			// handles all events that are to be sent to the server
			if (overrides == null) {
				overrides = {};
			}
			var opts:Object = parseOptions(overrides,_opts);// merges any overrides in with the already-existing options
			opts.event = evname;
			opts._com_path = "pixel.swf";
			opts.fpf = Quantcast._so.data._fpf;
			setTrace(opts,true);
			doSend(['sendEvent',opts],opts._callbackObj,opts._callbackMethod);
		}
		private function doSend(args:Array, cbobj:Object=null, cbfn:Object = null):void {
			if (Quantcast._lcClient._quant_lc_name == null) {
				// If no connection was possible
				if(Quantcast._lcClient.lc == null){
					return;
				}
				// we are not connected with quant.swf yet, 
				// so just add the event to the queue and exit
				var qargs:Array = [];
				for (var i:Number = 0; i < arguments.length; i++) {
					qargs.push(arguments[i]);
				}
				Quantcast._lcClient._queue.push(qargs);
				return;
			}
			// we are connected to quant.swf,
			// so set up the callbacks and send an event.
			// the id just indicates which element in the callback array
			// holds the associated callback object and function
			Quantcast._lcClient._id += 1;
			var id:Number = Quantcast._lcClient._id;
			if (cbfn === null) {
				cbfn = cbobj;
			}
			Quantcast._lcClient._callbacks[id] = [cbobj, cbfn];
			// create a new LocalConection and send a message to quant.swf
			var slc:LocalConnection = new LocalConnection();
			slc.send(Quantcast._lcClient._quant_lc_name, 'rpc', id, args);
		}
		private function loadCommunicator(options:Object):void {
			if (!isNetworkAvailable()) {
				return;
			}


			/// this section makes it so only a single instance of quant.swf will be loaded
			if (typeof(Quantcast._lcClient.lc) != "undefined") {
				xTrace("Quant.swf already loaded. Do forceEmbed");
				// forceEmbed causes quant.swf to send an "impression" event to the server
				doSend(['forceEmbed']);
				return;
			}
			
			// start the receiving LC, to receive messages back from quant.swf //
			startLC(options._com_server);
			options = parseOptions(options, {});
			// create the full URL to quant.swf
			var url:String = options._com_server + "/" + options._com_path;
			delete options._com_server;
			delete options._com_path;
			
			//////// load quant.swf ///////
			var ldr:Loader = new Loader();
			// getData holds all of the info we want to populate quant.swf with initially
			// it will be appended as a GET string after the url
			var getData:URLVariables = new URLVariables();
			getData.lc = Quantcast._lcClient.lc;
			xTrace("----------------------------------");
			for (var k:String in options) {
				var startChar:String= k.substring(0,1);
				if (startChar!='_') {
					getData[k] = options[k];
					xTrace('set opt '+k+' -> '+getData[k]);
				}
			}
			xTrace("----------------------------------");
			var urlReq:URLRequest = new URLRequest(url);
			urlReq.method = URLRequestMethod.GET;
			urlReq.data = getData;
			ldr.load(urlReq);
			// when quant.swf is loaded, do getFPF and send an embedded event
			getFPF(this, _gotTPF);
		}
		private function startLC(hostName:String):void {
			///// set up the localConnection for receiving events from quant.swf/////////////
			var lc:LocalConnection = new LocalConnection();
			lc.allowDomain(hostName);
			var theName:String = makeRand();
			lc.client = Quantcast._lcClient;
			lc.connect(theName);
			// Quantcast._lcClient is the client for this localConnection. 
			// It hold variables and callback functions.
			Quantcast._lcClient._id = 0;
			Quantcast._lcClient._queue = [];
			Quantcast._lcClient.lc = theName;
			Quantcast._lcClient._callbacks = {};
			Quantcast._lcClient._callbacks[0] = [this, '_didConnect'];
			// rpcResult is the only handler that quant.swf calls (via LocalConnection).
			// It passes an integer, which indicates which item in the _callbacks queue to run
			// When quant.swf first runs, it also sends the name of its localConnection (as the second argument) 
			// Otherwise it passes the tpf (third-party shared Object) as the second argument  
			Quantcast._lcClient.rpcResult = function (cbs:String):void{
					// run callback <cb> in the _callbacks queue and reshuffle the queue 
					var cb:Number = parseInt(cbs);
					var cblst:Array = Quantcast._lcClient._callbacks[cb];
					if (!cblst) {
					// there are no callbacks in the queue, so exit
						return;
					}
					delete Quantcast._lcClient._callbacks[cb];
					var args:Array = [];
					for (var i:Number = 2; i < cblst.length; i++) {
						args.push(cblst[i]);
					}
					for (var j:Number = 1; j < arguments.length; j++) {
					// even though the rpcResult function only explicitly accepts one variable (cb)
					// other values may still be passed via the arguments parameter 
						args.push(arguments[j]);
					}
					var method:Object = cblst[1];
					var obj:Object = cblst[0];
					if (obj && typeof(method) == 'string') {
						method = obj[method];
					}
					if (obj && method) {
						method.apply(obj, args);
					}
			};
		}
		
		private function _didConnect(q_lc_name:String):void {
			// the first time quant.swf runs it send the name of its incoming LocalConnection
			// This is what allows the API to send it messages
			xTrace("connected: "+ q_lc_name);
			// Once the quant.swf's localConnection name is received, 
			// Send all messages in the queue
			Quantcast._lcClient._quant_lc_name = q_lc_name;
			var ds:Function = doSend;
			var item:Object = Quantcast._lcClient._queue[0];
			delete Quantcast._lcClient._queue[0];
			ds.apply(this, item);
		}
		private function _gotTPF(tpf:String):void {
			// got the data from quant.swf with the contents of the third-party
			// shared object. Make the first-party shared object match this.
			Quantcast._so.data._fpf = tpf;
			_opts.fpf = tpf;
			write_so();
			xTrace("got tpf "+tpf);
			
			var q:Array = Quantcast._lcClient._queue;
			delete Quantcast._lcClient._queue;
			var ds:Function = doSend;
			for (var i:Number = 1; i < q.length; i++) {
				var item:Object = q[i];
				if(typeof(item) != "undefined"){
					if(item[0][0] == "sendEvent"){
						item[0][1].fpf = tpf;
					}
					ds.apply(this, item);
				}
			}
		}

		private function getFPF(/* optional */callbackObj:Object, callbackMethod:Object):void {
			// ask quant.swf to get the contents of the third-party shared object
			doSend(['getFPF'],callbackObj,callbackMethod);
		}
		
		private function getQCVersion():String {
			return "2.1.1";
		}
		private function isNetworkAvailable():Boolean {
			if (Security) {
				var a:String = Security.sandboxType;
				if (Security.sandboxType == "localWithFile") {
					return false;
				}
			}
			return true;
		}
		private function parseOptions(options:Object, defaults:Object):Object {
			// merge the passed options with the passed defaults
			var optcopy:Object = {};
			for (var k:String in defaults) {
				optcopy[k] = defaults[k];
			}
			if (options) {
				for (var j:String in options) {
					optcopy[j] = options[j];
				}
			}
			/* Allow a flashvars override */
			// get the FlashVars, if any, and add them in to options
			var paramObj:Object = LoaderInfo(_rootMC.loaderInfo).parameters;
			for (var p:String in paramObj) {
				var v:String = paramObj[p];
				optcopy[unescape(p)] = unescape(v);
			}
			if (_opts) {
				_opts.duration = optcopy.duration;
			}
			return optcopy;
		}
		private function setTrace(options:Object, always:Boolean):void {
			if(typeof (options.allowTrace) != "undefined"){
				if(options.allowTrace == false || always){
					delete options.allowTrace;
				}
			}
		}
		// Shared object reading and writing
		private function read_so():void {
			//Look for a shared object and set _fpf if found
			try {
				Quantcast._so = SharedObject.getLocal("com.quantserve", "/");
				if (typeof (Quantcast._so.data._fpf) != "undefined") {
					_opts.fpf = Quantcast._so.data._fpf;
					xTrace("read _fpf"+_opts.fpf);
				} else {
					xTrace("fpf is undefined");
					_opts.fpf = "";
				}
			} catch (err:Error) {
				xTrace("Shared Object (FPF) read error: "+err);
			}
		}
		private function write_so():void {
			xTrace("Attempting to save Shared Object...");
			var flushStatus:String = null;
			try {
				flushStatus = Quantcast._so.flush(51200);
			} catch (error:Error) {
				xTrace("Error...Could not write SharedObject to disk");
			}
			if (flushStatus != null) {
				switch (flushStatus) {
					case "pending" :
						xTrace("Requesting permission to save object...");
						Quantcast._so.addEventListener(NetStatusEvent.NET_STATUS, pendingFlushHandler);
						break;
					case "flushed" :
						xTrace("Shared object flushed to disk.");
						break;
						otherwise:xTrace("Shared object could not be flushed to disk.");
				}
			}
		}
		private function pendingFlushHandler(e:NetStatusEvent):void {
			if (e.info.code == "SharedObject.Flush.Success") {
				xTrace("User granted permission -- shared object saved.");
			} else {
				xTrace("User denied permission -- shared object not saved.");
			}
		}
		private function getLocation():String{
			try {
				// attempt to use a JavaScript call, via ExternalInterface, to get the URL of the
				// page in which the SWF is embedded. Will only work if allowScriptAccess is set to 
				// sameDomain (if the swf is in the same domain) or "always"
				if (ExternalInterface.available) {
					var getLocJS:String = "function getLoc() { return window.location.toString(); }";
					var embedURL:String = ExternalInterface.call( getLocJS );
					return embedURL;
				}
			} catch (error:Error) {
				xTrace("ExternalInterface error");
			}
			return "";
		}
		private function makeRand():String {
			// makes a random name for the localConnection, based on the date and time
			var d:Date = new Date();
			return ["",Math.floor(d.getTime()),Math.round(Math.random() * 10000)].join("_");
		}
		private function xTrace(msg:String):void {
			if (_opts.allowTrace) {
				trace(msg);
			}
		}
		
	}
}
