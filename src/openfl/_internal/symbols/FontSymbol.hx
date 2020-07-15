package openfl._internal.symbols;

import haxe.Serializer;
import haxe.Unserializer;
import openfl._internal.formats.swf.ShapeCommand;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class FontSymbol extends SWFSymbol
{
	public var advances:Array<Int>;
	public var ascent:Int;
	public var bold:Bool;
	public var codes:Array<Int>;
	public var descent:Int;
	public var glyphs:Array<Array<ShapeCommand>>;
	public var italic:Bool;
	public var leading:Int;
	public var name:String;

	public function new()
	{
		super();
	}

	@:keep
	override function hxSerialize(s:Serializer) {
		s.serialize(advances);
		s.serialize(ascent);
		s.serialize(bold);
		s.serialize(codes);
		s.serialize(descent);
		s.serialize(glyphs);
		s.serialize(italic);
		s.serialize(leading);
		s.serialize(name);
		super.hxSerialize(s);
	}

	@:keep
	override function hxUnserialize(u:Unserializer) {

		advances = u.unserialize();
		ascent = u.unserialize();
		bold = u.unserialize();
		codes  = u.unserialize();
		descent = u.unserialize();
		glyphs = u.unserialize();
		italic = u.unserialize();
		leading = u.unserialize();
		name = u.unserialize();
		super.hxUnserialize(u);
	}

}
