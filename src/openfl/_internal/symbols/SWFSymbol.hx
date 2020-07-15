package openfl._internal.symbols;

import haxe.Unserializer;
import haxe.Serializer;
import openfl._internal.formats.swf.SWFLite;
import openfl.display.DisplayObject;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:keepSub class SWFSymbol
{
	public var className:String;
	public var id:Int;

	public function new() {}

	private function __createObject(swf:SWFLite):DisplayObject
	{
		return null;
	}

	@:keep
	function hxSerialize(s:Serializer) {
		s.serialize(className);
		s.serialize(id);

	}

	@:keep
	function hxUnserialize(u:Unserializer) {

		className = u.unserialize();
		id = u.unserialize();


	}
}
