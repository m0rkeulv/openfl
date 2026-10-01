package render;

import openfl.display.Sprite;
import openfl.display.StageQuality;

/**
	One cell of a scene: a rectangle scored on its own, with its own thresholds when they differ from
	the scene's (percent of the cell's pixels, see `Compare`).
**/
typedef Cell =
{
	name:String,
	x:Int,
	y:Int,
	width:Int,
	height:Int,
	?maxOff:Float,
	?maxInterior:Float
}

/**
	A scene builds a picture on the stage and says how to score it: the AIR reference it is compared
	with, the area the reference covers, the channel difference that counts as noise, and the cells with
	the share of pixels each one may have off.
**/
class Scene
{
	public var name:String;
	public var reference:String;
	public var width:Int;
	public var height:Int;
	public var color:Int = 0x808080;
	public var quality:StageQuality = HIGH;
	/** A channel difference up to this is noise and never counts. **/
	public var tolerance:Int = 8;
	/** The share of a cell's pixels that may differ by more than `tolerance`, in percent. **/
	public var maxOff:Float = 0;
	/** The share that may differ away from any edge, in percent (see `Compare.edges`). **/
	public var maxInterior:Float = 0;
	public var cells:Array<Cell> = [];

	public function new() {}

	public function build(root:Sprite):Void {}

	function cell(name:String, x:Int, y:Int, width:Int, height:Int, ?maxOff:Float, ?maxInterior:Float):Void
	{
		cells.push({name: name, x: x, y: y, width: width, height: height, maxOff: maxOff, maxInterior: maxInterior});
	}
}
