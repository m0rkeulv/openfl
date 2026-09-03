package openfl.filters;

#if !flash
import openfl.display.BitmapData;
import openfl.display.DisplayObjectRenderer;
import openfl.display.Shader;
import openfl.geom.ColorTransform;
import openfl.geom.Point;
import openfl.geom.Rectangle;
#if lime
import lime._internal.graphics.ImageDataUtil; // TODO

#end
/**
	The DropShadowFilter class lets you add a drop shadow to display objects.
	The shadow algorithm is based on the same box filter that the blur filter
	uses. You have several options for the style of the drop shadow, including
	inner or outer shadow and knockout mode. You can apply the filter to any
	display object (that is, objects that inherit from the DisplayObject
	class), such as MovieClip, SimpleButton, TextField, and Video objects, as
	well as to BitmapData objects.

	The use of filters depends on the object to which you apply the
	filter:

	* To apply filters to display objects use the `filters`
	property (inherited from DisplayObject). Setting the `filters`
	property of an object does not modify the object, and you can remove the
	filter by clearing the `filters` property.
	* To apply filters to BitmapData objects, use the
	`BitmapData.applyFilter()` method. Calling
	`applyFilter()` on a BitmapData object takes the source
	BitmapData object and the filter object and generates a filtered image as a
	result.

	If you apply a filter to a display object, the value of the
	`cacheAsBitmap` property of the display object is set to
	`true`. If you clear all filters, the original value of
	`cacheAsBitmap` is restored.

	This filter supports Stage scaling. However, it does not support general
	scaling, rotation, and skewing. If the object itself is scaled (if
	`scaleX` and `scaleY` are set to a value other than
	1.0), the filter is not scaled. It is scaled only when the user zooms in on
	the Stage.

	A filter is not applied if the resulting image exceeds the maximum
	dimensions. In AIR 1.5 and Flash Player 10, the maximum is 8,191 pixels in
	width or height, and the total number of pixels cannot exceed 16,777,215
	pixels.(So, if an image is 8,191 pixels wide, it can only be 2,048 pixels
	high.) In Flash Player 9 and earlier and AIR 1.1 and earlier, the
	limitation is 2,880 pixels in height and 2,880 pixels in width. If, for
	example, you zoom in on a large movie clip with a filter applied, the
	filter is turned off if the resulting image exceeds the maximum
	dimensions.

	@see `openfl.display.DisplayObject.filters`
	@see `openfl.display.BitmapData.applyFilter`
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.filters.GlowFilter)
@:access(openfl.geom.ColorTransform)
@:access(openfl.geom.Point)
@:access(openfl.geom.Rectangle)
@:final class DropShadowFilter extends BitmapFilter
{
	@:noCompletion private static var __hideShader = new HideShader();

	/**
		The alpha transparency value for the shadow color. Valid values are 0.0 to
		1.0. For example, .25 sets a transparency value of 25%. The default value
		is 1.0.
	**/
	public var alpha(get, set):Float;

	/**
		The angle of the shadow. Valid values are 0 to 360 degrees (floating
		point). The default value is 45.
	**/
	public var angle(get, set):Float;

	/**
		The amount of horizontal blur. Valid values are 0 to 255.0 (floating
		point). The default value is 4.0.
	**/
	public var blurX(get, set):Float;

	/**
		The amount of vertical blur. Valid values are 0 to 255.0 (floating point).
		The default value is 4.0.
	**/
	public var blurY(get, set):Float;

	/**
		The color of the shadow. Valid values are in hexadecimal format
		_0xRRGGBB_. The default value is 0x000000.
	**/
	public var color(get, set):Int;

	/**
		The offset distance for the shadow, in pixels. The default value is 4.0
		(floating point).
	**/
	public var distance(get, set):Float;

	/**
		Indicates whether or not the object is hidden. The value `true`
		indicates that the object itself is not drawn; only the shadow is visible.
		The default is `false`(the object is shown).
	**/
	public var hideObject(get, set):Bool;

	/**
		Indicates whether or not the shadow is an inner shadow. The value
		`true` indicates an inner shadow. The default is
		`false`, an outer shadow (a shadow around the outer edges of
		the object).
	**/
	public var inner(get, set):Bool;

	/**
		Applies a knockout effect (`true`), which effectively makes the
		object's fill transparent and reveals the background color of the
		document. The default is `false`(no knockout).
	**/
	public var knockout(get, set):Bool;

	/**
		The number of times to apply the filter. The default value is
		`BitmapFilterQuality.LOW`, which is equivalent to applying the
		filter once. The value `BitmapFilterQuality.MEDIUM` applies the
		filter twice; the value `BitmapFilterQuality.HIGH` applies it
		three times. Filters with lower values are rendered more quickly.

		For most applications, a quality value of low, medium, or high is
		sufficient. Although you can use additional numeric values up to 15 to
		achieve different effects, higher values are rendered more slowly. Instead
		of increasing the value of `quality`, you can often get a
		similar effect, and with faster rendering, by simply increasing the values
		of the `blurX` and `blurY` properties.
	**/
	public var quality(get, set):Int;

	/**
		The strength of the imprint or spread. The higher the value, the more
		color is imprinted and the stronger the contrast between the shadow and
		the background. Valid values are from 0 to 255.0. The default is 1.0.
	**/
	public var strength(get, set):Float;

	@:noCompletion private var __alpha:Float;
	@:noCompletion private var __angle:Float;
	@:noCompletion private var __blurX:Float;
	@:noCompletion private var __blurY:Float;
	@:noCompletion private var __color:Int;
	@:noCompletion private var __distance:Float;
	@:noCompletion private var __hideObject:Bool;
	@:noCompletion private var __horizontalPasses:Int;
	@:noCompletion private var __inner:Bool;
	@:noCompletion private var __knockout:Bool;
	@:noCompletion private var __offsetX:Float;
	@:noCompletion private var __offsetY:Float;
	@:noCompletion private var __quality:Int;
	@:noCompletion private var __strength:Float;
	@:noCompletion private var __verticalPasses:Int;

	#if openfljs
	@:noCompletion private static function __init__()
	{
		untyped Object.defineProperties(DropShadowFilter.prototype, {
			"alpha": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_alpha (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_alpha (v); }")
			},
			"angle": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_angle (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_angle (v); }")
			},
			"blurX": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_blurX (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_blurX (v); }")
			},
			"blurY": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_blurY (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_blurY (v); }")
			},
			"color": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_color (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_color (v); }")
			},
			"distance": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_distance (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_distance (v); }")
			},
			"hideObject": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_hideObject (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_hideObject (v); }")
			},
			"inner": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_inner (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_inner (v); }")
			},
			"knockout": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_knockout (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_knockout (v); }")
			},
			"quality": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_quality (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_quality (v); }")
			},
			"strength": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_strength (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_strength (v); }")
			},
		});
	}
	#end

	/**
		Creates a new DropShadowFilter instance with the specified parameters.

		@param distance   Offset distance for the shadow, in pixels.
		@param angle      Angle of the shadow, 0 to 360 degrees (floating point).
		@param color      Color of the shadow, in hexadecimal format
						  _0xRRGGBB_. The default value is 0x000000.
		@param alpha      Alpha transparency value for the shadow color. Valid
						  values are 0.0 to 1.0. For example, .25 sets a
						  transparency value of 25%.
		@param blurX      Amount of horizontal blur. Valid values are 0 to 255.0
						 (floating point).
		@param blurY      Amount of vertical blur. Valid values are 0 to 255.0
						 (floating point).
		@param strength   The strength of the imprint or spread. The higher the
						  value, the more color is imprinted and the stronger the
						  contrast between the shadow and the background. Valid
						  values are 0 to 255.0.
		@param quality    The number of times to apply the filter. Use the
						  BitmapFilterQuality constants:

						   * `BitmapFilterQuality.LOW`
						   * `BitmapFilterQuality.MEDIUM`
						   * `BitmapFilterQuality.HIGH`


						  For more information about these values, see the
						  `quality` property description.
		@param inner      Indicates whether or not the shadow is an inner shadow.
						  A value of `true` specifies an inner shadow.
						  A value of `false` specifies an outer shadow
						 (a shadow around the outer edges of the object).
		@param knockout   Applies a knockout effect (`true`), which
						  effectively makes the object's fill transparent and
						  reveals the background color of the document.
		@param hideObject Indicates whether or not the object is hidden. A value
						  of `true` indicates that the object itself is
						  not drawn; only the shadow is visible.
	**/
	public function new(distance:Float = 4, angle:Float = 45, color:Int = 0, alpha:Float = 1, blurX:Float = 4, blurY:Float = 4, strength:Float = 1,
			quality:Int = 1, inner:Bool = false, knockout:Bool = false, hideObject:Bool = false)
	{
		super();

		__offsetX = 0;
		__offsetY = 0;

		__distance = distance;
		__angle = angle;
		__color = color;
		__alpha = alpha;
		__blurX = blurX;
		__blurY = blurY;
		__strength = strength;
		__quality = quality;
		__inner = inner;
		__knockout = knockout;
		__hideObject = hideObject;

		__updateSize();

		__needSecondBitmapData = true;
		__preserveObject = true;
		__softwareComposite = true;
		__renderDirty = true;
	}

	public override function clone():BitmapFilter
	{
		return new DropShadowFilter(__distance, __angle, __color, __alpha, __blurX, __blurY, __strength, __quality, __inner, __knockout, __hideObject);
	}

	@:noCompletion private override function __applyFilter(bitmapData:BitmapData, sourceBitmapData:BitmapData, sourceRect:Rectangle, destPoint:Point):BitmapData
	{
		var width = bitmapData.width;
		var height = bitmapData.height;

		// blur the source alpha, then read it back shifted by the shadow offset --
		// the GL path does the same by sampling the glow at (coord - offset).
		// An inner shadow blurs the *inverted* alpha (the GL path runs
		// InvertAlphaShader as its first pass) so the shadow falls inside the edge.
		var mask = BitmapFilter.__alphaMask(sourceBitmapData, sourceRect, destPoint, width, height);
		if (__inner)
		{
			for (i in 0...mask.length)
				mask[i] = 1 - mask[i];
		}
		BitmapFilter.__blurMask(mask, width, height, __blurX * __renderScale, __blurY * __renderScale, __quality);

		var cr = ((__color >> 16) & 0xFF) / 255.0;
		var cg = ((__color >> 8) & 0xFF) / 255.0;
		var cb = (__color & 0xFF) / 255.0;
		var ox = Std.int(__offsetX * __renderScale);
		var oy = Std.int(__offsetY * __renderScale);

		var fxR = new Array<Float>(), fxG = new Array<Float>(), fxB = new Array<Float>(), fxA = new Array<Float>();
		for (y in 0...height)
		{
			for (x in 0...width)
			{
				var sx = x - ox;
				var sy = y - oy;
				var f = ((sx < 0 || sx >= width || sy < 0 || sy >= height) ? 0.0 : mask[sy * width + sx]) * __strength;
				if (f > 1) f = 1;
				else if (f < 0) f = 0;
				fxR.push(cr * f);
				fxG.push(cg * f);
				fxB.push(cb * f);
				fxA.push(__alpha * f);
			}
		}

		// hideObject drops the object just like knockout does
		return BitmapFilter.__compositeEffect(bitmapData, sourceBitmapData, sourceRect, destPoint, fxR, fxG, fxB, fxA, __inner ? INNER : OUTER,
			__knockout || __hideObject);
	}

	@:noCompletion private override function __initShader(renderer:DisplayObjectRenderer, pass:Int, sourceBitmapData:BitmapData):Shader
	{
		#if !macro
		// Drop shadow is glow with an offset
		if (__inner && pass == 0)
		{
			return GlowFilter.__invertAlphaShader;
		}

		var blurPass = pass - (__inner ? 1 : 0);
		var numBlurPasses = __horizontalPasses + __verticalPasses;

		if (blurPass < numBlurPasses)
		{
			var strength = blurPass == (numBlurPasses - 1) ? __strength : 1.0;
			var horizontal = blurPass < __horizontalPasses;
			return GlowFilter.__setupBlurAlphaShader(horizontal, (horizontal ? blurX : blurY) * __renderScale, color, alpha, strength);
		}
		if (__inner)
		{
			if (__knockout || __hideObject)
			{
				var shader = GlowFilter.__innerCombineKnockoutShader;
				shader.sourceBitmap.input = sourceBitmapData;
				shader.offset.value[0] = __offsetX * __renderScale;
				shader.offset.value[1] = __offsetY * __renderScale;
				return shader;
			}
			var shader = GlowFilter.__innerCombineShader;
			shader.sourceBitmap.input = sourceBitmapData;
			shader.offset.value[0] = __offsetX * __renderScale;
			shader.offset.value[1] = __offsetY * __renderScale;
			return shader;
		}
		else
		{
			if (__knockout)
			{
				var shader = GlowFilter.__combineKnockoutShader;
				shader.sourceBitmap.input = sourceBitmapData;
				shader.offset.value[0] = __offsetX * __renderScale;
				shader.offset.value[1] = __offsetY * __renderScale;
				return shader;
			}
			else if (__hideObject)
			{
				var shader = __hideShader;
				shader.sourceBitmap.input = sourceBitmapData;
				shader.offset.value[0] = __offsetX * __renderScale;
				shader.offset.value[1] = __offsetY * __renderScale;
				return shader;
			}
			var shader = GlowFilter.__combineShader;
			shader.sourceBitmap.input = sourceBitmapData;
			shader.offset.value[0] = __offsetX * __renderScale;
			shader.offset.value[1] = __offsetY * __renderScale;
			return shader;
		}
		#else
		return null;
		#end
	}

	@:noCompletion private function __updateSize():Void
	{
		__offsetX = Std.int(__distance * Math.cos(__angle * Math.PI / 180));
		__offsetY = Std.int(__distance * Math.sin(__angle * Math.PI / 180));

		// Box blur applies `quality` passes (low, medium, high).
		// each pass widens the shadow by approx. half the blur.
		// so the reach grows to approx. `quality * blur / 2`.
		// If we only reserve one blur radius the shadow is hard-clipped to a rectangle at high quality.
		var q = (__quality > 0) ? __quality : 1;
		var exX = Math.ceil(__blurX * 0.5 * q) + 4;
		var exY = Math.ceil(__blurY * 0.5 * q) + 4;

		__topExtension = Std.int((__offsetY < 0 ? -__offsetY : 0) + exY);
		__bottomExtension = Std.int((__offsetY > 0 ? __offsetY : 0) + exY);
		__leftExtension = Std.int((__offsetX < 0 ? -__offsetX : 0) + exX);
		__rightExtension = Std.int((__offsetX > 0 ? __offsetX : 0) + exX);
		__calculateNumShaderPasses();
	}

	@:noCompletion private function __calculateNumShaderPasses():Void
	{
		var q = (__quality > 0) ? __quality : 1;
		__horizontalPasses = (__blurX <= 0) ? 0 : q;
		__verticalPasses = (__blurY <= 0) ? 0 : q;
		__numShaderPasses = __horizontalPasses + __verticalPasses + (__inner ? 2 : 1);
	}

	// Get & Set Methods
	@:noCompletion private function get_alpha():Float
	{
		return __alpha;
	}

	@:noCompletion private function set_alpha(value:Float):Float
	{
		if (value != __alpha) __renderDirty = true;
		return __alpha = value;
	}

	@:noCompletion private function get_angle():Float
	{
		return __angle;
	}

	@:noCompletion private function set_angle(value:Float):Float
	{
		if (value != __angle)
		{
			__angle = value;
			__renderDirty = true;
			__updateSize();
		}
		return value;
	}

	@:noCompletion private function get_blurX():Float
	{
		return __blurX;
	}

	@:noCompletion private function set_blurX(value:Float):Float
	{
		if (value != __blurX)
		{
			__blurX = value;
			__renderDirty = true;
			__updateSize();
		}
		return value;
	}

	@:noCompletion private function get_blurY():Float
	{
		return __blurY;
	}

	@:noCompletion private function set_blurY(value:Float):Float
	{
		if (value != __blurY)
		{
			__blurY = value;
			__renderDirty = true;
			__updateSize();
		}
		return value;
	}

	@:noCompletion private function get_color():Int
	{
		return __color;
	}

	@:noCompletion private function set_color(value:Int):Int
	{
		if (value != __color) __renderDirty = true;
		return __color = value;
	}

	@:noCompletion private function get_distance():Float
	{
		return __distance;
	}

	@:noCompletion private function set_distance(value:Float):Float
	{
		if (value != __distance)
		{
			__distance = value;
			__renderDirty = true;
			__updateSize();
		}
		return value;
	}

	@:noCompletion private function get_hideObject():Bool
	{
		return __hideObject;
	}

	@:noCompletion private function set_hideObject(value:Bool):Bool
	{
		if (value != __hideObject)
		{
			__renderDirty = true;
		}
		return __hideObject = value;
	}

	@:noCompletion private function get_inner():Bool
	{
		return __inner;
	}

	@:noCompletion private function set_inner(value:Bool):Bool
	{
		if (value != __inner) __renderDirty = true;
		return __inner = value;
	}

	@:noCompletion private function get_knockout():Bool
	{
		return __knockout;
	}

	@:noCompletion private function set_knockout(value:Bool):Bool
	{
		if (value != __knockout) __renderDirty = true;
		return __knockout = value;
	}

	@:noCompletion private function get_quality():Int
	{
		return __quality;
	}

	@:noCompletion private function set_quality(value:Int):Int
	{
		if (value != __quality)
		{
			__renderDirty = true;
			__quality = value;
			__updateSize(); // passes & extension both depend on quality
		}
		return __quality = value;
	}

	@:noCompletion private function get_strength():Float
	{
		return __strength;
	}

	@:noCompletion private function set_strength(value:Float):Float
	{
		if (value != __strength) __renderDirty = true;
		return __strength = value;
	}
}

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
private class HideShader extends BitmapFilterShader
{
	@:glFragmentSource("
		uniform sampler2D openfl_Texture;
		uniform sampler2D sourceBitmap;
		varying vec4 textureCoords;

		void main(void) {
			gl_FragColor = texture2D(openfl_Texture, textureCoords.zw);
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
		#end
	}
}
#else
typedef DropShadowFilter = flash.filters.DropShadowFilter;
#end
