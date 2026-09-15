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
			float sa = src.a;
			float da = dst.a;
			vec3 s = sa > 0.0 ? src.rgb / sa : vec3(0.0);
			vec3 d = da > 0.0 ? dst.rgb / da : vec3(0.0);
			vec3 b;
			if (uMode == 0) b = abs(d - s);
			else if (uMode == 2) b = min(d, s);
			else if (uMode == 3) b = max(d, s);
			else if (uMode == 4) b = hardLight(d, s);
			else b = hardLight(s, d);

			// separable blend over a possibly transparent backdrop (PDF compositing)
			gl_FragColor = vec4(src.rgb * (1.0 - da) + dst.rgb * (1.0 - sa) + sa * da * b, sa + da - sa * da);
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
