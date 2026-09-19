package openfl.display._internal;

#if !flash
import openfl.display.BitmapData;
import openfl.filters.BitmapFilterShader;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@SuppressWarnings("checkstyle:FieldDocComment")
class BlendModeShader extends BitmapFilterShader
{
	@:glFragmentSource("varying vec2 openfl_TextureCoordv;
		uniform sampler2D openfl_Texture;
		uniform sampler2D uBackdrop;
		uniform vec2 uBackdropFlip;
		uniform int uMode;
		uniform bool uDiscardTransparent;

		vec3 hardLight(vec3 base, vec3 control) {
			return mix(2.0 * base * control, 1.0 - 2.0 * (1.0 - base) * (1.0 - control), step(0.5, control));
		}

		void main(void) {
			vec4 src = texture2D(openfl_Texture, openfl_TextureCoordv);
			vec4 dst = texture2D(uBackdrop, vec2(openfl_TextureCoordv.x, openfl_TextureCoordv.y * uBackdropFlip.x + uBackdropFlip.y));

			float srcAlpha = src.a;
			float dstAlpha = dst.a;

			// a texel the shape did not draw: leave the backdrop alone (see applyDiscardTransparent)
			if (uDiscardTransparent && srcAlpha == 0.0) discard;

			// where the backdrop is transparent the source shows as it is, under every mode
			vec3 sourceOnly = src.rgb * (1.0 - dstAlpha);
			float coverage = srcAlpha + dstAlpha - srcAlpha * dstAlpha;

			if (uMode >= 6) {
				// Flash's own formulas on premultiplied colour, not a blend of straight colours
				if (uMode == 6) gl_FragColor = vec4(sourceOnly + max(vec3(0.0), dst.rgb - src.rgb * dstAlpha), coverage);								// SUBTRACT
				else if (uMode == 7) gl_FragColor = vec4(sourceOnly + dst.rgb * (1.0 - 2.0 * srcAlpha) + srcAlpha * dstAlpha, coverage);				// INVERT
				else if (uMode == 8) gl_FragColor = vec4(sourceOnly + dst.rgb * (1.0 - srcAlpha), srcAlpha * (1.0 - dstAlpha) + dstAlpha * (1.0 - srcAlpha));	// ERASE
				else gl_FragColor = vec4(sourceOnly + dst.rgb * srcAlpha, srcAlpha * (1.0 - dstAlpha) + dstAlpha * srcAlpha);								// ALPHA
				return;
			}

			vec3 s = srcAlpha > 0.0 ? src.rgb / srcAlpha : vec3(0.0);
			vec3 d = dstAlpha > 0.0 ? dst.rgb / dstAlpha : vec3(0.0);

			vec3 blend;

			if (uMode == 0) blend = abs(d - s); 			// DIFFERENCE
			else if (uMode == 1) blend = d * s; 			// MULTIPLY
			else if (uMode == 2) blend = min(d, s); 		// DARKEN
			else if (uMode == 3) blend = max(d, s); 		// LIGHTEN
			else if (uMode == 4) blend = hardLight(d, s); 	// HARDLIGHT
			else blend = hardLight(s, d); 					// OVERLAY

			// separable blend over a possibly transparent backdrop (PDF compositing)
			vec3 backdropOnly = dst.rgb * (1.0 - srcAlpha);
			vec3 weightedBlend = srcAlpha * dstAlpha * blend;

			gl_FragColor = vec4(sourceOnly + backdropOnly + weightedBlend, coverage);
		}")
	public function new()
	{
		super();

		#if !macro
		uBackdropFlip.value = [1, 0];
		uMode.value = [0];
		uDiscardTransparent.value = [false];
		#end
	}

	public function init(backdrop:BitmapData, mode:Int, flipScale:Float, flipOffset:Float, discardTransparent:Bool):Void
	{
		#if !macro
		uDiscardTransparent.value[0] = discardTransparent;
		uBackdrop.input = backdrop;
		uBackdrop.filter = NEAREST;
		uBackdrop.mipFilter = MIPNONE;
		uBackdrop.wrap = CLAMP;
		uMode.value[0] = mode;
		uBackdropFlip.value[0] = flipScale;
		uBackdropFlip.value[1] = flipOffset;
		#end
	}
}
#end
