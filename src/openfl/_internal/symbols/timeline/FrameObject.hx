package openfl._internal.symbols.timeline;

import haxe.Unserializer;
import haxe.Serializer;
import openfl._internal.formats.swf.FilterType;
import openfl.display.BlendMode;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class FrameObject
{
	public var blendMode:BlendMode;
	public var cacheAsBitmap:Null<Bool>;
	public var clipDepth:Int;
	public var colorTransform:ColorTransform;
	public var depth:Int;
	public var filters:Array<FilterType>;
	public var id:Int;
	public var matrix:Matrix;
	public var name:String;
	public var symbol:Int;
	public var type:FrameObjectType;
	public var visible:Null<Bool>;

	public function new() {}

	@:keep
	function hxSerialize(s:Serializer) {
		s.serialize(blendMode);
		s.serialize(cacheAsBitmap);
		s.serialize(clipDepth);
		s.serialize(colorTransform);
		s.serialize(depth);
		s.serialize(filters);
		s.serialize(id);
		s.serialize(matrix);
		s.serialize(name);
		s.serialize(symbol);
		s.serialize(type);
		s.serialize(visible);
	}

	@:keep
	function hxUnserialize(u:Unserializer) {

		blendMode = u.unserialize();
		cacheAsBitmap = u.unserialize();
		clipDepth = u.unserialize();
		colorTransform = u.unserialize();
		depth = u.unserialize();
		filters = u.unserialize();
		id = u.unserialize();
		matrix = u.unserialize();
		name = u.unserialize();
		symbol = u.unserialize();
		type = u.unserialize();
		visible = u.unserialize();

	}

}
