package openfl._internal.symbols.timeline;

#if !openfl_debug
import haxe.Unserializer;
import haxe.Serializer;
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:keep class Frame
{
	public var label:String;
	public var objects:Array<FrameObject>;
	public var script:Void->Void;
	public var scriptSource:String;

	// public var scriptType:FrameScriptType;
	public function new() {}

	@:keep
	function hxSerialize(s:Serializer) {
		s.serialize(label);
		s.serialize(objects);
		s.serialize(script);
		s.serialize(scriptSource);

	}

	@:keep
	function hxUnserialize(u:Unserializer) {

		label = u.unserialize();
		objects = u.unserialize();
		script = u.unserialize();
		scriptSource = u.unserialize();


	}

}
