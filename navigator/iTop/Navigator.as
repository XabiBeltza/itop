﻿package iTop
{
	import flash.display.*;
	import flash.geom.*;
	import flash.net.*;
	import flash.events.*;
	import iTop.GraphNode;
	import fl.controls.Slider; 
	import fl.events.SliderEvent; 
	import fl.controls.Label; 
	// For callbacks from Javascript
	import flash.external.ExternalInterface;

	// The main canvas
	public class Navigator extends MovieClip
	{
		public var DEBUG:Boolean = false;
		protected var CURRENT_VERSION:String = 'v. 2.0.6';
		protected var m_oLoader:URLLoader;
		protected var m_aNodes:Object;
		protected var m_aLinks:Array;
		protected var m_oRootNode:GraphNode;
		protected var m_oCanvas:NavigatorCanvas;
		public var m_bChildDragging:Boolean;
		
		// Parameters
		protected var m_sStartPosition:String;
		protected var m_sDataUrl:String;
		protected var m_sDetailsUrl:String;
		protected var m_sRelation:String;
		protected var m_sObjClass:String;
		protected var m_sObjId:String;
		protected var m_sExclude:String;
		
		// Constants
		protected var m_RADIUS = 150;
		protected var m_Q = 0.9; // Electrostatic forces coeff
		protected var m_K = 1; // Elastic forces coeff
		protected var m_Kf = 0.7; // Fluid friction coeff
		protected var m_Ks = 30; // Solid friction coeff
		protected var m_KsLowFriction = 10; // Solid friction coeff
		protected var m_KsHighFriction = 30; // Solid friction coeff
		protected var m_deltaT = 0.1; // Interval of time between updates
		protected var m_MAX_ITEMS_PER_ROW = 8;
		protected var m_FOCUS_DELAY_COUNTDOWN; // Number of images to zoom & pan correctly
		protected var m_fZoom:Number;
		protected var m_iIterations:int = 0;
		public var m_bComputationNeeded = true;
		public var m_bAutoPanAndZoom = true;
		public var m_bHighFrictionMode = false;
		protected var m_iNbNodes:int = 0;
		
		// Constructor
		public function Navigator()
		{
			m_aLinks = [];
			m_aNodes = [];
			m_sExclude = '';
			m_fZoom = 1;
			m_Ks = m_KsLowFriction;
			m_oLoader = null;
			initParameters();
			var success = true;
			if (ExternalInterface.available) 
			{
				//Security.allowDomain(loader.contentLoaderInfo.url);
				//the addCallback registers a function to be called from javascript, and this is what you wanted to do:
				try
				{
					ExternalInterface.addCallback("Filter", DoFilter);
				}
				catch(err)
				{
					m_sTitle.text = 'E: '+err.description;
					success = false
				}
			}
			
			if (success)
			{
				//m_sTitle.text = 'Ok...';
				doLoadData();
			}
			else
			{
				m_sTitle.text = 'Failed to addCallback';
			}
			
			addEventListener(Event.ENTER_FRAME, initGraphics);
			//Stop scaling the flash content
			stage.scaleMode = StageScaleMode.NO_SCALE;
		}
		
		function Reset()
		{
			m_aLinks = [];
			for (var i:String in m_aNodes)
			{
				m_oCanvas.removeChild(m_aNodes[i]);
			}
			m_aNodes = [];
			m_bAutoPanAndZoom = true;
			m_bHighFrictionMode = false;
			m_iIterations = 0;
			m_iNbNodes = 0;
			m_bComputationNeeded = true;
			removeEventListener(Event.ENTER_FRAME, drawLines);
			stage.removeEventListener(MouseEvent.MOUSE_DOWN, mouseDown)  
			stage.removeEventListener(MouseEvent.MOUSE_UP, mouseReleased);
			stage.removeEventListener(MouseEvent.MOUSE_WHEEL, mouseWheelHandler);
		}
		
		function DoFilter(sExcludeList:String):void
		{
			//do something
			m_sExclude = sExcludeList;
			doLoadData();
		}

		protected function initParameters():void
		{
			
			m_sDataUrl = ReadParam('xmlUrl', 'c:\\temp\\test.xml');
			//m_sDataUrl = ReadParam('xmlUrl', 'c:\\temp\\test2.xml');
			//m_sDataUrl = ReadParam('xmlUrl', 'c:\\temp\\navigator.xml');
			m_sDetailsUrl = ReadParam('drillUrl', 'http://localhost/pages/UI.php?operation=details');
			m_sRelation = ReadParam('relation', 'impacts');
			m_sObjClass = ReadParam('obj_class', 'DBServerInstance');
			m_sObjId = ReadParam('obj_id', '7');
			m_sStartPosition = ReadParam('start_pos', 'left');
		}
		
		function initGraphics(event:Event):void
		{
			stage.align = 'left';
			m_oCanvas = new NavigatorCanvas(); // All drawings will occur here
			addChild(m_oCanvas); 
			m_oCanvas.scaleX = m_fZoom;
			m_oCanvas.scaleY = m_fZoom;
			// Handle listeners...
			removeEventListener(Event.ENTER_FRAME,initGraphics);
			m_oZoomSlider.value = 100;
			m_oZoomSlider.addEventListener(SliderEvent.CHANGE, onZoomChange);
			m_oVersion.text = CURRENT_VERSION;
		}
		function mouseDown(event:MouseEvent):void 
		{ 
			trace("Click in canvas");
			if (!m_bChildDragging)
			{
				m_bAutoPanAndZoom = false;
				m_oCanvas.startDrag(); 
			}
		}
		
		function mouseReleased(event:MouseEvent):void 
		{ 
			if (!m_bChildDragging)
			{
				m_oCanvas.stopDrag();
				trace('Canvas.x = '+m_oCanvas.x+', Canvas.y = '+m_oCanvas.y); 
			}
		}
		
		function mouseWheelHandler(event:MouseEvent):void
		{
        	trace("mouseWheelHandler delta: " + event.delta);
			var newZoomLevel:Number = m_fZoom;
			if (event.delta > 0)
			{
				newZoomLevel += 0.05;
				if (newZoomLevel < 1.0)
				{
					SetZoomLevel(newZoomLevel);
					m_oZoomSlider.value = Math.round(100*newZoomLevel);
				}
			}
			else
			{
				newZoomLevel -= 0.05;
				if (newZoomLevel > 0.0)
				{
					SetZoomLevel(newZoomLevel);
					m_oZoomSlider.value = Math.round(100*newZoomLevel);
				}
			}
    	}
		
		function onZoomChange(event:SliderEvent):void
		{
			m_bAutoPanAndZoom = false;
    		SetZoomLevel(event.value/100);
		}
		
		function SetZoomLevel(fZoomLevel:Number):void
		{
			m_fZoom = fZoomLevel;
			m_oCanvas.scaleX = m_fZoom;
			m_oCanvas.scaleY = m_fZoom;
		}
		function GetZoomLevel()
		{
			return m_fZoom;
		}
		
		function doLoadData()
		{
			m_sTitle.text = "Loading...";
			m_oPreloader.visible = true;
			m_oZoomSlider.enabled = true;
			var sSeparator:String = '?';
			if (m_sDataUrl.indexOf(sSeparator) != -1)
			{
				sSeparator = '&';
			}
			var myString:String = m_sDataUrl+sSeparator+'relation='+m_sRelation+'&class='+m_sObjClass+'&id='+m_sObjId+'&exclude='+m_sExclude;
			trace("Requesting:"+myString);
			var myXMLURL:URLRequest = new URLRequest(myString);
			if (m_oLoader != null)
			{
				m_oLoader.close();
			}
			m_oLoader = new URLLoader();
			m_oLoader.addEventListener(Event.COMPLETE, onXMLLoadComplete);
			m_oLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onXMLLoadError);
			m_oLoader.addEventListener(IOErrorEvent.IO_ERROR, onXMLLoadError);
			m_oLoader.load(myXMLURL);
		}
		
		function onXMLLoadComplete(event:Event):void
		{
			try
			{
				Reset();
				var myXML:XML = XML(m_oLoader.data);
				//trace("Data loaded." + myXML);
				//trace("===========================");
				parseXMLData(null, myXML, 0, 0);
				m_sTitle.text = decodeEntities(myXML.attribute("title").toString());


				// Initial positions computation
				for(var i=0; i<10; i++)
				{
					UpdatePositions();
				}
				UpdatePanAndZoom(1);
				addEventListener(Event.ENTER_FRAME, drawLines);
				stage.addEventListener(MouseEvent.MOUSE_DOWN, mouseDown)  
				stage.addEventListener(MouseEvent.MOUSE_UP, mouseReleased);
				stage.addEventListener(MouseEvent.MOUSE_WHEEL, mouseWheelHandler);
				//trace('======= Initial Posistions =========');
				//DumpPositions();
			}
			catch(error:IOErrorEvent)
			{
				m_sTitle.text = "I/O Error: unable to load the graph data ("+error+")";
			}
			catch(error:TypeError)
			{
				m_sTitle.text = "Error: unable to load the graph data (Invalid XML data)";
			}
			catch(error:Error)
			{
				m_sTitle.text = "Error: unable to load the graph data ("+error+")";
			}
			finally
			{
				if (m_oPreloader != null)
				{
					m_oPreloader.visible = false;
				}
				m_oZoomSlider.enabled = true;
				m_oVersion.visible = false;
			}
		}

		function onXMLLoadError(event:IOErrorEvent):void
		{
				if (m_oPreloader != null)
				{
					m_oPreloader.visible = false;
				}
				m_sTitle.text = "I/O Error: unable to load the graph data ("+event+")";
		}
		
		function parseXMLData(oParentNode:GraphNode, oXMLData:XML, iChildIndex:Number, iChildCount:Number)
		{
			//trace(oXMLData.child("node").length());
			var oNode:GraphNode;
			oNode  = addNode(oParentNode, oXMLData.child("node")[0], iChildIndex, iChildCount);
			if (oParentNode != null)
			{
				AddLink(oParentNode.GetKey(), oNode.GetKey());
			}
			//trace('Root node:'+oRoot.toString());
			var oLinks = oXMLData.child("node")[0].links;
			var iChildIndex:Number = 0;
			if (oLinks.length() > 0)
			{
				//trace('links: '+oLinks.toString());
				var oLink = oLinks.link;
				for each(var oChild:XML in oLink)
				{
					parseXMLData(oNode, oChild, iChildIndex, oLinks.link.length());
					iChildIndex++;
				}
			}
		}
		
		function decodeEntities(str: String)
		{
			return str.replace(/&amp;/g, '&').replace(/&gt;/g, '>').replace(/&lt;/g, '<').replace(/&quot;/g, '"').replace(/&apos;/g, "'");
		}
		
		function addNode(oParent:GraphNode, oXMLData:XML, iChildIndex:Number, iChildCount:Number)
		{
			var sClass:String  = oXMLData.@obj_class;
			var sClassName:String  = oXMLData.@obj_class_name;
			var iId = oXMLData.@id;
			var sLabel:String = decodeEntities(oXMLData.@name);
			var sIcon:String = oXMLData.@icon;
			var oDetails:Object = {};
			var sZlist:String = oXMLData.@zlist;
			
			var oNode:GraphNode = GetNode(sClass+'/'+iId);
			if (oNode == null)
			{
				// If the node does not already exist, let's create it
				var oPt:Point = GetNextFreePosition(oParent, iChildIndex, iChildCount);
				var sParentKey = null;
				if (oParent != null)
				{
					sParentKey = oParent.GetKey();
				}
				// Read the details
				var aDetails:Array;
				aDetails = sZlist.split(',');
				for(var i:String in aDetails)
				{
					//if (oXMLData.hasOwnProperty('att_'+i))
					//{
						oDetails[aDetails[i]] = oXMLData.attribute('att_'+i).toString();
					//}
				}
				oNode = new GraphNode(this, oPt, sClass, sClassName, iId, sLabel, sIcon, sParentKey, m_fZoom, oDetails);
				if (oParent == null)
				{
					// this is the root node, higlight it
					oNode.MarkAsRoot();
				}
				this.m_aNodes[oNode.GetKey()] = oNode; //Keep it referenced
				m_iNbNodes++;
				if (oParent == null)
				{
					m_oRootNode = oNode;
				}
				m_oCanvas.addChild(oNode);
			}
			return oNode;
			//trace("class: "+sClass+", id: "+iId+", name: "+sLabel+", Icon: "+sIcon);
		}
		
		function GetNode(sKey)
		{
			if (m_aNodes.hasOwnProperty(sKey))
			{
				return m_aNodes[sKey];
			}
			else
			{
				return null;
			}
		}
		
		function GetNextFreePosition(oParent:GraphNode, iChildIndex:Number, iChildCount:Number):Point
		{
			var oPt:Point = GetInitialPosition();
			var angle:Number = GetInitialAngle();
			if (oParent != null)
			{
				oPt.x = oParent.x;
				oPt.y = oParent.y;
				var sGrandParentKey:String = oParent.GetParentKey();
				if (sGrandParentKey != null)
				{
					var oGrandParent:GraphNode = GetNode(sGrandParentKey);
					var dx:Number = oParent.x - oGrandParent.x;
					var dy:Number = oParent.y - oGrandParent.y;
					if ((dx == 0) && (dy == 0))
					{
						angle = GetInitialAngle();
					}
					else
					{
						angle = Math.atan2(dy, dx);
					}
				}
				var nbItemsOnRow:Number = 0;
				var nbRows:Number = 0;
				// Determines the position of this element
				// The elements are placed on circles of maximum  m_MAX_ITEMS_PER_ROW elements per row
				// The last row containing potentially less items
				// nbRows indicates on which row (first row = 0) the item is to be placed
				if (iChildCount > m_MAX_ITEMS_PER_ROW)
				{
					nbRows = Math.floor(iChildIndex / m_MAX_ITEMS_PER_ROW);
					if ( iChildIndex > (Math.floor(iChildCount / m_MAX_ITEMS_PER_ROW)*m_MAX_ITEMS_PER_ROW))
					{
						// node is on the last (incomplete) row
						nbItemsOnRow = (iChildCount % m_MAX_ITEMS_PER_ROW);
					}
					else
					{
						nbItemsOnRow = m_MAX_ITEMS_PER_ROW;
					}
				}				
				else
				{
					if (iChildCount == 2)
					{
						nbItemsOnRow = 4; // Nicer display than everything aligned at 180 deg.
					}
					else
					{
						nbItemsOnRow =  iChildCount;
					}
				}
				var radius = this.m_RADIUS * (1 + nbRows);
				angle += (1 - 2*((1+iChildIndex) % 2))*(Math.floor((1+iChildIndex) / 2))*(2*Math.PI) / nbItemsOnRow;
				
				oPt.x += radius * Math.cos(angle);
				oPt.y += radius * 0.7 * Math.sin(angle); // Ellipse because the labels are written horizontally !
				
				//trace("iChildIndex: "+iChildIndex+" (iChildCount: "+iChildCount+") x: "+oPt.x+" y: "+oPt.y+" sGdParentKey: "+sGrandParentKey);
			}
			return oPt;
		}
		
		function GetInitialPosition():Point
		{
			trace('width: '+stage.stageWidth+' height: '+stage.stageHeight);
			var oPos:Point = new Point(0,0);
			switch(m_sStartPosition)
			{
				case 'left':
				oPos.x = m_RADIUS;
				oPos.y = stage.stageHeight / 2;
				break;
				
				case 'right':
				oPos.x = stage.stageWidth - m_RADIUS;
				oPos.y = stage.stageHeight / 2;
				break;
				
				case 'top':
				oPos.x = stage.stageWidth/2;
				oPos.y = m_RADIUS;
				break;
				
				case 'bottom':
				oPos.x = stage.stageWidth/2;
				oPos.y = stage.stageHeight - m_RADIUS;
				break;
			}
			return oPos;
		}

		function GetInitialAngle():Number
		{
			var angle:Number;
			switch(m_sStartPosition)
			{
				case 'left':
				angle = 0;
				break;
				
				case 'right':
				angle = Math.PI;
				break;
				
				case 'top':
				angle = -Math.PI / 2;
				break;
				
				case 'right':
				angle = Math.PI / 2;
				break;
			}
			return angle;
		}
				
		function AddLink(sStart:String, sEnd:String)
		{
			var oLink = new Link(sStart, sEnd);
			m_aLinks.push(oLink);
		}
		
		function drawLines(event:Event):void
		{
			var color:uint = 0x666666;
			m_oCanvas.graphics.clear();
			
			if (m_bHighFrictionMode)
			{
				// Increase the friction so that manually manipulating objects gets easier
				trace("More friction now...");
				m_Ks = m_KsHighFriction; // 5 times more friction
			}
			else
			{
				m_Ks = m_KsLowFriction;
			}			
			
			if (DEBUG)
			{
				m_oCanvas.graphics.lineStyle(2,0xff3333,100,false,"normal",CapsStyle.ROUND);
				
				var sceneRect:Rectangle = null;
				for(var i:String in this.m_aNodes)
				{
					if (sceneRect == null)
					{
						sceneRect = GetNode(i).getBounds(m_oCanvas);
					}
					else
					{
						sceneRect = sceneRect.union(GetNode(i).getBounds(m_oCanvas));
					}
				}
				if (sceneRect != null)
				{
					/*
					m_oCanvas.graphics.lineStyle(2,0xff0000,100,false,"normal",CapsStyle.ROUND);

					m_oCanvas.graphics.moveTo(-500, 0);
					m_oCanvas.graphics.lineTo(500, 0);

					m_oCanvas.graphics.moveTo(0, -500);
					m_oCanvas.graphics.lineTo(0, 500);

					m_oCanvas.graphics.moveTo(sceneRect.x, sceneRect.y);
					m_oCanvas.graphics.lineTo(sceneRect.x + sceneRect.width, sceneRect.y);
					m_oCanvas.graphics.lineTo(sceneRect.x + sceneRect.width, sceneRect.y + sceneRect.height);
					m_oCanvas.graphics.lineTo(sceneRect.x, sceneRect.y + sceneRect.height);
					m_oCanvas.graphics.lineTo(sceneRect.x, sceneRect.y);
					*/
				}
			}
			
			m_oCanvas.graphics.lineStyle(2,0x666666,100);
			UpdatePositions();
			if (m_bAutoPanAndZoom)
			{
				UpdatePanAndZoom(1);
			}
			
			for (var index:String in m_aLinks)
			{
				
    			var oStartNode:GraphNode = GetNode(m_aLinks[index].GetStart());
				var oEndNode = GetNode(m_aLinks[index].GetEnd());
				
				m_oCanvas.graphics.moveTo(oStartNode.x, oStartNode.y);
				m_oCanvas.graphics.lineTo(oEndNode.x, oEndNode.y);
				
				if (DEBUG)
				{
					m_oCanvas.graphics.drawCircle(oStartNode.x, oStartNode.y, 5);
					m_oCanvas.graphics.drawCircle(oEndNode.x, oEndNode.y, 5);
				}
				var oMiddlePoint:Point = new Point((oEndNode.x+oStartNode.x)/2, (oEndNode.y+oStartNode.y)/2);
				drawArrow(oMiddlePoint, oEndNode.x - oStartNode.x, oEndNode.y - oStartNode.y, color);
			}
		}
		function drawArrow(oPt:Point, dx:Number, dy:Number, color:uint):void
		{
			var l:Number = Math.sqrt(dx*dx+dy*dy);
			var arrowSize:Number = 5;
			if (l > 0)
			{
				m_oCanvas.graphics.lineStyle(2,color,100,false,"normal",CapsStyle.ROUND);
				m_oCanvas.graphics.moveTo(oPt.x, oPt.y);
				m_oCanvas.graphics.lineTo(oPt.x + arrowSize*(dy-dx)/l, oPt.y - arrowSize*(dx+dy)/l);
				m_oCanvas.graphics.moveTo(oPt.x, oPt.y);
				m_oCanvas.graphics.lineTo(oPt.x - arrowSize*(dx+dy)/l, oPt.y - arrowSize*(dy-dx)/l);
			}
		}
		
		public function ReadParam(sName:String, sDefaultValue:String)
		{
			var paramObj:Object = LoaderInfo(this.root.loaderInfo).parameters;
		
			if (paramObj.hasOwnProperty(sName))
			{
				return unescape(paramObj[sName]);
			}
			else
			{
				return sDefaultValue;
			}
		}
		
		public function ComputeElectrostaticForces():Array
		{
			var aForces:Array = [];
			//trace('====== BEGIN ComputeElectrostaticForces() =======');
			
			for (var i:String in this.m_aNodes)
			{
				aForces[i] = new Object;
				aForces[i].FxTotal = 0;
				aForces[i].FyTotal = 0;
				var oCurrentNode:GraphNode = GetNode(i);
				for (var j:String in this.m_aNodes)
				{
					if (i != j)
					{
						var oRemoteNode:GraphNode = GetNode(j);
						var dx:Number = oRemoteNode.x - oCurrentNode.x;
						var dy:Number = oRemoteNode.y - oCurrentNode.y;
						var d2:Number = (dx*dx + dy*dy) / (this.m_RADIUS * this.m_RADIUS);
						var Fx:Number = 0;
						var Fy:Number = 0;
						if (d2 < 0.05)
						{
							d2 = 0.05;
						}
						if (d2 < 2 ) // Full influence under 2 * m_RADIUS px
						{
							Fx = -this.m_Q * dx / d2;
							Fy = -this.m_Q * dy / d2;
							aForces[i].FxTotal += Fx;
							aForces[i].FyTotal += Fy;
						}
						else if (d2 < 4 ) // Decrease the influence to between 4 and 2 * m_RADIUS px
						{
							Fx = -this.m_Q * (4 - d2) * dx / d2;
							Fy = -this.m_Q * (4 - d2) * dy / d2;
							aForces[i].FxTotal += Fx;
							aForces[i].FyTotal += Fy;
						}
					}
				}
			}
			//for (i in this.m_aNodes)
			//{
			//	trace('ELECTROSTATIC forces on '+i+': Fx='+aForces[i].FxTotal+', Fy='+aForces[i].FyTotal);
			//	if (Math.abs(aForces[i].FyTotal) > 1)
			//	{
			//		for (i in this.m_aNodes)
			//		{
			//			var oNode:GraphNode = GetNode(i);
			//			trace('node: '+i+' (x='+oNode.x+', y='+oNode.y+')');
			//		}
			//	}
			//}
			//trace('====== END ComputeElectrostaticForces() =======');
			return aForces;
		}


		function ComputeElasticForces()
		{
			//trace('====== BEGIN ComputeElasticForces() =======');
			var aForces:Array = [];
		
			for (var i:String in this.m_aNodes)
			{
				aForces[i] = new Object;
				aForces[i].FxTotal = 0;
				aForces[i].FyTotal = 0;
			}
			
			// Elastic forces: each link applies a force proportional to its length (F = - K * x)
			for(i in this.m_aLinks)
			{
				trace(i);
    			var oStartNode:GraphNode = GetNode(m_aLinks[i].GetStart());
				var oEndNode = GetNode(m_aLinks[i].GetEnd());
				var dx = oStartNode.x - oEndNode.x;
				var dy = oStartNode.y - oEndNode.y;
				//d = Math.sqrt(dx*dx + dy*dy);
				//Fx = -K * d * dx / d;
				//Fy = -K * d * dy / d;
				//var Fy = -m_K * d * dy / d;
				// Which can be simplified as:
				var Fx = -this.m_K * dx;
				var Fy = -this.m_K * dy;
				// Links with more weight attached are more rigid !
				//weightCoeff = (aWeights[aLinks[l].start] + aWeights[aLinks[l].end])/2;
				aForces[oStartNode.GetKey()].FxTotal += Fx;
				aForces[oStartNode.GetKey()].FyTotal += Fy;
				aForces[oEndNode.GetKey()].FxTotal -= Fx;
				aForces[oEndNode.GetKey()].FyTotal -= Fy;
			}
			//for (i in this.m_aNodes)
			//{
			//	trace('Elastic forces on '+i+': Fx='+aForces[i].FxTotal+', Fy='+aForces[i].FyTotal);
			//	if (Math.abs(aForces[i].FyTotal) > 1)
			//	{
			//		for (i in this.m_aNodes)
			//		{
			//			var oNode:GraphNode = GetNode(i);
			//			trace('node: '+i+' (x='+oNode.x+', y='+oNode.y+')');
			//		}
			//	}
			//}
			//trace('====== END ComputeElasticForces() =======');
			return aForces;
		}
		
		/**
		 * Update the nodes' position based on their current movement and the forces applied
		 */		 		
		function UpdatePositions()
		{
			if (!m_bComputationNeeded)
			{
				trace('Nothing is moving, halting the computation, deltaT='+m_deltaT);
				return; // everything is still, no need to recompute
			}
			//trace('====== BEGIN UpdatePositions() =======');
			var aElasticForces:Array = ComputeElasticForces();
			var aElectrostaticForces:Array = ComputeElectrostaticForces();
			if (DEBUG)
			{
				DrawForces(aElasticForces, 0xcc0000);
				DrawForces(aElectrostaticForces, 0x0000cc);
			}
			var Ks2:Number = this.m_Ks*this.m_Ks;
			var nbNodes:int = 0;
			var dxMax:Number = 0;
			var dyMax:Number = 0;
			var maxAccel2 = 50000.0/(m_fZoom*m_fZoom);
			m_bComputationNeeded = false; // Needed only if something is still moving
			var nextDeltaT = m_deltaT;
			for (var i:String in this.m_aNodes)
			{
				var oNode:GraphNode = GetNode(i);
				if (!oNode.m_bInDrag)
				{
					var Fx:Number = aElasticForces[i].FxTotal + aElectrostaticForces[i].FxTotal;
					var Fy:Number = aElasticForces[i].FyTotal + aElectrostaticForces[i].FyTotal;

					if ( (Fx*Fx + Fy*Fy) < (this.m_Ks*this.m_Ks))
					{
						// Movement is less than minimum level (solid friction) => object is stopped
						// otherwise let's keep it moving
						oNode.m_speed_x = 0;
						oNode.m_speed_y = 0;
						//trace('object '+i+' stopped ! (x='+oNode.x+', y='+oNode.y+')');
					}
					else
					{
						var Ax = this.m_deltaT*Fx;
						var Ay =  this.m_deltaT*Fy;
						if ((Ax * Ax + Ay *Ay) > maxAccel2)
						{
							nextDeltaT = m_deltaT*0.95; // Slow down for the next pass
						}
						oNode.m_speed_x = oNode.m_speed_x*this.m_Kf + this.m_deltaT*Fx;
						oNode.m_speed_y = oNode.m_speed_y*this.m_Kf + this.m_deltaT*Fy;
						
						var dx:int = oNode.m_speed_x * this.m_deltaT;
						var dy:int = oNode.m_speed_y * this.m_deltaT;
						dxMax = Math.max(dxMax, dx);
						dyMax = Math.max(dyMax, dy);
						if ((dx*m_fZoom > 1) || (dx*m_fZoom > 1))
						{
							// visibly moving by more than 1 px
							oNode.x = oNode.x + dx;
							oNode.y = oNode.y + dy;
							m_bComputationNeeded = true;
						}
						//trace('object '+i+' moves (Force: Fx='+Fx+', Fy='+Fy+')! ');
					}
				}
				else
				{
					 m_bComputationNeeded = true;
				}
				nbNodes++;
			}
			m_deltaT = nextDeltaT;
			trace('Iteration: '+(m_iIterations)+', '+nbNodes+' nodes processed. Max displacement dx='+dxMax+', dy='+dyMax);
			m_iIterations++;
			//trace('======= Updated Positions =========');
			//DumpPositions();
			//trace('====== END UpdatePositions() =======');
		}
		
		public function DrawForces(aForces:Array, color:uint)
		{
			for (var i:String in aForces)
			{
				var oNode:GraphNode = GetNode(i);
				var oForce:Object = aForces[i];
				m_oCanvas.graphics.lineStyle(2,color,100,false,"normal",CapsStyle.ROUND);
				m_oCanvas.graphics.moveTo(oNode.x, oNode.y);
				var oEndPoint:Point = new Point;
				oEndPoint.x = oNode.x + oForce.FxTotal;
				oEndPoint.y = oNode.y + oForce.FyTotal;
				m_oCanvas.graphics.lineTo(oEndPoint.x, oEndPoint.y);
				drawArrow(oEndPoint, oForce.FxTotal, oForce.FyTotal, color);
				//trace('Drawinf vector '+i+': (x='+oNode.x+', y='+oNode.y+') to (x='+oEndPoint.x+', y='+oEndPoint.y+')');
			}
		}
		
		public function UpdatePanAndZoom(countDownRatio:Number)
		{
			var sceneRect:Rectangle = null;
			for(var i:String in this.m_aNodes)
			{
				if (sceneRect == null)
				{
					sceneRect = GetNode(i).getBounds(m_oCanvas);
				}
				else
				{
					sceneRect = sceneRect.union(GetNode(i).getBounds(m_oCanvas));
				}
			}
			if (sceneRect != null)
			{
				var idealZoomLevel:Number = 1;
				trace('Stage dimensions: width:'+stage.stageWidth+' height:'+stage.stageHeight);
				
				var wRatio:Number = stage.stageWidth / sceneRect.width;
				var hRatio:Number = (stage.stageHeight - 50) / sceneRect.height;
				idealZoomLevel = Math.min(Math.min(wRatio, hRatio), 1);
				SetZoomLevel(idealZoomLevel);
				m_oZoomSlider.value = Math.round(100*idealZoomLevel);

				var xOffset:Number = 0;
				var yOffset:Number = 0;
				var newWidth:Number = sceneRect.width * idealZoomLevel;
				var newHeight:Number = sceneRect.height * idealZoomLevel;
				
				xOffset = stage.stageWidth/2 - newWidth/2 - sceneRect.x*idealZoomLevel;
				yOffset = 50 + stage.stageHeight/2 - newHeight/2 - sceneRect.y*idealZoomLevel; 
				
				m_oCanvas.x = xOffset;
				m_oCanvas.y = yOffset;
				
				trace('Scene bounding rect: x:'+sceneRect.x+' y:'+sceneRect.y+' width:'+sceneRect.width+' height:'+sceneRect.height+' zoomLevel:'+idealZoomLevel);
			}
		}
		
		public function DumpPositions()
		{
			for (var i:String in this.m_aNodes)
			{
				var oNode:GraphNode = GetNode(i);
				trace(i+' Position: (x='+oNode.x+', y='+oNode.y+')');
			}
		}
	}	
}

class Link extends Object
{
	protected var m_sStart:String;
	protected var m_sEnd:String;
	public function Link(sStartNodeKey:String, sEndNodeKey:String)
	{
		m_sStart = sStartNodeKey;
		m_sEnd = sEndNodeKey;
	}
	
	public function GetStart():String
	{
		return m_sStart;
	}
	public function GetEnd():String
	{
		return m_sEnd;
	}
}

import flash.display.*;
import flash.geom.*;
import flash.events.*;

class NavigatorCanvas extends Sprite
{
	public function NavigatorCanvas()
	{
	}
}
