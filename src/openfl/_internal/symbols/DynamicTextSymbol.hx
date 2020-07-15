package openfl._internal.symbols;

import haxe.Serializer;
import haxe.Unserializer;
import openfl._internal.formats.swf.SWFLite;
import openfl.text.TextField;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.text.TextField)
class DynamicTextSymbol extends SWFSymbol
{
	public var align: /*TextFormatAlign*/ String;
	public var border:Bool;
	public var color:Null<Int>;
	public var fontHeight:Int;
	public var fontID:Int;
	public var fontName:String;
	public var height:Float;
	public var html:Bool;
	public var indent:Null<Int>;
	public var input:Bool;
	public var leading:Null<Int>;
	public var leftMargin:Null<Int>;
	public var multiline:Bool;
	public var password:Bool;
	public var rightMargin:Null<Int>;
	public var selectable:Bool;
	public var text:String;
	public var width:Float;
	public var wordWrap:Bool;
	public var x:Float;
	public var y:Float;

	public function new()
	{
		super();
	}

	private override function __createObject(swf:SWFLite):TextField
	{
		var textField = new TextField();
		textField.__fromSymbol(swf, this);
		return textField;
	}


	@:keep
	override function hxSerialize(s:Serializer) {
		s.serialize(align);
		s.serialize(border);
		s.serialize(color);
		s.serialize(fontHeight);
		s.serialize(fontID);
		s.serialize(fontName);
		s.serialize(height);
		s.serialize(html);
		s.serialize(indent);
		s.serialize(input);
		s.serialize(leading);
		s.serialize(leftMargin);
		s.serialize(multiline);
		s.serialize(password);
		s.serialize(rightMargin);
		s.serialize(selectable);
		s.serialize(text);
		s.serialize(width);
		s.serialize(wordWrap);
		s.serialize(x);
		s.serialize(y);

		super.hxSerialize(s);
	}

	@:keep
	override function hxUnserialize(u:Unserializer) {

		align = u.unserialize();
		border = u.unserialize();
		color = u.unserialize();
		fontHeight = u.unserialize();
		fontID = u.unserialize();
		fontName = u.unserialize();
		height = u.unserialize();
		html = u.unserialize();
		indent = u.unserialize();
		input = u.unserialize();
		leading = u.unserialize();
		leftMargin = u.unserialize();
		multiline = u.unserialize();
		password = u.unserialize();
		rightMargin = u.unserialize();
		selectable = u.unserialize();
		text = u.unserialize();
		width = u.unserialize();
		wordWrap = u.unserialize();
		x = u.unserialize();
		y = u.unserialize();
		super.hxUnserialize(u);
	}

}
