package openfl.filters;

#if !flash
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.display.DisplayObjectRenderer;
import openfl.display.Shader;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.Vector;

/**
	The BitmapFilter class is the base class for all image filter effects.

	The BevelFilter, BlurFilter, ColorMatrixFilter, ConvolutionFilter,
	DisplacementMapFilter, DropShadowFilter, GlowFilter, GradientBevelFilter,
	and GradientGlowFilter classes all extend the BitmapFilter class. You can
	apply these filter effects to any display object.

	You can neither directly instantiate nor extend BitmapFilter.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class BitmapFilter
{
	@:noCompletion private var __bottomExtension:Int;
	@:noCompletion private var __leftExtension:Int;
	@:noCompletion private var __needSecondBitmapData:Bool;
	@:noCompletion private var __numShaderPasses:Int;
	@:noCompletion private var __preserveObject:Bool;
	@:noCompletion private var __renderDirty:Bool;
	@:noCompletion private var __rightExtension:Int;
	@:noCompletion private var __shaderBlendMode:BlendMode;
	@:noCompletion private var __smooth:Bool;
	@:noCompletion private var __topExtension:Int;

	/**
		Whether `__applyFilter` composites the original object into its own result.

		The GPU path hands the unfiltered object to the combine shader (see
		`__initShader`), which composites inner / knockout / full itself. The
		software path instead relies on the caller drawing the object back on top
		afterwards, which can only ever produce an "outer, non-knockout" result.
		Filters whose `__applyFilter` does the whole composite set this so the
		software callers skip that draw. The GPU path never reads it.
	**/
	@:noCompletion private var __softwareComposite:Bool;

	public function new()
	{
		__bottomExtension = 0;
		__leftExtension = 0;
		__needSecondBitmapData = true;
		__numShaderPasses = 0;
		__preserveObject = false;
		__rightExtension = 0;
		__shaderBlendMode = NORMAL;
		__topExtension = 0;
		__smooth = true;
		__softwareComposite = false;
	}

	/**
		Returns a BitmapFilter object that is an exact copy of the original
		BitmapFilter object.

		@return A BitmapFilter object.
	**/
	public function clone():BitmapFilter
	{
		return new BitmapFilter();
	}

	@:noCompletion private function __applyFilter(bitmapData:BitmapData, sourceBitmapData:BitmapData, sourceRect:Rectangle, destPoint:Point):BitmapData
	{
		return sourceBitmapData;
	}

	@:noCompletion private function __initShader(renderer:DisplayObjectRenderer, pass:Int, sourceBitmapData:BitmapData):Shader
	{
		// return renderer.__defaultShader;
		return null;
	}

	// ------------------------------------------------------------------------
	// Software (CPU) helpers, shared by the effect filters. These mirror the GL
	// shaders so both paths produce the same image: the same fractional box blur
	// of the source alpha, and the same combine formulas.
	// ------------------------------------------------------------------------

	/**
		The source's alpha channel as a 0..1 field laid out on the destination
		grid, using the sourceRect/destPoint mapping `__applyFilter` is given.
		Samples outside the source read 0, matching the transparent border the GL
		path gets from its cache texture.
	**/
	@:noCompletion private static function __alphaField(source:BitmapData, sourceRect:Rectangle, destPoint:Point, width:Int, height:Int):Array<Float>
	{
		var field = new Array<Float>();
		for (i in 0...width * height)
			field.push(0.0);

		var pixels = source.getVector(sourceRect);
		var sw = Std.int(sourceRect.width);
		var sh = Std.int(sourceRect.height);
		var ox = Std.int(destPoint.x);
		var oy = Std.int(destPoint.y);

		for (y in 0...sh)
		{
			var dy = y + oy;
			if (dy < 0 || dy >= height) continue;
			for (x in 0...sw)
			{
				var dx = x + ox;
				if (dx < 0 || dx >= width) continue;
				field[dy * width + dx] = ((pixels[y * sw + x] >>> 24) & 0xFF) / 255.0;
			}
		}
		return field;
	}

	/**
		Box-blur a 0..1 field in place, matching `BoxBlurShader`: `quality`
		iterations of one horizontal then one vertical pass.
	**/
	@:noCompletion private static function __blurField(field:Array<Float>, width:Int, height:Int, blurX:Float, blurY:Float, quality:Int):Array<Float>
	{
		var passes = (quality > 0) ? quality : 1;
		var scratch = new Array<Float>();
		for (i in 0...field.length)
			scratch.push(0.0);

		for (i in 0...passes)
		{
			__blurFieldAxis(field, scratch, width, height, blurX, true);
			__blurFieldAxis(scratch, field, width, height, blurY, false);
		}
		return field;
	}

	// One axis of the fractional box: the centre sample, `n` full-weight pairs,
	// and a fractional-weight texel per edge, divided by the box width and
	// rounded to 8 bits -- the same kernel BoxBlurShader uses.
	@:noCompletion private static function __blurFieldAxis(src:Array<Float>, dest:Array<Float>, width:Int, height:Int, blur:Float, horizontal:Bool):Void
	{
		var fullSize = (blur > 255) ? 255.0 : blur;

		if (fullSize <= 1)
		{
			for (i in 0...src.length)
				dest[i] = src[i];
			return;
		}

		var half = fullSize * 0.5;
		var n = Std.int(Math.floor(half - 0.5));
		if (n < 0) n = 0;
		var frac = Math.floor((half - (n + 0.5)) * 255) / 255;
		var edge = n + 1;

		for (y in 0...height)
		{
			for (x in 0...width)
			{
				var sum = __fieldAt(src, width, height, x, y);

				for (i in 1...(n + 1))
				{
					if (horizontal) sum += __fieldAt(src, width, height, x + i, y) + __fieldAt(src, width, height, x - i, y);
					else sum += __fieldAt(src, width, height, x, y + i) + __fieldAt(src, width, height, x, y - i);
				}

				if (horizontal) sum += (__fieldAt(src, width, height, x + edge, y) + __fieldAt(src, width, height, x - edge, y)) * frac;
				else sum += (__fieldAt(src, width, height, x, y + edge) + __fieldAt(src, width, height, x, y - edge)) * frac;

				dest[y * width + x] = Math.floor((sum / fullSize) * 255) / 255;
			}
		}
	}

	@:noCompletion private static inline function __fieldAt(field:Array<Float>, width:Int, height:Int, x:Int, y:Int):Float
	{
		return (x < 0 || x >= width || y < 0 || y >= height) ? 0.0 : field[y * width + x];
	}

	/**
		Combine an effect layer with the source and write the result into `dest`,
		matching the GL combine shaders. The effect is supplied as premultiplied
		0..1 channels; `type` is INNER / OUTER / FULL.

		outer:    src + fx * (1 - src.a)
		inner:    rgb = src.rgb * (1 - fx.a) + fx.rgb * src.a,  a = src.a
		full:     src * (1 - fx.a) + fx
		knockout: the src term is dropped (outer keeps `fx * (1 - src.a)`,
		          inner keeps `fx * src.a`, full keeps `fx`)
	**/
	@:noCompletion private static function __compositeEffect(dest:BitmapData, source:BitmapData, sourceRect:Rectangle, destPoint:Point, fxR:Array<Float>,
			fxG:Array<Float>, fxB:Array<Float>, fxA:Array<Float>, type:BitmapFilterType, knockout:Bool):BitmapData
	{
		var width = dest.width;
		var height = dest.height;

		// source pixels on the destination grid, premultiplied
		var srcR = new Array<Float>(), srcG = new Array<Float>(), srcB = new Array<Float>(), srcA = new Array<Float>();
		for (i in 0...width * height)
		{
			srcR.push(0.0);
			srcG.push(0.0);
			srcB.push(0.0);
			srcA.push(0.0);
		}

		var pixels = source.getVector(sourceRect);
		var sw = Std.int(sourceRect.width);
		var sh = Std.int(sourceRect.height);
		var ox = Std.int(destPoint.x);
		var oy = Std.int(destPoint.y);

		for (y in 0...sh)
		{
			var dy = y + oy;
			if (dy < 0 || dy >= height) continue;
			for (x in 0...sw)
			{
				var dx = x + ox;
				if (dx < 0 || dx >= width) continue;
				var argb = pixels[y * sw + x];
				var a = ((argb >>> 24) & 0xFF) / 255.0;
				var i = dy * width + dx;
				srcA[i] = a;
				srcR[i] = (((argb >> 16) & 0xFF) / 255.0) * a;
				srcG[i] = (((argb >> 8) & 0xFF) / 255.0) * a;
				srcB[i] = ((argb & 0xFF) / 255.0) * a;
			}
		}

		var out = new Vector<UInt>(width * height, true);

		for (i in 0...width * height)
		{
			var sr = srcR[i], sg = srcG[i], sb = srcB[i], sa = srcA[i];
			var er = fxR[i], eg = fxG[i], eb = fxB[i], ea = fxA[i];
			var r:Float, g:Float, b:Float, a:Float;

			if (type == INNER)
			{
				var mr = er * sa, mg = eg * sa, mb = eb * sa, ma = ea * sa;
				if (knockout)
				{
					r = mr;
					g = mg;
					b = mb;
					a = ma;
				}
				else
				{
					r = sr * (1 - ea) + mr;
					g = sg * (1 - ea) + mg;
					b = sb * (1 - ea) + mb;
					a = sa;
				}
			}
			else if (type == FULL)
			{
				if (knockout)
				{
					r = er;
					g = eg;
					b = eb;
					a = ea;
				}
				else
				{
					r = sr * (1 - ea) + er;
					g = sg * (1 - ea) + eg;
					b = sb * (1 - ea) + eb;
					a = sa * (1 - ea) + ea;
				}
			}
			else // OUTER
			{
				var k = 1 - sa;
				if (knockout)
				{
					r = er * k;
					g = eg * k;
					b = eb * k;
					a = ea * k;
				}
				else
				{
					r = sr + er * k;
					g = sg + eg * k;
					b = sb + eb * k;
					a = sa + ea * k;
				}
			}

			out[i] = __toStraightARGB(r, g, b, a);
		}

		dest.setVector(dest.rect, out);
		return dest;
	}

	// premultiplied 0..1 -> straight 0xAARRGGBB
	@:noCompletion private static inline function __toStraightARGB(r:Float, g:Float, b:Float, a:Float):UInt
	{
		if (a <= 0) return 0;
		if (a > 1) a = 1;
		var ir = Std.int(__clamp01(r / a) * 255 + 0.5);
		var ig = Std.int(__clamp01(g / a) * 255 + 0.5);
		var ib = Std.int(__clamp01(b / a) * 255 + 0.5);
		var ia = Std.int(a * 255 + 0.5);
		return (ia << 24) | (ir << 16) | (ig << 8) | ib;
	}

	@:noCompletion private static inline function __clamp01(v:Float):Float
	{
		return v < 0 ? 0 : (v > 1 ? 1 : v);
	}
}
#else
typedef BitmapFilter = flash.filters.BitmapFilter;
#end
