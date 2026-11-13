package openfl.filters;

#if !flash
import openfl.display.BitmapData;
import openfl.display.DisplayObjectRenderer;
import openfl.display.Shader;
import openfl.geom.Point;
import openfl.geom.Rectangle;
#if lime
import lime._internal.graphics.ImageCanvasUtil; // TODO
import lime.graphics.PixelFormat;
import lime.math.RGBA;
#end

/**
	The ColorMatrixFilter class lets you apply a 4 x 5 matrix transformation
	on the RGBA color and alpha values of every pixel in the input image to
	produce a result with a new set of RGBA color and alpha values. It allows
	saturation changes, hue rotation, luminance to alpha, and various other
	effects. You can apply the filter to any display object (that is, objects
	that inherit from the DisplayObject class), such as MovieClip,
	SimpleButton, TextField, and Video objects, as well as to BitmapData
	objects.

	**Note:** For RGBA values, the most significant byte represents the red
	channel value, followed by green, blue, and then alpha.

	To create a new color matrix filter, use the syntax `new
	ColorMatrixFilter()`. The use of filters depends on the object to which
	you apply the filter:

	* To apply filters to movie clips, text fields, buttons, and video, use
	the `filters` property (inherited from DisplayObject). Setting the
	`filters` property of an object does not modify the object, and you can
	remove the filter by clearing the `filters` property.
	* To apply filters to BitmapData objects, use the
	`BitmapData.applyFilter()` method. Calling `applyFilter()` on a BitmapData
	object takes the source BitmapData object and the filter object and
	generates a filtered image as a result.

	If you apply a filter to a display object, the `cacheAsBitmap` property of
	the display object is set to `true`. If you remove all filters, the
	original value of `cacheAsBitmap` is restored.

	A filter is not applied if the resulting image exceeds the maximum
	dimensions. In AIR 1.5 and Flash Player 10, the maximum is 8,191 pixels in
	width or height, and the total number of pixels cannot exceed 16,777,215
	pixels. (So, if an image is 8,191 pixels wide, it can only be 2,048 pixels
	high.) In Flash Player 9 and earlier and AIR 1.1 and earlier, the
	limitation is 2,880 pixels in height and 2,880 pixels in width. For
	example, if you zoom in on a large movie clip with a filter applied, the
	filter is turned off if the resulting image reaches the maximum
	dimensions.

	@see `openfl.display.DisplayObject.filters`
	@see `openfl.display.BitmapData.applyFilter`
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:final class ColorMatrixFilter extends BitmapFilter
{
	@:noCompletion private static var __colorMatrixShader:ColorMatrixShader = new ColorMatrixShader();

	/**
		An array of 20 items for 4 x 5 color transform. The `matrix` property
		cannot be changed by directly modifying its value (for example,
		`myFilter.matrix[2] = 1;`). Instead, you must get a reference to the
		array, make the change to the reference, and reset the value.
		The color matrix filter separates each source pixel into its red,
		green, blue, and alpha components as srcR, srcG, srcB, srcA. To
		calculate the result of each of the four channels, the value of each
		pixel in the image is multiplied by the values in the transformation
		matrix. An offset, between -255 and 255, can optionally be added to
		each result (the fifth item in each row of the matrix). The filter
		combines each color component back into a single pixel and writes out
		the result. In the following formula, a[0] through a[19] correspond to
		entries 0 through 19 in the 20-item array that is passed to the
		`matrix` property:

		```
		redResult   = (a[0]  * srcR) + (a[1]  * srcG) + (a[2]  * srcB) + (a[3]  * srcA) + a[4]
		greenResult = (a[5]  * srcR) + (a[6]  * srcG) + (a[7]  * srcB) + (a[8]  * srcA) + a[9]
		blueResult  = (a[10] * srcR) + (a[11] * srcG) + (a[12] * srcB) + (a[13] * srcA) + a[14]
		alphaResult = (a[15] * srcR) + (a[16] * srcG) + (a[17] * srcB) + (a[18] * srcA) + a[19]
		```

		For each color value in the array, a value of 1 is equal to 100% of
		that channel being sent to the output, preserving the value of the
		color channel.

		The calculations are performed on unmultiplied color values. If the
		input graphic consists of premultiplied color values, those values are
		automatically converted into unmultiplied color values for this
		operation.

		Two optimized modes are available:

		**Alpha only.** When you pass to the filter a matrix that adjusts only
		the alpha component, as shown here, the filter optimizes its
		performance:

		```
		1 0 0 0 0
		0 1 0 0 0
		0 0 1 0 0
		0 0 0 N 0  (where N is between 0.0 and 1.0)
		```

		**Faster version**. Available only with SSE/AltiVec
		accelerator-enabled processors, such as Intel<sup>®</sup>
		Pentium<sup>®</sup> 3 and later and Apple<sup>®</sup> G4 and later.
		The accelerator is used when the multiplier terms are in the range
		-15.99 to 15.99 and the adder terms a[4], a[9], a[14], and a[19] are
		in the range -8000 to 8000.

		@throws TypeError The Array is `null` when being set
	**/
	public var matrix(get, set):Array<Float>;

	@:noCompletion private var __matrix:Array<Float>;

	#if openfljs
	@:noCompletion private static function __init__()
	{
		untyped Object.defineProperties(ColorMatrixFilter.prototype, {
			"matrix": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_matrix (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_matrix (v); }")
			},
		});
	}
	#end

	/**
		Initializes a new ColorMatrixFilter instance with the specified
		parameters.
	**/
	public function new(matrix:Array<Float> = null)
	{
		super();

		this.matrix = matrix;

		__numShaderPasses = 1;
		__needSecondBitmapData = false;
	}

	public override function clone():BitmapFilter
	{
		return new ColorMatrixFilter(__matrix);
	}

	@:noCompletion private override function __applyFilter(destBitmapData:BitmapData, sourceBitmapData:BitmapData, sourceRect:Rectangle,
			destPoint:Point):BitmapData
	{
		#if lime
		var sourceImage = sourceBitmapData.image;
		var image = destBitmapData.image;

		#if (js && html5)
		ImageCanvasUtil.convertToData(sourceImage);
		ImageCanvasUtil.convertToData(image);
		#end

		var sourceData = sourceImage.data;
		var destData = image.data;

		var offsetX = Std.int(destPoint.x - sourceRect.x);
		var offsetY = Std.int(destPoint.y - sourceRect.y);
		var sourceStride = sourceBitmapData.width * 4;
		var destStride = destBitmapData.width * 4;

		var sourceFormat = sourceImage.buffer.format;
		var destFormat = image.buffer.format;
		var sourcePremultiplied = sourceImage.buffer.premultiplied;
		var destPremultiplied = image.buffer.premultiplied;

		// where each channel sits in a pixel of either image, worked out once
		var sourceR = __channelOffset(sourceFormat, 0), sourceG = __channelOffset(sourceFormat, 1);
		var sourceB = __channelOffset(sourceFormat, 2), sourceA = __channelOffset(sourceFormat, 3);
		var destR = __channelOffset(destFormat, 0), destG = __channelOffset(destFormat, 1);
		var destB = __channelOffset(destFormat, 2), destA = __channelOffset(destFormat, 3);

		// reading a UInt8Array element allocates on HashLink (lime's ArrayBufferIO.getUint8 returns
		// Null<UInt>), so the source is read through the Bytes under it
		#if !js
		var sourceBytes = sourceData.buffer;
		var sourceStart = sourceData.byteOffset;
		#end

		// one row of the matrix per output channel: its share of the input's red, green, blue and alpha, then an offset
		var m = __matrix;
		var redFromR = m[0], redFromG = m[1], redFromB = m[2], redFromA = m[3], redOffset = m[4];
		var greenFromR = m[5], greenFromG = m[6], greenFromB = m[7], greenFromA = m[8], greenOffset = m[9];
		var blueFromR = m[10], blueFromG = m[11], blueFromB = m[12], blueFromA = m[13], blueOffset = m[14];
		var alphaFromR = m[15], alphaFromG = m[16], alphaFromB = m[17], alphaFromA = m[18], alphaOffset = m[19];

		var sourcePixel:RGBA = 0, destPixel:RGBA = 0;
		var sourceOffset:Int, destOffset:Int;

		for (row in Std.int(sourceRect.y)...Std.int(sourceRect.height))
		{
			for (column in Std.int(sourceRect.x)...Std.int(sourceRect.width))
			{
				sourceOffset = (row * sourceStride) + (column * 4);
				destOffset = ((row + offsetX) * destStride) + ((column + offsetY) * 4);

				#if js
				sourcePixel.set(sourceData[sourceOffset + sourceR], sourceData[sourceOffset + sourceG], sourceData[sourceOffset + sourceB],
					sourceData[sourceOffset + sourceA]);
				#else
				var at = sourceStart + sourceOffset;
				sourcePixel.set(sourceBytes.get(at + sourceR), sourceBytes.get(at + sourceG), sourceBytes.get(at + sourceB), sourceBytes.get(at + sourceA));
				#end
				if (sourcePremultiplied) sourcePixel.unmultiplyAlpha();

				if (sourcePixel.a == 0)
				{
					destPixel = 0;
				}
				else
				{
					var r = sourcePixel.r, g = sourcePixel.g, b = sourcePixel.b, a = sourcePixel.a;
					destPixel.set(
						__toByte(redFromR * r + redFromG * g + redFromB * b + redFromA * a + redOffset),
						__toByte(greenFromR * r + greenFromG * g + greenFromB * b + greenFromA * a + greenOffset),
						__toByte(blueFromR * r + blueFromG * g + blueFromB * b + blueFromA * a + blueOffset),
						__toByte(alphaFromR * r + alphaFromG * g + alphaFromB * b + alphaFromA * a + alphaOffset));
				}

				if (destPremultiplied) destPixel.multiplyAlpha();
				destData[destOffset + destR] = destPixel.r;
				destData[destOffset + destG] = destPixel.g;
				destData[destOffset + destB] = destPixel.b;
				destData[destOffset + destA] = destPixel.a;
			}
		}

		destBitmapData.image.dirty = true;
		#end
		return destBitmapData;
	}

	/** A matrix result as a channel value: cut to 0..255, the fraction dropped. **/
	@:noCompletion private static inline function __toByte(value:Float):Int
	{
		return Std.int(value < 0 ? 0 : (value > 255 ? 255 : value));
	}

	#if lime
	/** The byte of channel `channel` (0 red, 1 green, 2 blue, 3 alpha) within a pixel of `format`. **/
	@:noCompletion private static function __channelOffset(format:PixelFormat, channel:Int):Int
	{
		return switch (format)
		{
			case BGRA32: [2, 1, 0, 3][channel];
			case ARGB32: [1, 2, 3, 0][channel];
			default: channel; // RGBA32
		}
	}
	#end

	@:noCompletion private override function __initShader(renderer:DisplayObjectRenderer, pass:Int, sourceBitmapData:BitmapData):Shader
	{
		__colorMatrixShader.init(matrix);
		return __colorMatrixShader;
	}

	// Get & Set Methods
	@:noCompletion private function get_matrix():Array<Float>
	{
		// need to return a copy because we shouldn't allow values within the
		// matrix array to be modified directly. instead, the user should pass a
		// whole array to the matrix property
		return __matrix.copy();
	}

	@:noCompletion private function set_matrix(value:Array<Float>):Array<Float>
	{
		if (value == null)
		{
			value = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
		}

		return __matrix = value;
	}
}

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@SuppressWarnings("checkstyle:FieldDocComment")
private class ColorMatrixShader extends BitmapFilterShader
{
	@:glFragmentSource("varying vec2 openfl_TextureCoordv;
		uniform sampler2D openfl_Texture;

		uniform mat4 uMultipliers;
		uniform vec4 uOffsets;

		void main(void) {

			vec4 color = texture2D (openfl_Texture, openfl_TextureCoordv);

			if (color.a == 0.0) {

				gl_FragColor = vec4 (0.0, 0.0, 0.0, 0.0);

			} else {

				color = vec4 (color.rgb / color.a, color.a);
				color = uOffsets + color * uMultipliers;

				gl_FragColor = vec4 (color.rgb * color.a, color.a);

			}

		}")
	public function new()
	{
		super();

		#if !macro
		uMultipliers.value = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
		uOffsets.value = [0, 0, 0, 0];
		#end
	}

	public function init(matrix:Array<Float>):Void
	{
		#if !macro
		var multipliers = uMultipliers.value;
		var offsets = uOffsets.value;

		multipliers[0] = matrix[0];
		multipliers[1] = matrix[1];
		multipliers[2] = matrix[2];
		multipliers[3] = matrix[3];
		multipliers[4] = matrix[5];
		multipliers[5] = matrix[6];
		multipliers[6] = matrix[7];
		multipliers[7] = matrix[8];
		multipliers[8] = matrix[10];
		multipliers[9] = matrix[11];
		multipliers[10] = matrix[12];
		multipliers[11] = matrix[13];
		multipliers[12] = matrix[15];
		multipliers[13] = matrix[16];
		multipliers[14] = matrix[17];
		multipliers[15] = matrix[18];

		offsets[0] = matrix[4] / 255.0;
		offsets[1] = matrix[9] / 255.0;
		offsets[2] = matrix[14] / 255.0;
		offsets[3] = matrix[19] / 255.0;
		#end
	}
}
#else
typedef ColorMatrixFilter = flash.filters.ColorMatrixFilter;
#end
