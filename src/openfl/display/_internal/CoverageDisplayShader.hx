package openfl.display._internal;

#if !flash
import openfl.display.DisplayObjectShader;

/**
	The display shader for a texture that stands for a vector shape or a group when the
	blend mode is ALPHA. Flash applies ALPHA only to the pixels an object covers: the
	empty parts of a shape's bounding box leave the backdrop alone, while a Bitmap's
	transparent pixels do cut it (a bitmap covers its whole rectangle). A texture of a
	shape carries alpha 0 where nothing was drawn, so those texels are discarded here
	instead of multiplying the backdrop by 0; the fixed-function factors then only touch
	the covered pixels.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class CoverageDisplayShader extends DisplayObjectShader
{
	@:glFragmentSource("#pragma header

		void main(void) {

			vec4 color = texture2D (openfl_Texture, openfl_TextureCoordv);

			if (color.a == 0.0) {

				discard;

			} else if (openfl_HasColorTransform) {

				color = vec4 (color.rgb / color.a, color.a);

				mat4 colorMultiplier = mat4 (0);
				colorMultiplier[0][0] = openfl_ColorMultiplierv.x;
				colorMultiplier[1][1] = openfl_ColorMultiplierv.y;
				colorMultiplier[2][2] = openfl_ColorMultiplierv.z;
				colorMultiplier[3][3] = 1.0;

				color = clamp (openfl_ColorOffsetv + (color * colorMultiplier), 0.0, 1.0);

				gl_FragColor = vec4 (color.rgb * color.a * openfl_Alphav, color.a * openfl_Alphav);

			} else {

				gl_FragColor = color * openfl_Alphav;

			}

		}")
	public function new()
	{
		super();
	}
}
#end
