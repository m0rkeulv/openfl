package openfl.display._internal;

#if !flash
import openfl.display.Graphics;
import openfl.display.OpenGLRenderer;
import openfl.display._internal.DrawCommandReader;
#if (js && html5)
import openfl.display.BitmapData;
import openfl.display.CapsStyle;
import openfl.display.GradientType;
import openfl.display.JointStyle;
import openfl.display.LineScaleMode;
import openfl.display.SpreadMethod;
import openfl.geom.Matrix;
import js.Browser;
import js.html.CanvasElement;
import js.lib.Float32Array;
import js.lib.Uint8Array;
#end

/**
	OpenGLGraphics -- the MSAA vector-fill path.

	Sibling of `CairoGraphics` (native software FSAA) and `CanvasGraphics` (html5
	software FSAA). Renders a shape's fills on the GPU with **true MSAA** so
	abutting fills partition coverage exactly -- no background bleed (the
	Cairo/Canvas conflation artifact) and no ~N^2 cost.

	Pipeline (WebGL2, one multisampled framebuffer per shape). Each fill is drawn
	with **stencil-then-cover**, which fills an arbitrary path (concave, holes,
	self-intersecting) without CPU triangulation:
	  - stencil pass: draw an anchor-fan of the fill's flattened subpaths into the
	    stencil buffer with op=INVERT (even-odd; holes cancel);
	  - cover pass: draw a full-screen quad where stencil != 0, resetting the
	    stencil to 0, shading each pixel by the fill (solid / gradient / bitmap).
	Because the framebuffer is multisampled, coverage is per-sample, so interior
	seams resolve exactly and the silhouette gets clean AA in one resolve.

	Supported fills: solid colour, linear and radial gradients, and bitmap fills.
	Falls back to the software path for shader fills, thick line strokes, and
	non-zero winding. Curves are flattened; even-odd winding (OpenFL's Canvas
	default) is assumed. Gradients use sRGB interpolation and PAD/REPEAT/REFLECT
	spread; radial focal point is treated as concentric (focal ~0).

	Opt-in on html5 with `-D openfl_gpu_graphics` (dispatched from
	`CanvasGraphics.render`); it is compiled out when software rendering is forced
	(`openfl_force_sw_graphics` / `force_sw_graphics`), and if WebGL2 is
	unavailable at runtime it reports "not handled" so the software path is used.
	The same approach is reusable by native GL targets (item 4).
**/
@:access(openfl.display.Graphics)
@:access(openfl.display.BitmapData)
@:access(openfl.display.DisplayObject)
@SuppressWarnings("checkstyle:FieldDocComment")
class OpenGLGraphics
{
	/**
		MSAA sample count requested for the fill target. Clamped to the driver's
		GL_MAX_SAMPLES at render time. 2 is already coverage-clean for abutting
		solid fills; 4 gives smoother silhouettes.
	**/
	public static var samples:Int = 4;

	#if (js && html5)
	private static inline var MODE_SOLID = 0;
	private static inline var MODE_LINEAR = 1;
	private static inline var MODE_RADIAL = 2;
	private static inline var MODE_BITMAP = 3;

	private static var supported:Bool = true;
	private static var inited:Bool = false;
	private static var glCanvas:CanvasElement;
	private static var gl:Dynamic; // WebGL2RenderingContext
	private static var prog:Dynamic;
	private static var locPos:Int = -1;
	private static var uMode:Dynamic;
	private static var uColor:Dynamic;
	private static var uRamp:Dynamic;
	private static var uTex:Dynamic;
	private static var uMat:Dynamic;
	private static var uSpread:Dynamic;
	private static var uWH:Dynamic;
	private static var vbo:Dynamic;
	private static var rampTex:Dynamic;
	private static var msFBO:Dynamic;
	private static var msColor:Dynamic;
	private static var msDepthStencil:Dynamic;
	private static var fbW:Int = 0;
	private static var fbH:Int = 0;
	private static var fbS:Int = 0;

	// Per-render working state (main thread only, like DrawCommandReader).
	private static var _rt:Matrix;
	private static var _invA:Float; // inverse render transform (pixel -> shape-local)
	private static var _invB:Float;
	private static var _invC:Float;
	private static var _invD:Float;
	private static var _invTX:Float;
	private static var _invTY:Float;
	private static var _w:Float;
	private static var _h:Float;
	private static var _bx:Float; // bounds origin, subtracted from local coords (as playCommands does)
	private static var _by:Float;
	private static var _sub:Array<Array<Float>>;
	private static var _cur:Array<Float>;
	private static var _clx:Float;
	private static var _cly:Float;

	// Current fill descriptor.
	private static var _mode:Int = MODE_SOLID;
	private static var _r:Float = 0;
	private static var _g:Float = 0;
	private static var _b:Float = 0;
	private static var _a:Float = 0;
	private static var _spread:Int = 0;
	private static var _mat:Float32Array; // pixel -> gradient-local (mat3 col-major)

	// Current stroke (line) descriptor. Strokes are tessellated to fill geometry
	// and rendered on the GPU too, so this renderer stays GPU-only.
	private static var _hasStroke:Bool = false;
	private static var _shw:Float = 0; // half thickness, in pixels
	private static var _scaps:Int = 0; // 0 butt, 1 round, 2 square
	private static var _sjoints:Int = 0; // 0 bevel, 1 miter, 2 round
	private static var _smiter:Float = 3;
	private static var _slr:Float = 0;
	private static var _slg:Float = 0;
	private static var _slb:Float = 0;
	private static var _sla:Float = 0;
	// Collected stroke batches (rendered after all fills, so strokes sit on top).
	private static var _strokeBatches:Array<{verts:Array<Float>, r:Float, g:Float, b:Float, a:Float}>;

	private static final QUAD:Array<Float> = [-1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0];
	#end

	/**
		Whether this path can currently render `graphics`: solid-colour or
		gradient (linear/radial) or bitmap vector fills, no stroke, even-odd
		winding. Returns false for anything else so the caller uses software.
	**/
	public static function isCompatible(graphics:Graphics):Bool
	{
		#if (js && html5)
		if (graphics.__commands == null) return false;
		var hasAnyFill = false;
		var data = new DrawCommandReader(graphics.__commands);
		var ok = true;
		for (type in graphics.__commands.types)
		{
			switch (type)
			{
				case BEGIN_FILL, BEGIN_GRADIENT_FILL, BEGIN_BITMAP_FILL:
					hasAnyFill = true;
					data.skip(type);

				case END_FILL, MOVE_TO, LINE_TO, CURVE_TO, CUBIC_CURVE_TO, WINDING_EVEN_ODD, LINE_STYLE:
					// solid strokes are tessellated on the GPU; gradient/bitmap line
					// styles are separate commands (LINE_GRADIENT_STYLE / _BITMAP_STYLE)
					// and fall through to the default reject below.
					data.skip(type);

				default:
					// shader fills, gradient/bitmap strokes, DRAW_* primitives,
					// non-zero winding, overrides, unknown -> not handled.
					ok = false;
					data.skip(type);
			}
			if (!ok) break;
		}
		data.destroy();
		return ok && hasAnyFill;
		#else
		return false;
		#end
	}

	/**
		Render `graphics` via MSAA into `graphics.__canvas` (same contract as
		`CanvasGraphics.render`). Returns true if handled, false to fall back.
	**/
	public static function render(graphics:Graphics, renderer:OpenGLRenderer):Bool
	{
		#if (js && html5)
		if (!supported) return false;
		// scale9-grid shapes are left to the software path.
		if (graphics.__owner == null || graphics.__owner.__worldScale9Grid != null) return false;
		if (!isCompatible(graphics)) return false;

		// This is now the dispatch point (called from Context3DGraphics before the
		// software list), so do the same setup CanvasGraphics.render did.
		#if (openfl_disable_hdpi || openfl_disable_hdpi_graphics)
		var pixelRatio = 1;
		#else
		var pixelRatio = renderer.__pixelRatio;
		#end
		graphics.__update(renderer.__worldTransform, pixelRatio);

		// not dirty (or managed) -> keep the cached GPU bitmap, skip re-render.
		// Returns true so the software list does NOT run and clobber it.
		if (!graphics.__softwareDirty || graphics.__managed) return true;

		graphics.__bitmapScaleX = 1;
		graphics.__bitmapScaleY = 1;

		var width = graphics.__width;
		var height = graphics.__height;
		if (!graphics.__visible || graphics.__commands.length == 0 || graphics.__bounds == null || width < 1 || height < 1)
		{
			graphics.__canvas = null;
			graphics.__context = null;
			graphics.__bitmap = null;
			graphics.__softwareDirty = false;
			graphics.__dirty = false;
			return true; // nothing to draw, but this graphic is ours
		}
		if (!initGL()) return false;
		if (!ensureTarget(width, height)) return false;

		_rt = graphics.__renderTransform;
		// __renderTransform is scale-only; the bounds origin is applied by
		// subtracting bounds.x/y from every local coord (as CanvasGraphics'
		// playCommands does). Keep it here for the geometry + inverse.
		_bx = (graphics.__bounds != null) ? graphics.__bounds.x : 0;
		_by = (graphics.__bounds != null) ? graphics.__bounds.y : 0;
		// inverse render transform for gradient/bitmap coords. pixel = _rt *
		// (local - bounds), so pixel -> local adds bounds back into the
		// translation (below).
		var det = _rt.a * _rt.d - _rt.b * _rt.c;
		if (det == 0) return false;
		var idet = 1.0 / det;
		_invA = _rt.d * idet;
		_invB = -_rt.b * idet;
		_invC = -_rt.c * idet;
		_invD = _rt.a * idet;
		_invTX = -(_invA * _rt.tx + _invC * _rt.ty) + _bx;
		_invTY = -(_invB * _rt.tx + _invD * _rt.ty) + _by;
		_w = width;
		_h = height;
		_sub = [];
		_cur = null;
		_hasStroke = false;
		_strokeBatches = [];

		gl.bindFramebuffer(gl.FRAMEBUFFER, msFBO);
		gl.viewport(0, 0, width, height);
		gl.disable(gl.DEPTH_TEST);
		gl.enable(gl.STENCIL_TEST);
		gl.enable(gl.BLEND);
		gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA); // premultiplied over
		gl.clearColor(0, 0, 0, 0);
		gl.clearStencil(0);
		gl.clear(gl.COLOR_BUFFER_BIT | gl.STENCIL_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

		gl.useProgram(prog);
		gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
		gl.enableVertexAttribArray(locPos);
		gl.vertexAttribPointer(locPos, 2, gl.FLOAT, false, 0, 0);
		gl.uniform2f(uWH, width, height);

		var data = new DrawCommandReader(graphics.__commands);
		var hasFill = false;

		for (type in graphics.__commands.types)
		{
			switch (type)
			{
				case BEGIN_FILL:
					if (hasFill) flushFill();
					var c = data.readBeginFill();
					_mode = MODE_SOLID;
					_r = ((c.color >> 16) & 0xFF) / 255.0;
					_g = ((c.color >> 8) & 0xFF) / 255.0;
					_b = (c.color & 0xFF) / 255.0;
					_a = c.alpha;
					hasFill = true;
					collectStrokes();
					_sub = [];
					_cur = null;

				case BEGIN_GRADIENT_FILL:
					if (hasFill) flushFill();
					var c = data.readBeginGradientFill();
					setupGradient(c.type, c.colors, c.alphas, c.ratios, c.matrix, c.spreadMethod);
					hasFill = true;
					collectStrokes();
					_sub = [];
					_cur = null;

				case BEGIN_BITMAP_FILL:
					if (hasFill) flushFill();
					var c = data.readBeginBitmapFill();
					if (!setupBitmap(c.bitmap, c.matrix, c.repeat, c.smooth))
					{
						// couldn't prepare texture -> abandon MSAA, fall back
						data.destroy();
						return false;
					}
					hasFill = true;
					collectStrokes();
					_sub = [];
					_cur = null;

				case END_FILL:
					data.skip(type);
					if (hasFill) flushFill();
					hasFill = false;
					collectStrokes();
					_sub = [];
					_cur = null;

				case MOVE_TO:
					var c = data.readMoveTo();
					emitMove(c.x, c.y);

				case LINE_TO:
					var c = data.readLineTo();
					emitLine(c.x, c.y);

				case CURVE_TO:
					var c = data.readCurveTo();
					emitQuad(c.controlX, c.controlY, c.anchorX, c.anchorY);

				case CUBIC_CURVE_TO:
					var c = data.readCubicCurveTo();
					emitCubic(c.controlX1, c.controlY1, c.controlX2, c.controlY2, c.anchorX, c.anchorY);

				case LINE_STYLE:
					var c = data.readLineStyle();
					if (c.thickness == null)
					{
						_hasStroke = false;
					}
					else
					{
						_hasStroke = true;
						var sc = (c.scaleMode == LineScaleMode.NONE) ? 1.0 : Math.sqrt(Math.abs(_rt.a * _rt.d - _rt.b * _rt.c));
						var pxw = c.thickness * sc;
						if (pxw < 1) pxw = 1; // hairline / min 1px
						_shw = pxw / 2;
						_slr = ((c.color >> 16) & 0xFF) / 255.0;
						_slg = ((c.color >> 8) & 0xFF) / 255.0;
						_slb = (c.color & 0xFF) / 255.0;
						_sla = c.alpha;
						_scaps = switch (c.caps)
						{
							case ROUND: 1;
							case SQUARE: 2;
							default: 0; // NONE = butt
						}
						_sjoints = switch (c.joints)
						{
							case MITER: 1;
							case ROUND: 2;
							default: 0; // BEVEL
						}
						_smiter = (c.miterLimit != null && c.miterLimit > 1) ? c.miterLimit : 3;
					}

				default:
					data.skip(type);
			}
		}
		if (hasFill) flushFill();
		collectStrokes();
		renderStrokeBatches();
		data.destroy();

		gl.bindFramebuffer(gl.READ_FRAMEBUFFER, msFBO);
		gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, null);
		gl.clearColor(0, 0, 0, 0);
		gl.clear(gl.COLOR_BUFFER_BIT);
		gl.blitFramebuffer(0, 0, width, height, 0, 0, width, height, gl.COLOR_BUFFER_BIT, gl.NEAREST);
		gl.bindFramebuffer(gl.FRAMEBUFFER, null);

		if (graphics.__canvas == null)
		{
			graphics.__canvas = cast Browser.document.createElement("canvas");
			graphics.__context = graphics.__canvas.getContext("2d");
		}
		if (graphics.__canvas.width != width || graphics.__canvas.height != height)
		{
			graphics.__canvas.width = width;
			graphics.__canvas.height = height;
		}
		var ctx = graphics.__context;
		ctx.setTransform(1, 0, 0, 1, 0, 0);
		ctx.clearRect(0, 0, width, height);
		ctx.drawImage(glCanvas, 0, 0, width, height, 0, 0, width, height);

		if (graphics.__bitmap == null || graphics.__bitmap.width != width || graphics.__bitmap.height != height)
		{
			graphics.__bitmap = BitmapData.fromCanvas(graphics.__canvas);
		}
		else
		{
			graphics.__bitmap.image.version++;
		}

		graphics.__softwareDirty = false;
		graphics.__dirty = false;
		return true;
		#else
		return false;
		#end
	}

	#if (js && html5)
	// Compose pixel->gradient-local: apply inverse render (pixel->shape) then
	// inverse of `matrix` (shape->gradient-local). Stored as a mat3 (col-major).
	private static function setupGradient(type:GradientType, colors:Array<Int>, alphas:Array<Float>, ratios:Array<Int>, matrix:Matrix,
			spread:SpreadMethod):Void
	{
		_mode = (type == RADIAL) ? MODE_RADIAL : MODE_LINEAR;
		_spread = switch (spread)
		{
			case REFLECT: 1;
			case REPEAT: 2;
			default: 0; // PAD
		}

		// inverse of gradient matrix (shape-local -> gradient-local)
		var ga = 1.0, gb = 0.0, gc = 0.0, gd = 1.0, gtx = 0.0, gty = 0.0;
		if (matrix != null)
		{
			var det = matrix.a * matrix.d - matrix.b * matrix.c;
			if (det != 0)
			{
				var id = 1.0 / det;
				ga = matrix.d * id;
				gb = -matrix.b * id;
				gc = -matrix.c * id;
				gd = matrix.a * id;
				gtx = -(ga * matrix.tx + gc * matrix.ty);
				gty = -(gb * matrix.tx + gd * matrix.ty);
			}
		}

		// compose gInv (after) with invRender (first): C = gInv ∘ invRender
		var A = ga * _invA + gc * _invB;
		var C = ga * _invC + gc * _invD;
		var TX = ga * _invTX + gc * _invTY + gtx;
		var B = gb * _invA + gd * _invB;
		var D = gb * _invC + gd * _invD;
		var TY = gb * _invTX + gd * _invTY + gty;
		_mat = new Float32Array(cast [A, B, 0.0, C, D, 0.0, TX, TY, 1.0]);

		buildRamp(colors, alphas, ratios);
	}

	// Build a 256x1 straight-RGBA ramp from the colour stops and upload it.
	private static function buildRamp(colors:Array<Int>, alphas:Array<Float>, ratios:Array<Int>):Void
	{
		var px = new Uint8Array(256 * 4);
		var n = colors.length;
		var si = 0;
		for (i in 0...256)
		{
			var t = i / 255.0;
			// advance to the stop interval containing t
			while (si < n - 1 && (ratios[si + 1] / 255.0) < t)
				si++;
			var r0 = ratios[si] / 255.0;
			var c0 = colors[si], a0 = alphas[si];
			var r:Float, g:Float, b:Float, a:Float;
			if (si >= n - 1 || t <= r0)
			{
				r = (c0 >> 16) & 0xFF;
				g = (c0 >> 8) & 0xFF;
				b = c0 & 0xFF;
				a = a0 * 255;
			}
			else
			{
				var r1 = ratios[si + 1] / 255.0;
				var c1 = colors[si + 1], a1 = alphas[si + 1];
				var f = (r1 > r0) ? (t - r0) / (r1 - r0) : 0.0;
				r = ((c0 >> 16) & 0xFF) + (((c1 >> 16) & 0xFF) - ((c0 >> 16) & 0xFF)) * f;
				g = ((c0 >> 8) & 0xFF) + (((c1 >> 8) & 0xFF) - ((c0 >> 8) & 0xFF)) * f;
				b = (c0 & 0xFF) + ((c1 & 0xFF) - (c0 & 0xFF)) * f;
				a = (a0 + (a1 - a0) * f) * 255;
			}
			var o = i * 4;
			px[o] = Std.int(r);
			px[o + 1] = Std.int(g);
			px[o + 2] = Std.int(b);
			px[o + 3] = Std.int(a);
		}
		gl.bindTexture(gl.TEXTURE_2D, rampTex);
		gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 256, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, px);
	}

	// Prepare a bitmap fill (texture + pixel->uv matrix). Returns false if the
	// bitmap can't be turned into a texture (caller falls back to software).
	private static function setupBitmap(bitmap:BitmapData, matrix:Matrix, repeat:Bool, smooth:Bool):Bool
	{
		if (bitmap == null || bitmap.image == null) return false;
		var el:Dynamic = null;
		try
		{
			lime._internal.graphics.ImageCanvasUtil.convertToCanvas(bitmap.image);
			el = bitmap.image.src; // backing canvas/image in the html5 backend
		}
		catch (e:Dynamic) {}
		if (el == null) return false;

		_mode = MODE_BITMAP;
		_spread = 0;

		var tw = bitmap.width, th = bitmap.height;

		// inverse of bitmap matrix (shape-local -> bitmap pixels), then /size -> uv
		var ba = 1.0, bb = 0.0, bc = 0.0, bd = 1.0, btx = 0.0, bty = 0.0;
		if (matrix != null)
		{
			var det = matrix.a * matrix.d - matrix.b * matrix.c;
			if (det != 0)
			{
				var id = 1.0 / det;
				ba = matrix.d * id;
				bb = -matrix.b * id;
				bc = -matrix.c * id;
				bd = matrix.a * id;
				btx = -(ba * matrix.tx + bc * matrix.ty);
				bty = -(bb * matrix.tx + bd * matrix.ty);
			}
		}
		// compose bInv ∘ invRender, then scale rows by 1/size for uv
		var A = (ba * _invA + bc * _invB) / tw;
		var C = (ba * _invC + bc * _invD) / tw;
		var TX = (ba * _invTX + bc * _invTY + btx) / tw;
		var B = (bb * _invA + bd * _invB) / th;
		var D = (bb * _invC + bd * _invD) / th;
		var TY = (bb * _invTX + bd * _invTY + bty) / th;
		_mat = new Float32Array(cast [A, B, 0.0, C, D, 0.0, TX, TY, 1.0]);

		gl.activeTexture(gl.TEXTURE1);
		gl.bindTexture(gl.TEXTURE_2D, getBitmapTexture(bitmap, el));
		var wrap = repeat ? gl.REPEAT : gl.CLAMP_TO_EDGE;
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
		var filt = smooth ? gl.LINEAR : gl.NEAREST;
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filt);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filt);
		return true;
	}

	// Upload/reuse a GL texture for a BitmapData, keyed on the object, refreshed
	// when its image version changes.
	private static function getBitmapTexture(bitmap:BitmapData, el:Dynamic):Dynamic
	{
		var ver = -1;
		try
		{
			ver = bitmap.image.version;
		}
		catch (e:Dynamic) {}
		var tex = untyped bitmap.__oglTex;
		if (tex != null && untyped bitmap.__oglTexVer == ver) return tex;
		if (tex == null)
		{
			tex = gl.createTexture();
			untyped bitmap.__oglTex = tex;
		}
		gl.bindTexture(gl.TEXTURE_2D, tex);
		gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
		gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, el);
		untyped bitmap.__oglTexVer = ver;
		return tex;
	}

	private static function initGL():Bool
	{
		if (inited) return gl != null;
		inited = true;
		try
		{
			glCanvas = cast Browser.document.createElement("canvas");
			gl = untyped glCanvas.getContext("webgl2", {alpha: true, depth: false, stencil: true, antialias: false, premultipliedAlpha: true});
			if (gl == null)
			{
				supported = false;
				return false;
			}

			var vs = compile(gl.VERTEX_SHADER,
				"#version 300 es\nin vec2 p;\nuniform vec2 uWH;\nout vec2 vPixel;\nvoid main(){ vPixel = vec2((p.x+1.0)*0.5*uWH.x, (1.0-p.y)*0.5*uWH.y); gl_Position = vec4(p, 0.0, 1.0); }");
			var fs = compile(gl.FRAGMENT_SHADER, [
				"#version 300 es",
				"precision highp float;",
				"uniform int uMode;",
				"uniform vec4 uColor;",
				"uniform sampler2D uRamp;",
				"uniform sampler2D uTex;",
				"uniform mat3 uMat;",
				"uniform int uSpread;",
				"in vec2 vPixel;",
				"out vec4 o;",
				"float spread(float t){",
				"  if(uSpread==0) return clamp(t,0.0,1.0);",
				"  if(uSpread==2) return fract(t);",
				"  float f=fract(t*0.5)*2.0; return f>1.0?2.0-f:f;",
				"}",
				"void main(){",
				"  vec4 c;",
				"  if(uMode==0){ c=uColor; }",
				"  else { vec3 g=uMat*vec3(vPixel,1.0);",
				"    if(uMode==1){ c=texture(uRamp, vec2(spread((g.x+819.2)/1638.4),0.5)); }",
				"    else if(uMode==2){ c=texture(uRamp, vec2(spread(length(g.xy)/819.2),0.5)); }",
				"    else { c=texture(uTex, g.xy); } }",
				"  o=vec4(c.rgb*c.a, c.a);",
				"}"
			].join("\n"));
			prog = gl.createProgram();
			gl.attachShader(prog, vs);
			gl.attachShader(prog, fs);
			gl.linkProgram(prog);
			if (!gl.getProgramParameter(prog, gl.LINK_STATUS))
			{
				supported = false;
				return false;
			}
			locPos = gl.getAttribLocation(prog, "p");
			uMode = gl.getUniformLocation(prog, "uMode");
			uColor = gl.getUniformLocation(prog, "uColor");
			uRamp = gl.getUniformLocation(prog, "uRamp");
			uTex = gl.getUniformLocation(prog, "uTex");
			uMat = gl.getUniformLocation(prog, "uMat");
			uSpread = gl.getUniformLocation(prog, "uSpread");
			uWH = gl.getUniformLocation(prog, "uWH");
			vbo = gl.createBuffer();

			rampTex = gl.createTexture();
			gl.bindTexture(gl.TEXTURE_2D, rampTex);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

			gl.useProgram(prog);
			gl.uniform1i(uRamp, 0);
			gl.uniform1i(uTex, 1);
			return true;
		}
		catch (e:Dynamic)
		{
			supported = false;
			return false;
		}
	}

	private static function compile(type:Int, src:String):Dynamic
	{
		var s = gl.createShader(type);
		gl.shaderSource(s, src);
		gl.compileShader(s);
		if (!gl.getShaderParameter(s, gl.COMPILE_STATUS))
		{
			throw "OpenGLGraphics shader compile failed: " + gl.getShaderInfoLog(s);
		}
		return s;
	}

	private static function ensureTarget(w:Int, h:Int):Bool
	{
		var s = samples;
		var maxS:Int = gl.getParameter(gl.MAX_SAMPLES);
		if (s > maxS) s = maxS;
		if (s < 1) s = 1;

		if (msFBO != null && fbW == w && fbH == h && fbS == s) return true;

		if (msFBO != null)
		{
			gl.deleteFramebuffer(msFBO);
			gl.deleteRenderbuffer(msColor);
			gl.deleteRenderbuffer(msDepthStencil);
		}

		msColor = gl.createRenderbuffer();
		gl.bindRenderbuffer(gl.RENDERBUFFER, msColor);
		gl.renderbufferStorageMultisample(gl.RENDERBUFFER, s, gl.RGBA8, w, h);

		msDepthStencil = gl.createRenderbuffer();
		gl.bindRenderbuffer(gl.RENDERBUFFER, msDepthStencil);
		gl.renderbufferStorageMultisample(gl.RENDERBUFFER, s, gl.DEPTH24_STENCIL8, w, h);

		msFBO = gl.createFramebuffer();
		gl.bindFramebuffer(gl.FRAMEBUFFER, msFBO);
		gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, msColor);
		gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, msDepthStencil);

		if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE)
		{
			supported = false;
			return false;
		}

		glCanvas.width = w;
		glCanvas.height = h;
		fbW = w;
		fbH = h;
		fbS = s;
		return true;
	}

	private static inline function pushClip(lx:Float, ly:Float):Void
	{
		var x = lx - _bx, y = ly - _by;
		// store PIXEL coords (shared by fills and stroke tessellation); the
		// fill/stroke passes convert to clip space at emit time.
		_cur.push(_rt.a * x + _rt.c * y + _rt.tx);
		_cur.push(_rt.b * x + _rt.d * y + _rt.ty);
	}

	private static inline function clipX(px:Float):Float
	{
		return px / _w * 2 - 1;
	}

	private static inline function clipY(py:Float):Float
	{
		return 1 - py / _h * 2;
	}

	private static inline function segsFor(ax:Float, ay:Float, bx:Float, by:Float):Int
	{
		var pax = _rt.a * (ax - _bx) + _rt.c * (ay - _by) + _rt.tx;
		var pay = _rt.b * (ax - _bx) + _rt.d * (ay - _by) + _rt.ty;
		var pbx = _rt.a * (bx - _bx) + _rt.c * (by - _by) + _rt.tx;
		var pby = _rt.b * (bx - _bx) + _rt.d * (by - _by) + _rt.ty;
		var dx = pbx - pax, dy = pby - pay;
		var n = Math.ceil(Math.sqrt(dx * dx + dy * dy) / 4);
		if (n < 4) n = 4;
		if (n > 64) n = 64;
		return n;
	}

	private static function emitMove(lx:Float, ly:Float):Void
	{
		_cur = [];
		_sub.push(_cur);
		pushClip(lx, ly);
		_clx = lx;
		_cly = ly;
	}

	private static function emitLine(lx:Float, ly:Float):Void
	{
		if (_cur == null) emitMove(lx, ly);
		else
		{
			pushClip(lx, ly);
			_clx = lx;
			_cly = ly;
		}
	}

	private static function emitQuad(cx:Float, cy:Float, ax:Float, ay:Float):Void
	{
		if (_cur == null) emitMove(_clx, _cly);
		var n = segsFor(_clx, _cly, ax, ay);
		var x0 = _clx, y0 = _cly;
		var i = 1;
		while (i <= n)
		{
			var t = i / n, mt = 1 - t;
			pushClip(mt * mt * x0 + 2 * mt * t * cx + t * t * ax, mt * mt * y0 + 2 * mt * t * cy + t * t * ay);
			i++;
		}
		_clx = ax;
		_cly = ay;
	}

	private static function emitCubic(c1x:Float, c1y:Float, c2x:Float, c2y:Float, ax:Float, ay:Float):Void
	{
		if (_cur == null) emitMove(_clx, _cly);
		var n = segsFor(_clx, _cly, ax, ay);
		var x0 = _clx, y0 = _cly;
		var i = 1;
		while (i <= n)
		{
			var t = i / n, mt = 1 - t;
			var b0 = mt * mt * mt, b1 = 3 * mt * mt * t, b2 = 3 * mt * t * t, b3 = t * t * t;
			pushClip(b0 * x0 + b1 * c1x + b2 * c2x + b3 * ax, b0 * y0 + b1 * c1y + b2 * c2y + b3 * ay);
			i++;
		}
		_clx = ax;
		_cly = ay;
	}

	// Render one fill: stencil pass (even-odd INVERT) then cover pass.
	private static function flushFill():Void
	{
		if (_sub == null || _sub.length == 0) return;

		var verts = new Array<Float>();
		for (sp in _sub)
		{
			var n = sp.length >> 1;
			if (n < 3) continue;
			var ax = clipX(sp[0]), ay = clipY(sp[1]);
			var i = 1;
			while (i < n - 1)
			{
				verts.push(ax);
				verts.push(ay);
				verts.push(clipX(sp[i * 2]));
				verts.push(clipY(sp[i * 2 + 1]));
				verts.push(clipX(sp[i * 2 + 2]));
				verts.push(clipY(sp[i * 2 + 3]));
				i++;
			}
		}
		if (verts.length == 0) return;

		// stencil pass
		gl.colorMask(false, false, false, false);
		gl.stencilMask(0xFF);
		gl.stencilFunc(gl.ALWAYS, 0, 0xFF);
		gl.stencilOp(gl.KEEP, gl.KEEP, gl.INVERT);
		gl.uniform1i(uMode, MODE_SOLID);
		gl.uniform4f(uColor, 0, 0, 0, 0);
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(cast verts), gl.STREAM_DRAW);
		gl.drawArrays(gl.TRIANGLES, 0, Std.int(verts.length / 2));

		// cover pass
		gl.colorMask(true, true, true, true);
		gl.stencilFunc(gl.NOTEQUAL, 0, 0xFF);
		gl.stencilOp(gl.KEEP, gl.KEEP, gl.ZERO);
		gl.uniform1i(uMode, _mode);
		if (_mode == MODE_SOLID)
		{
			gl.uniform4f(uColor, _r, _g, _b, _a);
		}
		else
		{
			gl.uniformMatrix3fv(uMat, false, _mat);
			gl.uniform1i(uSpread, _spread);
		}
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(cast QUAD), gl.STREAM_DRAW);
		gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
		// NOTE: does not reset _sub -- the caller does, after collectStrokes(),
		// so the same path can be both filled and stroked.
	}

	// ---- strokes: tessellated to fill geometry, rendered on the GPU too ----

	// Build stroke triangles for every subpath currently in _sub (under the
	// active line style) into a batch, drawn after all fills so strokes sit on
	// top. NOTE: a line-style change mid-path applies the final style to the
	// whole group (rare); set lineStyle before the path for exact results.
	private static function collectStrokes():Void
	{
		if (!_hasStroke || _sub == null || _sub.length == 0) return;
		var out = new Array<Float>();
		for (sp in _sub)
			strokeSubpath(sp, out);
		if (out.length > 0) _strokeBatches.push({verts: out, r: _slr, g: _slg, b: _slb, a: _sla});
	}

	private static function renderStrokeBatches():Void
	{
		if (_strokeBatches == null) return;
		for (b in _strokeBatches)
			flushStrokeBatch(b.verts, b.r, b.g, b.b, b.a);
	}

	// Union-coverage stencil (stroke pieces overlap at joints/caps) then cover,
	// so overlaps and translucent strokes stay single-coverage.
	private static function flushStrokeBatch(verts:Array<Float>, r:Float, g:Float, b:Float, a:Float):Void
	{
		if (verts.length == 0) return;

		gl.colorMask(false, false, false, false);
		gl.stencilMask(0xFF);
		gl.stencilFunc(gl.ALWAYS, 1, 0xFF);
		gl.stencilOp(gl.KEEP, gl.KEEP, gl.REPLACE); // union: any covered sample -> 1
		gl.uniform1i(uMode, MODE_SOLID);
		gl.uniform4f(uColor, 0, 0, 0, 0);
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(cast verts), gl.STREAM_DRAW);
		gl.drawArrays(gl.TRIANGLES, 0, Std.int(verts.length / 2));

		gl.colorMask(true, true, true, true);
		gl.stencilFunc(gl.NOTEQUAL, 0, 0xFF);
		gl.stencilOp(gl.KEEP, gl.KEEP, gl.ZERO);
		gl.uniform1i(uMode, MODE_SOLID);
		gl.uniform4f(uColor, r, g, b, a);
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(cast QUAD), gl.STREAM_DRAW);
		gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
	}

	private static inline function sTri(out:Array<Float>, ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float):Void
	{
		out.push(clipX(ax));
		out.push(clipY(ay));
		out.push(clipX(bx));
		out.push(clipY(by));
		out.push(clipX(cx));
		out.push(clipY(cy));
	}

	private static function sDisc(out:Array<Float>, cx:Float, cy:Float, r:Float):Void
	{
		var seg = 16, i = 0;
		while (i < seg)
		{
			var a0 = i / seg * 2 * Math.PI, a1 = (i + 1) / seg * 2 * Math.PI;
			sTri(out, cx, cy, cx + Math.cos(a0) * r, cy + Math.sin(a0) * r, cx + Math.cos(a1) * r, cy + Math.sin(a1) * r);
			i++;
		}
	}

	// Tessellate one subpath (pixel coords in sp) into stroke triangles (clip in out).
	private static function strokeSubpath(sp:Array<Float>, out:Array<Float>):Void
	{
		var hw = _shw;
		var xs = new Array<Float>(), ys = new Array<Float>();
		var m = sp.length >> 1, k = 0;
		while (k < m)
		{
			var px = sp[k * 2], py = sp[k * 2 + 1];
			if (xs.length == 0 || Math.abs(px - xs[xs.length - 1]) > 0.001 || Math.abs(py - ys[ys.length - 1]) > 0.001)
			{
				xs.push(px);
				ys.push(py);
			}
			k++;
		}
		var n = xs.length;
		if (n < 2)
		{
			if (n == 1 && _scaps == 1) sDisc(out, xs[0], ys[0], hw);
			return;
		}

		var closed = (Math.abs(xs[0] - xs[n - 1]) < 0.01 && Math.abs(ys[0] - ys[n - 1]) < 0.01);
		if (closed)
		{
			xs.pop();
			ys.pop();
			n--;
			if (n < 2) return;
		}

		var segCount = closed ? n : n - 1, i = 0;
		while (i < segCount)
		{
			var j = (i + 1) % n;
			sSeg(out, xs[i], ys[i], xs[j], ys[j], hw);
			i++;
		}

		var jStart = closed ? 0 : 1, jEnd = closed ? n : n - 1;
		i = jStart;
		while (i < jEnd)
		{
			var p = (i - 1 + n) % n, q = (i + 1) % n;
			sJoint(out, xs[p], ys[p], xs[i], ys[i], xs[q], ys[q], hw);
			i++;
		}

		if (!closed)
		{
			sCap(out, xs[0], ys[0], xs[1], ys[1], hw);
			sCap(out, xs[n - 1], ys[n - 1], xs[n - 2], ys[n - 2], hw);
		}
	}

	private static function sSeg(out:Array<Float>, ax:Float, ay:Float, bx:Float, by:Float, hw:Float):Void
	{
		var dx = bx - ax, dy = by - ay;
		var len = Math.sqrt(dx * dx + dy * dy);
		if (len < 1e-6) return;
		var nx = -dy / len * hw, ny = dx / len * hw;
		sTri(out, ax + nx, ay + ny, ax - nx, ay - ny, bx + nx, by + ny);
		sTri(out, bx + nx, by + ny, ax - nx, ay - ny, bx - nx, by - ny);
	}

	private static function sJoint(out:Array<Float>, px:Float, py:Float, vx:Float, vy:Float, qx:Float, qy:Float, hw:Float):Void
	{
		var d0x = vx - px, d0y = vy - py;
		var l0 = Math.sqrt(d0x * d0x + d0y * d0y);
		var d1x = qx - vx, d1y = qy - vy;
		var l1 = Math.sqrt(d1x * d1x + d1y * d1y);
		if (l0 < 1e-6 || l1 < 1e-6) return;
		d0x /= l0;
		d0y /= l0;
		d1x /= l1;
		d1y /= l1;
		var n0x = -d0y * hw, n0y = d0x * hw;
		var n1x = -d1y * hw, n1y = d1x * hw;

		if (_sjoints == 2)
		{
			sDisc(out, vx, vy, hw); // round joint
			return;
		}

		// bevel both sides (inner overlaps segments harmlessly with union stencil)
		sTri(out, vx, vy, vx + n0x, vy + n0y, vx + n1x, vy + n1y);
		sTri(out, vx, vy, vx - n0x, vy - n0y, vx - n1x, vy - n1y);

		if (_sjoints == 1)
		{
			// miter: extend the outer corner to the apex within the limit
			var mx = n0x + n1x, my = n0y + n1y;
			var ml = Math.sqrt(mx * mx + my * my);
			if (ml < 1e-4) return;
			var mnx = mx / ml, mny = my / ml;
			var cosA = (n0x * mnx + n0y * mny) / hw;
			if (cosA < 1e-3) return;
			var ratio = 1 / cosA;
			if (ratio > _smiter) return;
			var apex = hw * ratio;
			var cross = d0x * d1y - d0y * d1x;
			var s = (cross > 0) ? -1.0 : 1.0;
			var apx = vx + s * mnx * apex, apy = vy + s * mny * apex;
			sTri(out, vx, vy, vx + s * n0x, vy + s * n0y, apx, apy);
			sTri(out, vx, vy, apx, apy, vx + s * n1x, vy + s * n1y);
		}
	}

	// Cap at endpoint E; (tx,ty) is the neighbouring point, so E-toward is outward.
	private static function sCap(out:Array<Float>, ex:Float, ey:Float, tx:Float, ty:Float, hw:Float):Void
	{
		if (_scaps == 0) return; // butt
		var dx = ex - tx, dy = ey - ty;
		var len = Math.sqrt(dx * dx + dy * dy);
		if (len < 1e-6) return;
		dx /= len;
		dy /= len;
		if (_scaps == 1)
		{
			sDisc(out, ex, ey, hw); // round cap ~ disc at endpoint
			return;
		}
		// square: extend by hw along the outward direction
		var nx = -dy * hw, ny = dx * hw;
		var gx = ex + dx * hw, gy = ey + dy * hw;
		sTri(out, ex + nx, ey + ny, ex - nx, ey - ny, gx + nx, gy + ny);
		sTri(out, gx + nx, gy + ny, ex - nx, ey - ny, gx - nx, gy - ny);
	}
	#end
}
#end
