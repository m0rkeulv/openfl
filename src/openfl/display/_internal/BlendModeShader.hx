package openfl.display._internal;

#if !flash
import openfl.display.BitmapData;
import openfl.filters.BitmapFilterShader;

/**
	Composes a group scratch buffer (the object, premultiplied) onto a copy of the backdrop with
	the Flash blend formulas: the blend works on straight colour and is mixed in by the
	object's alpha. Mode indexes as in OpenGLRenderer.__blendGroupMode.
**/
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

		vec3 hardLight(vec3 base, vec3 control) {
			return mix(2.0 * base * control, 1.0 - 2.0 * (1.0 - base) * (1.0 - control), step(0.5, control));
		}

		void main(void) {
			vec4 src = texture2D(openfl_Texture, openfl_TextureCoordv);
			vec4 dst = texture2D(uBackdrop, vec2(openfl_TextureCoordv.x, openfl_TextureCoordv.y * uBackdropFlip.x + uBackdropFlip.y));

			float srcAlpha = src.a;
			float dstAlpha = dst.a;

			vec3 s = srcAlpha > 0.0 ? src.rgb / srcAlpha : vec3(0.0);
			vec3 d = dstAlpha > 0.0 ? dst.rgb / dstAlpha : vec3(0.0);

			vec3 blend;

			if (uMode == 0) blend = abs(d - s); 			// DIFFERENCE
			else if (uMode == 2) blend = min(d, s); 		// DARKEN
			else if (uMode == 3) blend = max(d, s); 		// LIGHTEN
			else if (uMode == 4) blend = hardLight(d, s); 	// HARDLIGHT
			else blend = hardLight(s, d); 					// OVERLAY

			// separable blend over a possibly transparent backdrop (PDF compositing)
			vec3 sourceOnly = source.rgb * (1.0 - backdropAlpha);
			vec3 backdropOnly = backdrop.rgb * (1.0 - sourceAlpha);
			vec3 weightedBlend = sourceAlpha * backdropAlpha * blended;
			float coverage = sourceAlpha + backdropAlpha - sourceAlpha * backdropAlpha;

			gl_FragColor = vec4(sourceOnly + backdropOnly + weightedBlend, coverage);
		}")
	public function new()
	{
		super();

		#if !macro
		uBackdropFlip.value = [1, 0];
		uMode.value = [0];
		#end
	}

	/**
		The backdrop copy, how its rows map to the group's (scale and offset on the texture
		y: the window framebuffer is copied bottom-up) and the mode. Like the filter shaders,
		the uniforms are only touched under `#if !macro`: the fields come from ShaderMacro,
		which does not run when the class is typed in a macro context.
	**/
	public function init(backdrop:BitmapData, mode:Int, flipScale:Float, flipOffset:Float):Void
	{
		#if !macro
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
