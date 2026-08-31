package openfl.filters;

#if !flash
import openfl.display.BitmapData;
import openfl.display.DisplayObjectRenderer;
import openfl.display.Shader;
import openfl.geom.Point;
import openfl.geom.Rectangle;

/**
	The GradientGlowFilter class lets you apply a gradient glow effect to
	display objects. It is a glow whose colour is taken from a gradient (defined
	by `colors`/`alphas`/`ratios`) instead of a single colour: `ratios` position
	the colours along the glow — 0 is the outermost point, 255 the innermost.

	Not present in stock OpenFL; implemented here for the non-flash targets by
	blurring the object's alpha into a distance field and indexing a 256-entry
	ramp built from the stops.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.filters.BlurFilter)
@:access(openfl.geom.Point)
@:access(openfl.geom.Rectangle)
@:final class GradientGlowFilter extends BitmapFilter
{
	@:noCompletion private static var __gradientShader = new GradientGlowShader();

	public var distance(get, set):Float;
	public var angle(get, set):Float;
	public var colors(get, set):Array<Int>;
	public var alphas(get, set):Array<Float>;
	public var ratios(get, set):Array<Int>;
	public var blurX(get, set):Float;
	public var blurY(get, set):Float;
	public var strength(get, set):Float;
	public var quality(get, set):Int;
	public var type(get, set):BitmapFilterType;
	public var knockout(get, set):Bool;

	@:noCompletion private var __distance:Float;
	@:noCompletion private var __angle:Float;
	@:noCompletion private var __colors:Array<Int>;
	@:noCompletion private var __alphas:Array<Float>;
	@:noCompletion private var __ratios:Array<Int>;
	@:noCompletion private var __blurX:Float;
	@:noCompletion private var __blurY:Float;
	@:noCompletion private var __strength:Float;
	@:noCompletion private var __quality:Int;
	@:noCompletion private var __type:BitmapFilterType;
	@:noCompletion private var __knockout:Bool;
	@:noCompletion private var __offsetX:Int;
	@:noCompletion private var __offsetY:Int;
	@:noCompletion private var __horizontalPasses:Int;
	@:noCompletion private var __verticalPasses:Int;
	@:noCompletion private var __ramp:BitmapData;
	@:noCompletion private var __rampDirty:Bool;

	public function new(distance:Float = 4, angle:Float = 45, colors:Array<Int> = null, alphas:Array<Float> = null, ratios:Array<Int> = null,
			blurX:Float = 4, blurY:Float = 4, strength:Float = 1, quality:Int = 1, type:BitmapFilterType = OUTER, knockout:Bool = false)
	{
		super();

		__distance = distance;
		__angle = angle;
		__colors = (colors != null) ? colors : [0xFFFFFF, 0xFFFFFF];
		__alphas = (alphas != null) ? alphas : [0, 1];
		__ratios = (ratios != null) ? ratios : [0, 255];
		__blurX = blurX;
		__blurY = blurY;
		__strength = strength;
		__quality = quality;
		__type = type;
		__knockout = knockout;
		__rampDirty = true;

		__needSecondBitmapData = true;
		__preserveObject = true;
		__renderDirty = true;

		__updateSize();
	}

	public override function clone():BitmapFilter
	{
		return new GradientGlowFilter(__distance, __angle, __colors.copy(), __alphas.copy(), __ratios.copy(), __blurX, __blurY, __strength, __quality,
			__type, __knockout);
	}

	@:noCompletion private override function __applyFilter(bitmapData:BitmapData, sourceBitmapData:BitmapData, sourceRect:Rectangle, destPoint:Point):BitmapData
	{
		// software path not implemented yet (GL shader path below is the one used
		// on-screen); return the source unchanged so nothing crashes.
		return sourceBitmapData;
	}

	@:noCompletion private override function __initShader(renderer:DisplayObjectRenderer, pass:Int, sourceBitmapData:BitmapData):Shader
	{
		#if !macro
		var numBlurPasses = __horizontalPasses + __verticalPasses;
		if (pass < numBlurPasses)
		{
			// blur the object's alpha into a soft distance field (reuse BlurFilter)
			var horizontal = pass < __horizontalPasses;
			#if flash_box_blur
			return BlurFilter.__setupBoxBlur(horizontal, horizontal ? __blurX : __blurY);
			#else
			var shader = BlurFilter.__blurShader;
			if (horizontal)
			{
				var scale = Math.pow(0.5, pass >> 1);
				shader.uRadius.value[0] = __blurX * scale;
				shader.uRadius.value[1] = 0;
			}
			else
			{
				var scale = Math.pow(0.5, (pass - __horizontalPasses) >> 1);
				shader.uRadius.value[0] = 0;
				shader.uRadius.value[1] = __blurY * scale;
			}
			return shader;
			#end
		}

		if (__rampDirty) __buildRamp();

		var shader = __gradientShader;
		shader.sourceBitmap.input = sourceBitmapData;
		shader.gradientRamp.input = __ramp;
		shader.offset.value[0] = __offsetX;
		shader.offset.value[1] = __offsetY;
		shader.uStrength.value[0] = __strength;
		shader.uInner.value[0] = (__type == INNER) ? 1.0 : 0.0;
		shader.uFull.value[0] = (__type == FULL) ? 1.0 : 0.0;
		shader.uKnockout.value[0] = __knockout ? 1.0 : 0.0;
		return shader;
		#else
		return null;
		#end
	}

	// Build the 256x1 straight-ARGB ramp from (colors, alphas, ratios).
	@:noCompletion private function __buildRamp():Void
	{
		if (__ramp == null) __ramp = new BitmapData(256, 1, true, 0);
		var n = __colors.length;
		var si = 0;
		for (i in 0...256)
		{
			while (si < n - 1 && __ratios[si + 1] < i)
				si++;
			var r0 = __ratios[si];
			var c0 = __colors[si];
			var a0 = __alphas[si];
			var rr:Float, gg:Float, bb:Float, aa:Float;
			if (si >= n - 1 || i <= r0)
			{
				rr = (c0 >> 16) & 0xFF;
				gg = (c0 >> 8) & 0xFF;
				bb = c0 & 0xFF;
				aa = a0 * 255;
			}
			else
			{
				var r1 = __ratios[si + 1];
				var c1 = __colors[si + 1];
				var a1 = __alphas[si + 1];
				var f = (r1 > r0) ? (i - r0) / (r1 - r0) : 0.0;
				rr = ((c0 >> 16) & 0xFF) + (((c1 >> 16) & 0xFF) - ((c0 >> 16) & 0xFF)) * f;
				gg = ((c0 >> 8) & 0xFF) + (((c1 >> 8) & 0xFF) - ((c0 >> 8) & 0xFF)) * f;
				bb = (c0 & 0xFF) + ((c1 & 0xFF) - (c0 & 0xFF)) * f;
				aa = (a0 + (a1 - a0) * f) * 255;
			}
			var col = (Std.int(aa) << 24) | (Std.int(rr) << 16) | (Std.int(gg) << 8) | Std.int(bb);
			__ramp.setPixel32(i, 0, col);
		}
		__rampDirty = false;
	}

	@:noCompletion private function __updateSize():Void
	{
		__offsetX = Std.int(__distance * Math.cos(__angle * Math.PI / 180));
		__offsetY = Std.int(__distance * Math.sin(__angle * Math.PI / 180));
		#if flash_box_blur
		// Box blur reach grows to ~quality*blur/2 per side (see DropShadowFilter);
		// reserve the full spread so the gradient glow isn't clipped at high quality.
		var qext = (__quality > 0) ? __quality : 1;
		var exX = Math.ceil(__blurX * 0.5 * qext) + 4;
		var exY = Math.ceil(__blurY * 0.5 * qext) + 4;
		#else
		var exX = Math.ceil(__blurX * 1.5);
		var exY = Math.ceil(__blurY * 1.5);
		#end
		__topExtension = (__offsetY < 0 ? -__offsetY : 0) + exY;
		__bottomExtension = (__offsetY > 0 ? __offsetY : 0) + exY;
		__leftExtension = (__offsetX < 0 ? -__offsetX : 0) + exX;
		__rightExtension = (__offsetX > 0 ? __offsetX : 0) + exX;

		#if flash_box_blur
		var q = (__quality > 0) ? __quality : 1;
		__horizontalPasses = (__blurX <= 0) ? 0 : q;
		__verticalPasses = (__blurY <= 0) ? 0 : q;
		#else
		__horizontalPasses = (__blurX <= 0) ? 0 : Math.round(__blurX * (__quality / 4)) + 1;
		__verticalPasses = (__blurY <= 0) ? 0 : Math.round(__blurY * (__quality / 4)) + 1;
		#end
		__numShaderPasses = __horizontalPasses + __verticalPasses + 1;
	}

	// Getters / setters
	@:noCompletion private function get_distance():Float return __distance;

	@:noCompletion private function set_distance(v:Float):Float
	{
		if (v != __distance) { __distance = v; __updateSize(); __renderDirty = true; }
		return v;
	}

	@:noCompletion private function get_angle():Float return __angle;

	@:noCompletion private function set_angle(v:Float):Float
	{
		if (v != __angle) { __angle = v; __updateSize(); __renderDirty = true; }
		return v;
	}

	@:noCompletion private function get_colors():Array<Int> return __colors;

	@:noCompletion private function set_colors(v:Array<Int>):Array<Int>
	{
		__colors = v; __rampDirty = true; __renderDirty = true;
		return v;
	}

	@:noCompletion private function get_alphas():Array<Float> return __alphas;

	@:noCompletion private function set_alphas(v:Array<Float>):Array<Float>
	{
		__alphas = v; __rampDirty = true; __renderDirty = true;
		return v;
	}

	@:noCompletion private function get_ratios():Array<Int> return __ratios;

	@:noCompletion private function set_ratios(v:Array<Int>):Array<Int>
	{
		__ratios = v; __rampDirty = true; __renderDirty = true;
		return v;
	}

	@:noCompletion private function get_blurX():Float return __blurX;

	@:noCompletion private function set_blurX(v:Float):Float
	{
		if (v != __blurX) { __blurX = v; __updateSize(); __renderDirty = true; }
		return v;
	}

	@:noCompletion private function get_blurY():Float return __blurY;

	@:noCompletion private function set_blurY(v:Float):Float
	{
		if (v != __blurY) { __blurY = v; __updateSize(); __renderDirty = true; }
		return v;
	}

	@:noCompletion private function get_strength():Float return __strength;

	@:noCompletion private function set_strength(v:Float):Float
	{
		if (v != __strength) { __strength = v; __renderDirty = true; }
		return v;
	}

	@:noCompletion private function get_quality():Int return __quality;

	@:noCompletion private function set_quality(v:Int):Int
	{
		if (v != __quality) { __quality = v; __updateSize(); __renderDirty = true; }
		return v;
	}

	@:noCompletion private function get_type():BitmapFilterType return __type;

	@:noCompletion private function set_type(v:BitmapFilterType):BitmapFilterType
	{
		if (v != __type) { __type = v; __renderDirty = true; }
		return v;
	}

	@:noCompletion private function get_knockout():Bool return __knockout;

	@:noCompletion private function set_knockout(v:Bool):Bool
	{
		if (v != __knockout) { __knockout = v; __renderDirty = true; }
		return v;
	}
}

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
private class GradientGlowShader extends BitmapFilterShader
{
	@:glFragmentSource("
		uniform sampler2D openfl_Texture;
		uniform sampler2D sourceBitmap;
		uniform sampler2D gradientRamp;
		uniform float uStrength;
		uniform float uInner;
		uniform float uFull;
		uniform float uKnockout;
		varying vec4 textureCoords;

		void main(void) {
			vec4 src = texture2D(sourceBitmap, textureCoords.xy);
			float field = texture2D(openfl_Texture, textureCoords.zw).a;
			float f = clamp(field * uStrength, 0.0, 1.0);

			// index the ramp by the distance field (high near the shape = inner
			// ratio 255, low far away = outer ratio 0), same for every type.
			vec4 g = texture2D(gradientRamp, vec2(f, 0.5));

			if (uInner > 0.5) {
				vec4 inner = g * src.a;
				if (uKnockout > 0.5) gl_FragColor = inner;
				else gl_FragColor = src * (1.0 - inner.a) + inner;
			} else if (uFull > 0.5) {
				if (uKnockout > 0.5) gl_FragColor = g;
				else gl_FragColor = src * (1.0 - g.a) + g;
			} else {
				vec4 outer = g * (1.0 - src.a);
				if (uKnockout > 0.5) gl_FragColor = outer;
				else gl_FragColor = src + outer;
			}
		}
	")
	@:glVertexSource("attribute vec4 openfl_Position;
		attribute vec2 openfl_TextureCoord;
		uniform mat4 openfl_Matrix;
		uniform vec2 openfl_TextureSize;
		uniform vec2 offset;
		varying vec4 textureCoords;

		void main(void) {
			gl_Position = openfl_Matrix * openfl_Position;
			textureCoords = vec4(openfl_TextureCoord, openfl_TextureCoord - offset / openfl_TextureSize);
		}
	")
	public function new()
	{
		super();
		#if !macro
		offset.value = [0, 0];
		uStrength.value = [1];
		uInner.value = [0];
		uFull.value = [0];
		uKnockout.value = [0];
		#end
	}
}
#else
typedef GradientGlowFilter = flash.filters.GradientGlowFilter;
#end
