package openfl.display._internal;

#if !flash
import openfl.display.BitmapData;
import openfl.filters.BitmapFilterShader;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.display.BitmapData)
@SuppressWarnings("checkstyle:FieldDocComment")
class BlendModeShader extends BitmapFilterShader
{

	@:glFragmentSource("varying vec2 openfl_TextureCoordv;
		uniform sampler2D openfl_Texture;
		uniform sampler2D uBackdrop;
		uniform vec4 uBackdropFrame;
		uniform float uAlpha;
		uniform int uMode;
		uniform bool uDiscardTransparent;
		uniform vec4 uDrawn;
		uniform sampler2D uCoverage;
		uniform bool uHasCoverage;

		vec3 hardLight(vec3 base, vec3 control) {
			return mix(2.0 * base * control, 1.0 - 2.0 * (1.0 - base) * (1.0 - control), step(0.5, control));
		}

		void main(void) {
			// the source is the object's own texture, at its alpha; the backdrop copy is read at
			// this fragment's position in the framebuffer (see setBackdrop), so the source quad
			// can be a group at the backdrop's rectangle or the object drawn with its own matrix
			vec4 src = texture2D(openfl_Texture, openfl_TextureCoordv) * uAlpha;
			vec2 backdropCoord = (gl_FragCoord.xy - uBackdropFrame.xy) * uBackdropFrame.zw;
			vec4 dst = texture2D(uBackdrop, backdropCoord);

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
				else if (uMode == 9) {																		// ALPHA
					// with a coverage of the object, the backdrop is kept by 1 - coverage + alpha: what
					// the object did not cover stays, what it covered stays by its alpha
					float keep = uHasCoverage ? min(1.0, 1.0 - texture2D(uCoverage, openfl_TextureCoordv).a + srcAlpha) : srcAlpha;
					backdrop = dst.rgb * keep;
					kept = keep;
				}

				// these four show the source as it is only where nothing was drawn before (outside
				// uDrawn, in backdrop coordinates). Over a backdrop a mask left transparent, SUBTRACT
				// and INVERT leave a black or white silhouette at the object's alpha and ERASE and
				// ALPHA leave nothing
				bool drawn = backdropCoord.x >= uDrawn.x && backdropCoord.x < uDrawn.z && backdropCoord.y >= uDrawn.y && backdropCoord.y < uDrawn.w;

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
		uBackdropFrame.value = [0, 0, 1, 1];
		uAlpha.value = [1];
		uMode.value = [0];
		uDiscardTransparent.value = [false];
		uDrawn.value = [0, 0, 1, 1];
		uHasCoverage.value = [false];
		#end
	}
	/**
		Sets the copy of the backdrop the shader blends against. (x, y) is the framebuffer position the
		copy was taken from, so that the fragment position maps straight onto it.
	**/
	public function setBackdrop(backdrop:BitmapData, x:Float, y:Float):Void
	{
		#if !macro
		uBackdrop.input = backdrop;
		uBackdrop.filter = NEAREST;
		uBackdrop.mipFilter = MIPNONE;
		uBackdrop.wrap = CLAMP;
		uBackdropFrame.value[0] = x;
		uBackdropFrame.value[1] = y;
		uBackdropFrame.value[2] = 1 / backdrop.__textureWidth;
		uBackdropFrame.value[3] = 1 / backdrop.__textureHeight;
		#end
	}

	/**
		Sets the part of the target that has been drawn into before, from (x0, y0) to (x1, y1) in
		backdrop coordinates. Outside it, the shader draws the object as it is.
	**/
	public function setDrawn(x0:Float, y0:Float, x1:Float, y1:Float):Void
	{
		#if !macro
		uDrawn.value[0] = x0;
		uDrawn.value[1] = y0;
		uDrawn.value[2] = x1;
		uDrawn.value[3] = y1;
		#end
	}

	/**
		Prepares the shader for one draw: the blend mode, the alpha of the source, whether to skip fully
		transparent source texels, and for ALPHA the source's coverage, which is sampled with the same
		texture coordinates as the source. `mode` is one of the ids from
		`OpenGLRenderer.__blendGroupMode`.
	**/
	public function init(mode:Int, alpha:Float, discardTransparent:Bool, coverage:BitmapData):Void
	{
		#if !macro
		uMode.value[0] = mode;
		uAlpha.value[0] = alpha;
		uDiscardTransparent.value[0] = discardTransparent;
		uHasCoverage.value[0] = coverage != null;
		uCoverage.input = coverage;
		uCoverage.filter = NEAREST;
		uCoverage.mipFilter = MIPNONE;
		uCoverage.wrap = CLAMP;
		#end
	}
}
#end
