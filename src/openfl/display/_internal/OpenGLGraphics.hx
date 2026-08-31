package openfl.display._internal;

#if !flash
import openfl.display.Graphics;
import openfl.display._internal.DrawCommandReader;
#if (js && html5)
import openfl.display.BitmapData;
import openfl.display.CanvasRenderer;
import openfl.geom.Matrix;
import js.Browser;
import js.html.CanvasElement;
import js.lib.Float32Array;
#end

/**
	OpenGLGraphics -- the MSAA vector-fill path.

	Sibling of `CairoGraphics` (native software FSAA) and `CanvasGraphics` (html5
	software FSAA). Where those emulate coverage-correct anti-aliasing by
	supersampling and downsampling, this renders a shape's solid fills on the GPU
	with **true MSAA**, so abutting fills partition coverage exactly -- no
	background bleed (the Cairo/Canvas conflation artifact) and no ~N^2 cost.

	Pipeline (WebGL2, one multisampled framebuffer per shape):

	  * Each fill is drawn with **stencil-then-cover**, which fills an arbitrary
	    path (concave, holes, self-intersecting) without CPU triangulation:
	      - stencil pass: draw a triangle fan (anchor -> each flattened edge) of
	        all the fill's subpaths into the stencil buffer with op=INVERT, so the
	        even-odd interior ends up with a non-zero stencil (holes cancel);
	      - cover pass: draw a full-screen quad with the fill colour where
	        stencil != 0, resetting the stencil to 0 as it goes.
	  * Because the framebuffer is multisampled, the stencil (and therefore
	    coverage) is per-sample, so interior seams between abutting fills resolve
	    exactly and the silhouette gets clean AA -- all in one resolve.

	Only solid-colour vector fills are handled for now (`isCompatible`); anything
	else (gradients, bitmap/shader fills, thick line styles, non-zero winding,
	the DRAW_* primitives) returns false so the caller falls back to the software
	path. Curves are flattened; even-odd winding (OpenFL's Canvas default) is
	assumed.

	Selected on html5 with `-D openfl_canvas_msaa` (dispatched from
	`CanvasGraphics.render`). The same approach is reusable by native GL targets.
	Kept deliberately separate; can fold into `Context3DGraphics` later.
**/
@:access(openfl.display.Graphics)
@:access(openfl.display.BitmapData)
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
	private static var supported:Bool = true;
	private static var inited:Bool = false;
	private static var glCanvas:CanvasElement;
	private static var gl:Dynamic; // WebGL2RenderingContext
	private static var prog:Dynamic;
	private static var locPos:Int = -1;
	private static var locColor:Dynamic;
	private static var vbo:Dynamic;
	private static var msFBO:Dynamic;
	private static var msColor:Dynamic;
	private static var msDepthStencil:Dynamic;
	private static var fbW:Int = 0;
	private static var fbH:Int = 0;
	private static var fbS:Int = 0;

	// Per-render working state (main thread only, like DrawCommandReader).
	private static var _rt:Matrix;
	private static var _w:Float;
	private static var _h:Float;
	private static var _sub:Array<Array<Float>>;
	private static var _cur:Array<Float>;
	private static var _clx:Float;
	private static var _cly:Float;

	private static final QUAD:Array<Float> = [-1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0];
	#end

	/**
		Whether this path can currently render `graphics`: solid-colour vector
		fills only (path ops + BEGIN_FILL/END_FILL, no stroke, even-odd winding).
		Returns false for anything else so the caller uses the software path.
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
				case BEGIN_FILL:
					hasAnyFill = true;
					data.skip(type);

				case END_FILL, MOVE_TO, LINE_TO, CURVE_TO, CUBIC_CURVE_TO, WINDING_EVEN_ODD:
					data.skip(type);

				case LINE_STYLE:
					// A visible stroke isn't handled by this path yet.
					var c = data.readLineStyle();
					if (c.thickness != null)
					{
						ok = false;
					}

				default:
					// bitmap/gradient/shader fills, DRAW_* primitives, non-zero
					// winding, overrides, unknown -> not handled.
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
		`CanvasGraphics.render`: 2D canvas at normal size, `__bitmapScaleX/Y = 1`).
		Returns true if handled, false to fall back to the software path.
	**/
	public static function render(graphics:Graphics, renderer:CanvasRenderer):Bool
	{
		#if (js && html5)
		if (!supported) return false;

		var width = graphics.__width;
		var height = graphics.__height;
		if (width < 1 || height < 1) return false;
		if (!isCompatible(graphics)) return false;
		if (!initGL()) return false;
		if (!ensureTarget(width, height)) return false;

		_rt = graphics.__renderTransform;
		_w = width;
		_h = height;
		_sub = [];
		_cur = null;

		gl.bindFramebuffer(gl.FRAMEBUFFER, msFBO);
		gl.viewport(0, 0, width, height);
		gl.disable(gl.DEPTH_TEST);
		gl.enable(gl.STENCIL_TEST);
		gl.enable(gl.BLEND);
		// premultiplied over (shader outputs premultiplied colour)
		gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
		gl.clearColor(0, 0, 0, 0);
		gl.clearStencil(0);
		gl.clear(gl.COLOR_BUFFER_BIT | gl.STENCIL_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

		gl.useProgram(prog);
		gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
		gl.enableVertexAttribArray(locPos);
		gl.vertexAttribPointer(locPos, 2, gl.FLOAT, false, 0, 0);

		var data = new DrawCommandReader(graphics.__commands);
		var hasFill = false;
		var fr = 0.0, fg = 0.0, fb = 0.0, fa = 0.0;

		for (type in graphics.__commands.types)
		{
			switch (type)
			{
				case BEGIN_FILL:
					if (hasFill) flushFill(fr, fg, fb, fa);
					var c = data.readBeginFill();
					fr = ((c.color >> 16) & 0xFF) / 255.0;
					fg = ((c.color >> 8) & 0xFF) / 255.0;
					fb = (c.color & 0xFF) / 255.0;
					fa = c.alpha;
					hasFill = true;
					_sub = [];
					_cur = null;

				case END_FILL:
					data.skip(type);
					if (hasFill) flushFill(fr, fg, fb, fa);
					hasFill = false;
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
					data.readLineStyle(); // thickness==null guaranteed by isCompatible

				default:
					data.skip(type);
			}
		}
		if (hasFill) flushFill(fr, fg, fb, fa);
		data.destroy();

		// Resolve the multisampled buffer into the (single-sample) default
		// framebuffer of glCanvas, then snapshot it into graphics.__canvas.
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

		graphics.__bitmapScaleX = 1;
		graphics.__bitmapScaleY = 1;

		if (graphics.__bitmap == null || graphics.__bitmap.width != width || graphics.__bitmap.height != height)
		{
			graphics.__bitmap = BitmapData.fromCanvas(graphics.__canvas);
		}
		else
		{
			graphics.__bitmap.image.version++;
		}

		return true;
		#else
		return false;
		#end
	}

	#if (js && html5)
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

			var vs = compile(gl.VERTEX_SHADER, "#version 300 es\nin vec2 p;\nvoid main(){ gl_Position = vec4(p, 0.0, 1.0); }");
			var fs = compile(gl.FRAGMENT_SHADER,
				"#version 300 es\nprecision highp float;\nuniform vec4 uColor;\nout vec4 o;\nvoid main(){ o = vec4(uColor.rgb * uColor.a, uColor.a); }");
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
			locColor = gl.getUniformLocation(prog, "uColor");
			vbo = gl.createBuffer();
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

	// Create/reuse the multisampled colour + depth-stencil framebuffer.
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

	// local coord -> clip space (y flipped so local-top maps to the top row)
	private static inline function pushClip(lx:Float, ly:Float):Void
	{
		var px = _rt.a * lx + _rt.c * ly + _rt.tx;
		var py = _rt.b * lx + _rt.d * ly + _rt.ty;
		_cur.push(px / _w * 2 - 1);
		_cur.push(1 - py / _h * 2);
	}

	// segment count for a curve, from its transformed chord length
	private static inline function segsFor(ax:Float, ay:Float, bx:Float, by:Float):Int
	{
		var pax = _rt.a * ax + _rt.c * ay + _rt.tx;
		var pay = _rt.b * ax + _rt.d * ay + _rt.ty;
		var pbx = _rt.a * bx + _rt.c * by + _rt.tx;
		var pby = _rt.b * bx + _rt.d * by + _rt.ty;
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
		if (_cur == null)
		{
			emitMove(lx, ly);
		}
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
			var t = i / n;
			var mt = 1 - t;
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
			var t = i / n;
			var mt = 1 - t;
			var b0 = mt * mt * mt, b1 = 3 * mt * mt * t, b2 = 3 * mt * t * t, b3 = t * t * t;
			pushClip(b0 * x0 + b1 * c1x + b2 * c2x + b3 * ax, b0 * y0 + b1 * c1y + b2 * c2y + b3 * ay);
			i++;
		}
		_clx = ax;
		_cly = ay;
	}

	// Render one fill: stencil pass (even-odd INVERT) then cover pass.
	private static function flushFill(r:Float, g:Float, b:Float, a:Float):Void
	{
		if (_sub == null || _sub.length == 0) return;

		var verts = new Array<Float>();
		for (sp in _sub)
		{
			var n = sp.length >> 1;
			if (n < 3) continue;
			var ax = sp[0], ay = sp[1];
			var i = 1;
			while (i < n - 1)
			{
				verts.push(ax);
				verts.push(ay);
				verts.push(sp[i * 2]);
				verts.push(sp[i * 2 + 1]);
				verts.push(sp[i * 2 + 2]);
				verts.push(sp[i * 2 + 3]);
				i++;
			}
		}
		if (verts.length == 0)
		{
			_sub = [];
			_cur = null;
			return;
		}

		// stencil pass: no colour, toggle stencil per covered sample
		gl.colorMask(false, false, false, false);
		gl.stencilMask(0xFF);
		gl.stencilFunc(gl.ALWAYS, 0, 0xFF);
		gl.stencilOp(gl.KEEP, gl.KEEP, gl.INVERT);
		gl.uniform4f(locColor, 0, 0, 0, 0);
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(cast verts), gl.STREAM_DRAW);
		gl.drawArrays(gl.TRIANGLES, 0, Std.int(verts.length / 2));

		// cover pass: paint colour where stencil != 0, reset stencil to 0
		gl.colorMask(true, true, true, true);
		gl.stencilFunc(gl.NOTEQUAL, 0, 0xFF);
		gl.stencilOp(gl.KEEP, gl.KEEP, gl.ZERO);
		gl.uniform4f(locColor, r, g, b, a);
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(cast QUAD), gl.STREAM_DRAW);
		gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

		_sub = [];
		_cur = null;
	}
	#end
}
#end
