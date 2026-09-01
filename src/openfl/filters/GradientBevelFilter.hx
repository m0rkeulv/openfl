package openfl.filters;

#if !flash
import openfl.display.BitmapData;
import openfl.display.DisplayObjectRenderer;
import openfl.display.Shader;
import openfl.geom.Point;
import openfl.geom.Rectangle;

/**
	The GradientBevelFilter class lets you apply a gradient bevel effect to
	display objects. The bevel's colours come from a gradient (defined by
	`colors`/`alphas`/`ratios`) instead of separate highlight/shadow colours:
	ratio 0 is one edge, 255 the other, and 128 is the base (usually
	transparent), which appears where there is no bevel.

	Not present in stock OpenFL; implemented here for the non-flash targets by
	sampling the blurred alpha at +/- the bevel offset to build a signed
	distance field and indexing a 256-entry ramp built from the stops.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.filters.BlurFilter)
@:access(openfl.geom.Point)
@:access(openfl.geom.Rectangle)
@:final class GradientBevelFilter extends BitmapFilter
{
	@:noCompletion private static var __gradientShader = new GradientBevelShader();

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
	@:noCompletion private var __horizontalPasses:Int;
	@:noCompletion private var __verticalPasses:Int;
	@:noCompletion private var __ramp:BitmapData;
	@:noCompletion private var __rampDirty:Bool;

	public function new(distance:Float = 4, angle:Float = 45, colors:Array<Int> = null, alphas:Array<Float> = null, ratios:Array<Int> = null,
			blurX:Float = 4, blurY:Float = 4, strength:Float = 1, quality:Int = 1, type:BitmapFilterType = INNER, knockout:Bool = false)
	{
		super();

		__distance = distance;
		__angle = angle;
		__colors = (colors != null) ? colors : [0xFFFFFF, 0x808080, 0x000000];
		__alphas = (alphas != null) ? alphas : [1, 0, 1];
		__ratios = (ratios != null) ? ratios : [0, 128, 255];
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
		return new GradientBevelFilter(__distance, __angle, __colors.copy(), __alphas.copy(), __ratios.copy(), __blurX, __blurY, __strength, __quality,
			__type, __knockout);
	}

	@:noCompletion private override function __applyFilter(bitmapData:BitmapData, sourceBitmapData:BitmapData, sourceRect:Rectangle, destPoint:Point):BitmapData
	{
		// software path not implemented yet (GL shader path below is used on-screen)
		return sourceBitmapData;
	}

	@:noCompletion private override function __initShader(renderer:DisplayObjectRenderer, pass:Int, sourceBitmapData:BitmapData):Shader
	{
		#if !macro
		var numBlurPasses = __horizontalPasses + __verticalPasses;
		if (pass < numBlurPasses)
		{
			var horizontal = pass < __horizontalPasses;
			return BlurFilter.__setupBoxBlur(horizontal, horizontal ? __blurX : __blurY);
		}

		if (__rampDirty) __buildRamp();

		var rad = __angle * Math.PI / 180;
		var shader = __gradientShader;
		shader.sourceBitmap.input = sourceBitmapData;
		shader.gradientRamp.input = __ramp;
		shader.uTransformX.value[0] = __distance * Math.cos(rad);
		shader.uTransformY.value[0] = __distance * Math.sin(rad);
		shader.uStrength.value[0] = __strength;
		shader.uBevelType.value[0] = (__type == INNER) ? 0.0 : (__type == OUTER ? 1.0 : 2.0);
		shader.uKnockout.value[0] = __knockout;
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
		// The bevel field (bL-bR) is exactly zero beyond the box-blur support
		// (quality*blur/2) offset by the transform (distance). Because the ramp's
		// middle stop is usually opaque, flat regions map to the middle colour and
		// the *visible* band edge sits at the texture boundary — so the extension
		// must equal the true bevel extent (support + directional offset), with no
		// safety margin, or the middle colour over-fills past where Flash stops.
		// This mirrors BevelFilter's asymmetric extension (which matches Flash),
		// minus the margin that filter can afford only because its band fades out.
		var rad = __angle * Math.PI / 180;
		// magnitude of the transform offset per axis (band reaches support + |offset|
		// on every side); ceil the absolute value so negative angles don't lose a pixel
		var offsetX:Int = (__type != INNER) ? Math.ceil(Math.abs(__distance * Math.cos(rad))) : 0;
		var offsetY:Int = (__type != INNER) ? Math.ceil(Math.abs(__distance * Math.sin(rad))) : 0;
		var q = (__quality > 0) ? __quality : 1;
		var exX = Math.ceil(__blurX * 0.5 * q);
		var exY = Math.ceil(__blurY * 0.5 * q);
		__leftExtension = __rightExtension = exX + offsetX;
		__topExtension = __bottomExtension = exY + offsetY;

		__horizontalPasses = (__blurX <= 0) ? 0 : q;
		__verticalPasses = (__blurY <= 0) ? 0 : q;
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
		if (v != __angle) { __angle = v; __renderDirty = true; }
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
private class GradientBevelShader extends BitmapFilterShader
{
	@:glFragmentSource("uniform sampler2D openfl_Texture;
		uniform sampler2D sourceBitmap;
		uniform sampler2D gradientRamp;
		uniform float uBevelType;
		uniform bool uKnockout;
		uniform float uStrength;
		varying vec2 vTextureCoord;
		varying vec2 vTransform;

		void main(void) {
			vec4 dest = texture2D(sourceBitmap, vTextureCoord);
			vec2 uvL = vTextureCoord + vTransform;
			vec2 uvR = vTextureCoord - vTransform;
			float bL = texture2D(openfl_Texture, uvL).a;
			float bR = texture2D(openfl_Texture, uvR).a;
			if (uvL.x<0.0||uvL.x>1.0||uvL.y<0.0||uvL.y>1.0) bL = 0.0;
			if (uvR.x<0.0||uvR.x>1.0||uvR.y<0.0||uvR.y>1.0) bR = 0.0;

			// signed distance field -> ramp index (-1 = one edge/ratio 0,
			// 0 = base/ratio 128, +1 = other edge/ratio 255)
			float sd = clamp((bL - bR) * uStrength, -1.0, 1.0);
			vec4 glow = texture2D(gradientRamp, vec2(sd * 0.5 + 0.5, 0.5));

			if (uBevelType == 0.0) {
				if (uKnockout) gl_FragColor = glow * dest.a;
				else gl_FragColor = glow * dest.a + dest * (1.0 - glow.a);
			} else if (uBevelType == 1.0) {
				if (uKnockout) gl_FragColor = glow - glow * dest.a;
				else gl_FragColor = dest + glow - glow * dest.a;
			} else {
				if (uKnockout) gl_FragColor = glow;
				else gl_FragColor = dest - dest * glow.a + glow;
			}
		}")
	@:glVertexSource("attribute vec4 openfl_Position;
		attribute vec2 openfl_TextureCoord;
		uniform mat4 openfl_Matrix;
		uniform vec2 uTextureSize;
		uniform float uTransformX;
		uniform float uTransformY;
		varying vec2 vTextureCoord;
		varying vec2 vTransform;

		void main(void) {
			gl_Position = openfl_Matrix * openfl_Position;
			vTextureCoord = openfl_TextureCoord;
			vTransform = vec2(uTransformX / uTextureSize.x, uTransformY / uTextureSize.y);
		}")
	public function new()
	{
		super();
		#if !macro
		uTransformX.value = [0];
		uTransformY.value = [0];
		uBevelType.value = [0.0];
		uKnockout.value = [false];
		uStrength.value = [1];
		#end
	}

	@:noCompletion private override function __update():Void
	{
		#if !macro
		uTextureSize.value = [__texture.input.width, __texture.input.height];
		#end
		super.__update();
	}
}
#else
typedef GradientBevelFilter = flash.filters.GradientBevelFilter;
#end
