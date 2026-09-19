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
		uniform vec4 uDrawn;

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

			// every mode is the source on its own where the backdrop is transparent, plus the
			// backdrop's share from the mode's formula, with the part of the backdrop alpha that
			// stays (PDF compositing on premultiplied colour)
			vec3 sourceOnly = src.rgb * (1.0 - dstAlpha);
			float sourceAlpha = srcAlpha * (1.0 - dstAlpha);
			float kept = 1.0;

			vec3 backdrop;

			if (uMode < 6) {
				// a separable blend of the straight colours, weighted by both alphas
				vec3 s = srcAlpha > 0.0 ? src.rgb / srcAlpha : vec3(0.0);
				vec3 d = dstAlpha > 0.0 ? dst.rgb / dstAlpha : vec3(0.0);

				vec3 blend;

				if (uMode == 0) blend = abs(d - s); 			// DIFFERENCE
				else if (uMode == 1) blend = d * s; 			// MULTIPLY
				else if (uMode == 2) blend = min(d, s); 		// DARKEN
				else if (uMode == 3) blend = max(d, s); 		// LIGHTEN
				else if (uMode == 4) blend = hardLight(d, s); 	// HARDLIGHT
				else blend = hardLight(s, d); 					// OVERLAY

				backdrop = dst.rgb * (1.0 - srcAlpha) + srcAlpha * dstAlpha * blend;

			} else {
				// Flash's own formulas, not a blend of colours
				if (uMode == 6) backdrop = max(vec3(0.0), dst.rgb - src.rgb * dstAlpha);					// SUBTRACT
				else if (uMode == 7) backdrop = dst.rgb * (1.0 - 2.0 * srcAlpha) + srcAlpha * dstAlpha;		// INVERT
				else if (uMode == 8) { backdrop = dst.rgb * (1.0 - srcAlpha); kept = 1.0 - srcAlpha; }		// ERASE
				else if (uMode == 9){ backdrop = dst.rgb * srcAlpha; kept = srcAlpha; }									// ALPHA

				// these four show the source as it is only where nothing was drawn before (outside
				// uDrawn). Over a backdrop a mask left transparent, SUBTRACT and INVERT leave a
				// black or white silhouette at the object's alpha and ERASE and ALPHA leave nothing
				vec2 uv = openfl_TextureCoordv;
				bool drawn = uv.x >= uDrawn.x && uv.x < uDrawn.z && uv.y >= uDrawn.y && uv.y < uDrawn.w;

				if (drawn) {
					sourceOnly = (uMode == 7) ? vec3(sourceAlpha) : vec3(0.0);
					if (uMode >= 8) sourceAlpha = 0.0;
				}
			}

			gl_FragColor = vec4(sourceOnly + backdrop, sourceAlpha + dstAlpha * kept);
		}")
	public function new()
	{
		super();

		#if !macro
		uBackdropFlip.value = [1, 0];
		uMode.value = [0];
		uDiscardTransparent.value = [false];
		uDrawn.value = [0, 0, 1, 1];
		#end
	}
	/** The part of the group drawn into before, as texture coordinates (x0, y0, x1, y1). **/
	public function setDrawn(x0:Float, y0:Float, x1:Float, y1:Float):Void
	{
		#if !macro
		uDrawn.value[0] = x0;
		uDrawn.value[1] = y0;
		uDrawn.value[2] = x1;
		uDrawn.value[3] = y1;
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
