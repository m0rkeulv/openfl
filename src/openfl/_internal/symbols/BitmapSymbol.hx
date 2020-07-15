package openfl._internal.symbols;

import haxe.Unserializer;
import haxe.Serializer;
import openfl._internal.formats.swf.SWFLite;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.PixelSnapping;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class BitmapSymbol extends SWFSymbol
{
	public var alpha:String;
	public var path:String;
	public var smooth:Null<Bool>;

	public function new()
	{
		super();
	}

	private override function __createObject(swf:SWFLite):Bitmap
	{
		#if lime
		return new Bitmap(BitmapData.fromImage(swf.library.getImage(path)), PixelSnapping.AUTO, smooth != false);
		#else
		return null;
		#end
	}

	@:keep
	override function hxSerialize(s:Serializer) {
		s.serialize(alpha);
		s.serialize(path);
		s.serialize(smooth);
		super.hxSerialize(s);
	}

	@:keep
	override function hxUnserialize(u:Unserializer) {

		alpha = u.unserialize();
		path = u.unserialize();
		smooth = u.unserialize();
		super.hxUnserialize(u);
	}

}
