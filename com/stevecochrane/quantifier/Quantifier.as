package com.stevecochrane.quantifier {

	import com.jeroenwijering.events.*;
	import com.quantcast.as3.*
	import flash.display.MovieClip;

	public class Quantifier extends MovieClip implements PluginInterface {

		//	Reference to the plugin flashvars.
		public var config:Object = {
			quantcastid: 'null',
			videoid: 'null',
			videotitle: 'null'
		};		
		//	Reference to the View of the player.
		private var view:AbstractView;
		//	Reference to the Quantcast object.
		private var qc:Quantcast;
		//	A flag that indicates when a played event has been sent.
		private var playEventSent:Boolean = false;
		
		//	This function is automatically called by the player after the plugin has loaded.
		public function initializePlugin(vw:AbstractView):void {
			trace("Initializing the Quantifier plugin...");
			
			//	This will be our reference to the JW Player object.
			view = vw;

			//	And this will be our reference to the JW Player plugin variables.
			if (view.config['quantifier.quantcastid']) {
				config['quantcastid'] = view.config['quantifier.quantcastid'];
			}
			if (view.config['quantifier.videoid']) {
				config['videoid'] = view.config['quantifier.videoid']
			}
			if (view.config['quantifier.videotitle']) {
				config['videotitle'] = view.config['quantifier.videotitle']
			}

			//	This allows us to listen for player events.
			view.addModelListener(ModelEvent.STATE,stateHandler);
			
			//	This initializes the Quantcast object.
			//	We'll actually track events when we need to with stateHandler.
			qc = new Quantcast({publisherID: config['quantcastid'], videoID: config['videoid'], title: config['videotitle'], media: "video"}, this);

			//	This event gets fired when the player is loaded, which is now.
			trace("Submitting an 'embedded' event to Quantcast.");
			qc.embedded();
		};
		
		// 	This function is called each time the playback state changes. 
		private function stateHandler(evt:ModelEvent):void {
			//	If the video begins to play, and the flag indicates that it has not been hit yet...
			if (evt.data.newstate == ModelStates.PLAYING && playEventSent == false) {
				//	Submit a played event to Quantcast, and flip the flag to true,
				//	so that no future played events are sent.
				trace("Submitting a 'played' event to Quantcast.");
				qc.played();
				playEventSent = true;
			}
		};
	};
}