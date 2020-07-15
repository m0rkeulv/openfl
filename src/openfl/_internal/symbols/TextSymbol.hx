package openfl._internal.symbols;

#if !openfl_debug
import haxe.Serializer;
import haxe.Unserializer;
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class TextSymbol extends SWFSymbol
{
	public var border:Bool;
	public var color:Null<Int>;
	public var fontHeight:Float;
	public var fontID:Int;
	public var height:Float;
	public var multiline:Bool;
	public var password:Bool;
	public var selectable:Bool;
	public var text:String;
	public var width:Float;
	public var wordWrap:Bool;

	public function new()
	{
		super();
	}

	@:keep
	override function hxSerialize(s:Serializer) {
		s.serialize(border);
		s.serialize(color);
		s.serialize(fontHeight);
		s.serialize(fontID);
		s.serialize(height);
		s.serialize(multiline);
		s.serialize(password);
		s.serialize(selectable);
		s.serialize(text);
		s.serialize(width);
		s.serialize(wordWrap);
		super.hxSerialize(s);
	}

	@:keep
	override function hxUnserialize(u:Unserializer) {

		border = u.unserialize();
		color = u.unserialize();
		fontHeight = u.unserialize();
		fontID = u.unserialize();
		height = u.unserialize();
		multiline = u.unserialize();
		password = u.unserialize();
		selectable = u.unserialize();
		text = u.unserialize();
		width = u.unserialize();
		wordWrap = u.unserialize();
		super.hxUnserialize(u);
	}

}
