package openfl.filters;

#if !flash
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.display.DisplayObjectRenderer;
import openfl.display.Shader;
import openfl.geom.Point;
import haxe.ds.Vector;
import haxe.io.Bytes;
import openfl.geom.Rectangle;

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
@:access(openfl.geom.Rectangle)
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
	**/
	@:noCompletion private var __softwareComposite:Bool;

	/**
		Set by the display-list software path while `__applyFilter` runs where the
		object itself sits inside the padded cache bitmap it is given as source (in
		device pixels). `null` when the source is the object (BitmapData.applyFilter).
	**/
	@:noCompletion private var __objectRect:Rectangle;

	/**
		The device-pixel scale the filter is being rendered at.

		A filtered object is cached into a bitmap sized and drawn at the renderer's
		pixel ratio, so on a HiDPI display the object is (say) 1.5x larger in that
		bitmap. Filter distances, blur radius, and offsets are authored in
		*logical* pixels, so they must be scaled to match, otherwise the effect comes
		out 1/pixelRatio too small relative to its content.

		The renderer sets this before using the filter. It stays 1 for
		`BitmapData.applyFilter`, which works on the bitmap's own pixels.
	**/
	@:noCompletion private var __renderScale:Float;

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
		__renderScale = 1;
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


	// Flash rounds a distance offset down
	@:noCompletion private static inline function __offsetFloor(v:Float):Int
	{
		return Math.floor(v);
	}

	/**
		The source's alpha channel as a 0..1 mask laid out on the destination
		grid, using the sourceRect/destPoint mapping `__applyFilter` is given.
		Samples outside the source read 0, matching the transparent border the GL
		path gets from its cache texture.
	**/
	@:noCompletion private static function __alphaMask(source:BitmapData, sourceRect:Rectangle, destPoint:Point, width:Int, height:Int):Vector<Float>
	{
		var mask = __channel(width * height);

		var pixels = __argbPixels(source, sourceRect);
		var length = pixels.length;

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
				var p = (y * sw + x) * 4;
				if (p < length) mask[dy * width + dx] = pixels.get(p) / 255.0;
			}
		}
		return mask;
	}

	/**
		Box-blur a 0..1 mask in place, matching `BoxBlurShader`: `quality`
		iterations of one horizontal then one vertical pass.
	**/
	@:noCompletion private static function __blurMask(mask:Vector<Float>, width:Int, height:Int, blurX:Float, blurY:Float, quality:Int):Vector<Float>
	{
		var passes = (quality > 0) ? quality : 1;
		var scratch = __channel(mask.length);

		for (i in 0...passes)
		{
			__blurMaskAxis(mask, scratch, width, height, blurX, true);
			__blurMaskAxis(scratch, mask, width, height, blurY, false);
		}
		return mask;
	}

	@:noCompletion private static function __blurMaskAxis(src:Vector<Float>, dest:Vector<Float>, width:Int, height:Int, blur:Float, horizontal:Bool):Void
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

		// the box around the mask's samples that are not 0, grown by the blur's reach along its axis:
		// outside it every sample the blur reads is 0, and so is the result
		var left = width, top = height, right = -1, bottom = -1;
		for (y in 0...height)
		{
			for (x in 0...width)
			{
				if (src[y * width + x] == 0) continue;
				if (x < left) left = x;
				if (x > right) right = x;
				if (y < top) top = y;
				bottom = y;
			}
		}
		if (horizontal)
		{
			left -= edge;
			right += edge;
		}
		else
		{
			top -= edge;
			bottom += edge;
		}

		for (y in 0...height)
		{
			for (x in 0...width)
			{
				if (x < left || x > right || y < top || y > bottom)
				{
					dest[y * width + x] = 0;
					continue;
				}

				var sum = __maskAt(src, width, height, x, y);

				for (i in 1...(n + 1))
				{
					if (horizontal) sum += __maskAt(src, width, height, x + i, y) + __maskAt(src, width, height, x - i, y);
					else sum += __maskAt(src, width, height, x, y + i) + __maskAt(src, width, height, x, y - i);
				}

				if (horizontal) sum += (__maskAt(src, width, height, x + edge, y) + __maskAt(src, width, height, x - edge, y)) * frac;
				else sum += (__maskAt(src, width, height, x, y + edge) + __maskAt(src, width, height, x, y - edge)) * frac;

				dest[y * width + x] = Math.floor((sum / fullSize) * 255) / 255;
			}
		}
	}

	@:noCompletion private static inline function __maskAt(mask:Vector<Float>, width:Int, height:Int, x:Int, y:Int):Float
	{
		return (x < 0 || x >= width || y < 0 || y >= height) ? 0.0 : mask[y * width + x];
	}


	@:noCompletion private static function __maskAtFrac(mask:Vector<Float>, width:Int, height:Int, fx:Float, fy:Float):Float
	{
		var x0 = Math.floor(fx), y0 = Math.floor(fy);
		var tx = fx - x0, ty = fy - y0;
		var top = __maskAt(mask, width, height, x0, y0) * (1 - tx) + __maskAt(mask, width, height, x0 + 1, y0) * tx;
		var bottom = __maskAt(mask, width, height, x0, y0 + 1) * (1 - tx) + __maskAt(mask, width, height, x0 + 1, y0 + 1) * tx;
		return top * (1 - ty) + bottom * ty;
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
	@:noCompletion private static function __compositeEffect(dest:BitmapData, source:BitmapData, sourceRect:Rectangle, destPoint:Point, fxR:Vector<Float>,
			fxG:Vector<Float>, fxB:Vector<Float>, fxA:Vector<Float>, type:BitmapFilterType, knockout:Bool):BitmapData
	{
		var width = dest.width;
		var height = dest.height;

		var pixels = __argbPixels(source, sourceRect);
		var length = pixels.length;

		var sourceWidth = Std.int(sourceRect.width);
		var sourceHeight = Std.int(sourceRect.height);
		var destOffsetX = Std.int(destPoint.x);
		var destOffsetY = Std.int(destPoint.y);

		// starts transparent: a pixel that is skipped stays 0
		var out = Bytes.alloc(width * height * 4);
		// BitmapFilterType is an abstract over Null<Int>: compared per pixel, its constants are boxed
		var inner = (type == INNER);
		var full = (type == FULL);

		for (y in 0...height)
		{
			var sourceY = y - destOffsetY;
			var rowInSource = (sourceY >= 0 && sourceY < sourceHeight);

			for (x in 0...width)
			{
				var i = y * width + x;

				// the source pixel on the destination grid, premultiplied; transparent outside the source
				var sourceR = 0.0, sourceG = 0.0, sourceB = 0.0, sourceA = 0.0;
				var sourceX = x - destOffsetX;
				if (rowInSource && sourceX >= 0 && sourceX < sourceWidth)
				{
					var p = (sourceY * sourceWidth + sourceX) * 4;
					if (p < length && pixels.get(p) != 0)
					{
						sourceA = pixels.get(p) / 255.0;
						sourceR = (pixels.get(p + 1) / 255.0) * sourceA;
						sourceG = (pixels.get(p + 2) / 255.0) * sourceA;
						sourceB = (pixels.get(p + 3) / 255.0) * sourceA;
					}
				}

				var effectA = fxA[i];
				// no source and no effect gives alpha 0 in every mode, and so does no source alone
				// when the effect is confined to the shape
				if (sourceA == 0 && (inner || effectA == 0)) continue;

				var effectR = fxR[i], effectG = fxG[i], effectB = fxB[i];
				var r:Float, g:Float, b:Float, a:Float;

				if (inner)
				{
					// the effect confined to the shape: scaled by the source alpha
					var maskedR = effectR * sourceA, maskedG = effectG * sourceA, maskedB = effectB * sourceA, maskedA = effectA * sourceA;
					if (knockout)
					{
						r = maskedR;
						g = maskedG;
						b = maskedB;
						a = maskedA;
					}
					else
					{
						r = sourceR * (1 - effectA) + maskedR;
						g = sourceG * (1 - effectA) + maskedG;
						b = sourceB * (1 - effectA) + maskedB;
						a = sourceA;
					}
				}
				else if (full)
				{
					if (knockout)
					{
						r = effectR;
						g = effectG;
						b = effectB;
						a = effectA;
					}
					else
					{
						r = sourceR * (1 - effectA) + effectR;
						g = sourceG * (1 - effectA) + effectG;
						b = sourceB * (1 - effectA) + effectB;
						a = sourceA * (1 - effectA) + effectA;
					}
				}
				else // OUTER
				{
					var outside = 1 - sourceA; // how much of this pixel lies outside the shape
					if (knockout)
					{
						r = effectR * outside;
						g = effectG * outside;
						b = effectB * outside;
						a = effectA * outside;
					}
					else
					{
						r = sourceR + effectR * outside;
						g = sourceG + effectG * outside;
						b = sourceB + effectB * outside;
						a = sourceA + effectA * outside;
					}
				}

				var color:Int = __toStraightARGB(r, g, b, a);
				out.set(i * 4, color >>> 24);
				out.set(i * 4 + 1, color >> 16);
				out.set(i * 4 + 2, color >> 8);
				out.set(i * 4 + 3, color);
			}
		}

		__setArgbPixels(dest, out);
		return dest;
	}

	/**
		One channel of `length` pixels, all 0: a fixed-size array made once at its final size (a native
		float array on HashLink and hxcpp), instead of an Array grown by push.
	**/
	@:noCompletion private static function __channel(length:Int):Vector<Float>
	{
		var channel = new Vector<Float>(length);
		// static targets start a Vector at 0; the others start it empty
		#if !target.static
		for (i in 0...length)
			channel[i] = 0;
		#end
		return channel;
	}

	/**
		The pixels of `rect` as straight ARGB, four bytes per pixel in the order A, R, G, B: what
		`getVector` returns, read from the image without the ByteArray and the Vector in between.
	**/
	@:noCompletion private static function __argbPixels(source:BitmapData, rect:Rectangle):Bytes
	{
		#if lime
		return source.image.getPixels(rect.__toLimeRectangle(), ARGB32);
		#else
		return Bytes.alloc(0);
		#end
	}

	/** Writes straight ARGB pixels laid out as `__argbPixels` returns them over the whole of `dest`. **/
	@:noCompletion private static function __setArgbPixels(dest:BitmapData, pixels:Bytes):Void
	{
		#if lime
		dest.image.setPixels(dest.rect.__toLimeRectangle(), pixels, ARGB32, BIG_ENDIAN);
		#end
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
