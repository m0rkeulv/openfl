package openfl._internal.symbols;

import haxe.Serializer;
import haxe.Unserializer;
import openfl._internal.formats.swf.SWFLite;
import openfl.display.CapsStyle;
import openfl.display.JointStyle;
import openfl.display.LineScaleMode;
import openfl.geom.Matrix;
import openfl.text.StaticText;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.display.CapsStyle)
@:access(openfl.display.JointStyle)
@:access(openfl.display.LineScaleMode)
@:access(openfl.text.StaticText)
class StaticTextSymbol extends SWFSymbol
{
	public var matrix:Matrix;
	public var records:Array<StaticTextRecord>;
	public var rendered:StaticText;

	public function new()
	{
		super();
	}

	private override function __createObject(swf:SWFLite):StaticText
	{
		var staticText = new StaticText();
		var graphics = staticText.__graphics;

		if (rendered != null)
		{
			staticText.text = rendered.text;
			graphics.copyFrom(rendered.__graphics);
			return staticText;
		}

		var text = "";

		if (records != null)
		{
			var font:FontSymbol = null;
			var color = 0xFFFFFF;
			var offsetX = matrix.tx;
			var offsetY = matrix.ty;

			var scale, index;

			for (record in records)
			{
				if (record.fontID != null) font = cast swf.symbols.get(record.fontID);
				if (record.offsetX != null) offsetX = matrix.tx + record.offsetX * 0.05;
				if (record.offsetY != null) offsetY = matrix.ty + record.offsetY * 0.05;
				if (record.color != null) color = record.color;

				if (font != null)
				{
					scale = (record.fontHeight / 1024) * 0.05;

					for (i in 0...record.glyphs.length)
					{
						index = record.glyphs[i];
						text += String.fromCharCode(font.codes[index]);

						for (command in font.glyphs[index])
						{
							switch (command)
							{
								case BeginFill(_, alpha):
									graphics.beginFill(color & 0xFFFFFF, ((color >> 24) & 0xFF) / 0xFF);

								case CurveTo(controlX, controlY, anchorX, anchorY):
									graphics.curveTo(controlX * scale + offsetX, controlY * scale + offsetY, anchorX * scale + offsetX,
										anchorY * scale + offsetY);

								case EndFill:
									graphics.endFill();

								case LineStyle(thickness, color, alpha, pixelHinting, scaleMode, caps, joints, miterLimit):
									if (thickness != null)
									{
										graphics.lineStyle(thickness, color, alpha, pixelHinting, LineScaleMode.fromInt(scaleMode), CapsStyle.fromInt(caps),
											JointStyle.fromInt(joints), miterLimit);
									}
									else
									{
										graphics.lineStyle();
									}

								case LineTo(x, y):
									graphics.lineTo(x * scale + offsetX, y * scale + offsetY);

								case MoveTo(x, y):
									graphics.moveTo(x * scale + offsetX, y * scale + offsetY);

								default:
							}
						}

						offsetX += record.advances[i] * 0.05;
					}
				}
			}
		}

		staticText.text = text;

		records = null;
		rendered = new StaticText();
		rendered.text = text;
		rendered.__graphics.copyFrom(staticText.__graphics);

		return staticText;
	}

	@:keep
	override function hxSerialize(s:Serializer) {
		s.serialize(matrix);
		s.serialize(records);
		s.serialize(rendered);
		super.hxSerialize(s);

	}

	@:keep
	override function hxUnserialize(u:Unserializer) {

		matrix = u.unserialize();
		records = u.unserialize();
		rendered = u.unserialize();
		super.hxUnserialize(u);

	}

}

@:keep class StaticTextRecord
{
	public var advances:Array<Int>;
	public var color:Null<Int>;
	public var fontHeight:Int;
	public var fontID:Null<Int>;
	public var glyphs:Array<Int>;
	public var offsetX:Null<Int>;
	public var offsetY:Null<Int>;

	public function new() {}

	@:keep
	function hxSerialize(s:Serializer) {
		s.serialize(advances);
		s.serialize(color);
		s.serialize(fontHeight);
		s.serialize(fontID);
		s.serialize(glyphs);
		s.serialize(offsetX);
		s.serialize(offsetY);
	}

	@:keep
	function hxUnserialize(u:Unserializer) {

		advances =  u.unserialize();
		color =  u.unserialize();
		fontHeight =  u.unserialize();
		fontID =  u.unserialize();
		glyphs =  u.unserialize();
		offsetX =  u.unserialize();
		offsetY =  u.unserialize();

	}

}
