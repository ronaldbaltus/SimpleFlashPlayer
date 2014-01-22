package 
{
	import flash.display.Bitmap;
	import flash.display.Loader;
	import flash.display.LoaderInfo;
	import flash.display.Sprite;
	import flash.display.StageAlign;
	import flash.display.StageScaleMode;
	import flash.events.AsyncErrorEvent;
	import flash.events.Event;
	import flash.events.NetStatusEvent;
	import flash.events.StatusEvent;
	import flash.events.IOErrorEvent;
	import flash.events.MouseEvent;
	import flash.net.NetConnection;
	import flash.net.NetStream;
	import flash.net.URLRequest;
	import flash.system.Security;
	import flash.media.Video;
	import flash.external.ExternalInterface;
	
	/**
	 * @author Ronald Baltus
	 */
	public class Main extends Sprite 
	{
		
        private var stageWidth:int = 0;
        private var stageHeight:int = 0;
		
		private var video:Video = null;
		private var netConnection:NetConnection;
		private var netStream:NetStream;
		
		private var thumb:Bitmap = null;
		
		private var videoUrl:String = "";
		private var thumbUrl:String = null;
		
		private var resizing:Boolean = false;
		private var securityPolicyLoaded:Boolean = false;
		private var videoLoaded:Boolean = false;
		
		public function Main():void 
		{
			if (stage) init();
			else addEventListener(Event.ADDED_TO_STAGE, init);
		}
		
		private function init(e:Event = null):void 
		{
			removeEventListener(Event.ADDED_TO_STAGE, init);
			
			// entry point
			stage.scaleMode = StageScaleMode.NO_SCALE;
			stage.align = StageAlign.TOP_LEFT;
			scaleX = 1.0;
			scaleY = 1.0;
			
			// Parameters
			videoUrl = String(stage.loaderInfo.parameters["url"]);
			thumbUrl = String(stage.loaderInfo.parameters["thumb"]);
			
			if (thumbUrl !== "") {
				initializeThumbnail();
			}
			
			initializeVideo();
		
			onResize();
			
			stage.addEventListener(MouseEvent.CLICK, function():void {
				trigger('click');
			});
			
			buttonMode = true;
			useHandCursor = true;
			tabEnabled = false;
		}

		/**
		 * Show thumbnail.
		 */
		private function initializeThumbnail():void
		{
			var thumbLoader:Loader = new Loader();
			thumbLoader.x = 0;
			thumbLoader.y = 0;
			thumbLoader.width = 100;
			thumbLoader.height = 100;
			
			thumbLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, function(event:Event):void {
				try {
					thumb = Bitmap(thumbLoader.content);
					
					if (!videoLoaded) {
						addChild(thumb);
					}
				} catch (error:SecurityError) {
					if (securityPolicyLoaded) {
						throw error;
						
						return;
					}
					
					if (videoLoaded) {
						return;
					}
					
					securityPolicyLoaded = true;
					loadPolicy(thumbUrl);
					
					// try again
					thumbLoader.load(new URLRequest(thumbUrl));
					
					return;
				}
				
				onResize();
				
				trigger('thumb');
			});
			
			thumbLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void {
				trigger('error', 'thumbnail');
			});
			
			try {
				thumbLoader.load(new URLRequest(thumbUrl));
			} catch (error:SecurityError) {
				trigger('error', 'thumbnail security error');
			}
		}
		
		/**
		 * Initialie the video properties
		 */
		private function initializeVideo():void
		{
			// initialize net connection
			netConnection = new NetConnection;
			netConnection.connect(null);
			
			// initialize netstream
			netStream = new NetStream(netConnection);
			netStream.addEventListener(AsyncErrorEvent.ASYNC_ERROR, onAsyncErrorHandler);
			netStream.addEventListener(NetStatusEvent.NET_STATUS, onNetStatus);
			
			netStream.play(videoUrl);
			
			// initialize the actual video
			video = new Video();
			video.attachNetStream(netStream);	
			
			stage.addEventListener(Event.RESIZE, onResize);
			
			initializeExternalInterface();
		}
		
		/**
		 * Initialize the external interface
		 */
		private function initializeExternalInterface():void
		{
			if (!ExternalInterface.available) {
				trace('No external interface available!');
				
				return;
			}
						
			ExternalInterface.addCallback('play', function():void {
				netStream.seek(0);
				netStream.resume();
			});
			
			ExternalInterface.addCallback('pause', function():void {
				netStream.pause();
			});
			
			ExternalInterface.addCallback('stop', function():void {
				netStream.pause();
				netStream.seek(0);
			});
			
			trigger('ready');
		}
		
		/**
		 * Trigger an event on the html element
		 * @param	eventName
		 * @param	args
		 */
		private function trigger(eventName:String, args:Object = null):void
		{
			if (!ExternalInterface.available) {
				trace('No external interface available!');
				
				return;
			}
			
			var js:String = 'document.getElementById("' + ExternalInterface.objectID + '").on' + eventName.toLowerCase() + '';
			
			ExternalInterface.call(js, args);
		}
		
		/**
		 * Async Error handler
		 * 
		 * @param	event
		 */
		private function onAsyncErrorHandler(event:AsyncErrorEvent):void
		{
			trace("Async error: ", event.text);
			trigger('error', event.text);
		}
		
		/**
         * The flash component is being resized
         * @param Event e
         */
        private function onResize(e:Event = null):void
        {
			if (resizing) {
				return;
			}
			
			resizing = true;
			
            stageWidth = stage.stageWidth;
            stageHeight = stage.stageHeight;

            stage.scaleMode = StageScaleMode.EXACT_FIT;

			if (video !== null) {
				video.width = stageWidth;
				video.height = stageHeight;
			}
			
			if (thumb !== null) {
				thumb.width = stageWidth;
				thumb.height = stageHeight;
			}

            stage.scaleMode = StageScaleMode.NO_SCALE;
			
			resizing = false;
        }
		
		/**
		 * On net status
		 * 
		 * @param	e
		 */
		private function onNetStatus(e:NetStatusEvent):void 
		{
			switch (e.info.code) {
				case 'NetStream.Play.Start':
					trace('play', netStream.bufferLength);
					if (null !== thumb) {
						removeChild(thumb);
					}
					
					videoLoaded = true;
					addChild(video);
					
					trigger('play');
					
					break;
				case 'NetStream.Play.Stop':
					trace('stop');
					trigger('stop');
					
					break;
				case 'NetStream.Buffer.Full':
					trace('buffer full', netStream.bufferLength);
					trigger('buffer', 'full');
					
					break;
				case 'NetStream.Play.StreamNotFound':
					trace('stream not found');
					trigger('error', 'stream not found');
					
					break;
			}
		}
		
		/**
		 * Load policy
		 * @param	url
		 */
		private function loadPolicy(url:String):void
		{
			var domainPattern:RegExp = new RegExp("https?://[^/]+/");
			var found:Object = domainPattern.exec(url);
			var loaderDomain:String = found[0];
			
			trace('loading policy', loaderDomain + 'crossdomain.xml');
			Security.loadPolicyFile(loaderDomain + 'crossdomain.xml');
			
			if( 0 == loaderDomain.indexOf('https') )
			{
				Security.allowDomain(loaderDomain);
			}
			else
			{
				Security.allowInsecureDomain(loaderDomain)
			}
		}
	}
	
}