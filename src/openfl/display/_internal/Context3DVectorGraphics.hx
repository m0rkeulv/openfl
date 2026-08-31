package openfl.display._internal;

#if !flash
import openfl.display.Graphics;
import openfl.display.OpenGLRenderer;
import openfl.display._internal.DrawCommandReader;
#if (js && html5)
import openfl.display.BitmapData;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DBlendFactor;
import openfl.display3D.Context3DBufferUsage;
import openfl.display3D.Context3DCompareMode;
import openfl.display3D.Context3DProgramFormat;
import openfl.display3D.Context3DProgramType;
import openfl.display3D.Context3DStencilAction;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.Context3DTriangleFace;
import openfl.display3D.Context3DVertexBufferFormat;
import openfl.display3D.IndexBuffer3D;
import openfl.display3D.Program3D;
import openfl.display3D.VertexBuffer3D;
import openfl.display3D.textures.RectangleTexture;
import openfl.geom.Matrix;
import openfl.Vector;
#end

/**
	Context3DVectorGraphics -- the texture-resident, Context3D-native variant of
	the GPU vector renderer (see OpenGLGraphics for the raw-WebGL one).

	Renders each shape's fills into a Context3D render-to-texture target with MSAA
	(no offscreen canvas, no readback), via stencil-then-cover, then hands the
	texture straight to `graphics.__bitmap.__texture` so the compositor draws it
	GPU-to-GPU. Everything goes through the Context3D API (setRenderToTexture,
	setStencilActions, drawTriangles) so it stays one technology and doesn't
	desync Context3D's state cache.

	Two ways to feed per-fill data to the GLSL shader (OpenFL's constant API does
	not wire up uploadSources-GLSL uniforms), selected by `variant` for A/B perf
	testing:
	  - A (attributes): fill colour travels as a vertex attribute (va1).
	  - B (uniform): fill colour is a `uColor` uniform set via gl.uniform, named so
	    Context3D leaves it alone.

	First cut handles SOLID fills only (the perf-critical case); gradient/bitmap/
	stroke shapes return false so the caller falls back to the other renderer.
**/
@:access(openfl.display.Graphics)
@:access(openfl.display.BitmapData)
@:access(openfl.display.DisplayObject)
@:access(openfl.display3D.Context3D)
@:access(openfl.display3D.Program3D)
@SuppressWarnings("checkstyle:FieldDocComment")
class Context3DVectorGraphics
{
	public static inline var VARIANT_ATTR = 1;
	public static inline var VARIANT_UNIFORM = 2;

	#if (js && html5)
	private static var supported:Bool = true;
	private static var inited:Bool = false;
	private static var progAttr:Program3D;
	private static var progStencil:Program3D;
	private static var progUniform:Program3D;
	private static var uColorLoc:Dynamic;
	private static var vbuf:VertexBuffer3D;
	private static var vbufCap:Int = 0;
	private static var vbufStride:Int = 6; // x,y,r,g,b,a
	private static var ibuf:IndexBuffer3D;
	private static var ibufCap:Int = 0;

	private static var _rt:Matrix;
	private static var _bx:Float;
	private static var _by:Float;
	private static var _w:Float;
	private static var _h:Float;
	private static var _sub:Array<Array<Float>>; // clip-space coords
	private static var _cur:Array<Float>;
	private static var _clx:Float;
	private static var _cly:Float;
	#end

	// SOLID fills + path ops only (first cut).
	public static function isCompatible(graphics:Graphics):Bool
	{
		#if (js && html5)
		if (graphics.__commands == null) return false;
		var hasFill = false;
		var data = new DrawCommandReader(graphics.__commands);
		var ok = true;
		for (type in graphics.__commands.types)
		{
			switch (type)
			{
				case BEGIN_FILL:
					hasFill = true;
					data.skip(type);
				case END_FILL, MOVE_TO, LINE_TO, CURVE_TO, CUBIC_CURVE_TO, WINDING_EVEN_ODD:
					data.skip(type);
				default:
					ok = false;
					data.skip(type);
			}
			if (!ok) break;
		}
		data.destroy();
		return ok && hasFill;
		#else
		return false;
		#end
	}

	public static function render(graphics:Graphics, renderer:OpenGLRenderer, variant:Int):Bool
	{
		#if (js && html5)
		if (!supported) return false;
		if (graphics.__owner == null || graphics.__owner.__worldScale9Grid != null) return false;
		if (!isCompatible(graphics)) return false;

		var context = renderer.__context3D;
		if (context == null) return false;

		#if (openfl_disable_hdpi || openfl_disable_hdpi_graphics)
		var pixelRatio = 1;
		#else
		var pixelRatio = renderer.__pixelRatio;
		#end
		graphics.__update(renderer.__worldTransform, pixelRatio);

		if (!graphics.__softwareDirty || graphics.__managed) return true;

		graphics.__bitmapScaleX = 1;
		graphics.__bitmapScaleY = 1;

		var width = graphics.__width;
		var height = graphics.__height;
		if (!graphics.__visible || graphics.__commands.length == 0 || graphics.__bounds == null || width < 1 || height < 1)
		{
			graphics.__bitmap = null;
			graphics.__softwareDirty = false;
			graphics.__dirty = false;
			return true;
		}

		if (!initGL(context)) return false;

		// reuse the target texture across frames when the size is unchanged
		var tex:RectangleTexture = null;
		if (graphics.__bitmap != null && graphics.__bitmap.width == width && graphics.__bitmap.height == height
			&& graphics.__bitmap.__texture != null && (graphics.__bitmap.__texture is RectangleTexture))
		{
			tex = cast graphics.__bitmap.__texture;
		}
		else
		{
			tex = context.createRectangleTexture(width, height, Context3DTextureFormat.BGRA, true);
		}

		_rt = graphics.__renderTransform;
		_bx = graphics.__bounds.x;
		_by = graphics.__bounds.y;
		_w = width;
		_h = height;
		_sub = [];
		_cur = null;

		context.setRenderToTexture(tex, true, OpenGLGraphics.samples);
		context.clear(0, 0, 0, 0, 1, 0);
		context.setDepthTest(false, Context3DCompareMode.ALWAYS);
		context.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA);

		var data = new DrawCommandReader(graphics.__commands);
		var hasFill = false;
		var fr = 0.0, fg = 0.0, fb = 0.0, fa = 0.0;

		for (type in graphics.__commands.types)
		{
			switch (type)
			{
				case BEGIN_FILL:
					if (hasFill) flushFill(context, variant, fr, fg, fb, fa);
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
					if (hasFill) flushFill(context, variant, fr, fg, fb, fa);
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
				default:
					data.skip(type);
			}
		}
		if (hasFill) flushFill(context, variant, fr, fg, fb, fa);
		data.destroy();

		context.setRenderToBackBuffer();

		// hand the texture to a (non-readable) BitmapData for the compositor
		if (graphics.__bitmap == null || graphics.__bitmap.width != width || graphics.__bitmap.height != height)
		{
			graphics.__bitmap = new BitmapData(width, height, true, 0);
		}
		graphics.__bitmap.__texture = tex;
		graphics.__bitmap.__textureContext = context.__context;
		graphics.__bitmap.__textureVersion = 0x7FFFFFFF;
		graphics.__bitmap.readable = false;
		graphics.__bitmap.image = null;

		graphics.__softwareDirty = false;
		graphics.__dirty = false;
		return true;
		#else
		return false;
		#end
	}

	#if (js && html5)
	private static function initGL(context:Context3D):Bool
	{
		if (inited) return supported;
		inited = true;
		try
		{
			// stencil pass: position only, no colour output needed (masked off)
			progStencil = context.createProgram(Context3DProgramFormat.GLSL);
			progStencil.uploadSources("attribute vec2 va0;\nvoid main(){ gl_Position = vec4(va0, 0.0, 1.0); }",
				"void main(){ gl_FragColor = vec4(0.0); }");

			// variant A: colour via vertex attribute va1
			progAttr = context.createProgram(Context3DProgramFormat.GLSL);
			progAttr.uploadSources("attribute vec2 va0;\nattribute vec4 va1;\nvarying vec4 vCol;\nvoid main(){ vCol = va1; gl_Position = vec4(va0, 0.0, 1.0); }",
				"varying vec4 vCol;\nvoid main(){ gl_FragColor = vec4(vCol.rgb * vCol.a, vCol.a); }");

			// variant B: colour via a uColor uniform (set with gl.uniform; named so
			// Context3D's constant flush ignores it)
			progUniform = context.createProgram(Context3DProgramFormat.GLSL);
			progUniform.uploadSources("attribute vec2 va0;\nvoid main(){ gl_Position = vec4(va0, 0.0, 1.0); }",
				"uniform vec4 uColor;\nvoid main(){ gl_FragColor = vec4(uColor.rgb * uColor.a, uColor.a); }");
			uColorLoc = context.gl.getUniformLocation(progUniform.__glProgram, "uColor");

			ensureBuffers(context, 4096);
			return true;
		}
		catch (e:Dynamic)
		{
			supported = false;
			return false;
		}
	}

	private static function ensureBuffers(context:Context3D, verts:Int):Void
	{
		if (verts <= vbufCap) return;
		var cap = vbufCap;
		if (cap < 4096) cap = 4096;
		while (cap < verts) cap *= 2;
		vbuf = context.createVertexBuffer(cap, vbufStride, Context3DBufferUsage.DYNAMIC_DRAW);
		vbufCap = cap;
		// sequential indices [0,1,2,...]
		var idx = new Vector<UInt>();
		for (i in 0...cap) idx.push(i);
		ibuf = context.createIndexBuffer(cap, Context3DBufferUsage.STATIC_DRAW);
		ibuf.uploadFromVector(idx, 0, cap);
		ibufCap = cap;
	}

	private static function flushFill(context:Context3D, variant:Int, r:Float, g:Float, b:Float, a:Float):Void
	{
		if (_sub == null || _sub.length == 0) return;

		// build stencil fan triangles (clip coords) with colour interleaved
		var verts = new Vector<Float>();
		var n = 0;
		for (sp in _sub)
		{
			var cnt = sp.length >> 1;
			if (cnt < 3) continue;
			var ax = sp[0], ay = sp[1];
			var i = 1;
			while (i < cnt - 1)
			{
				pushV(verts, ax, ay, r, g, b, a);
				pushV(verts, sp[i * 2], sp[i * 2 + 1], r, g, b, a);
				pushV(verts, sp[i * 2 + 2], sp[i * 2 + 3], r, g, b, a);
				n += 3;
				i++;
			}
		}
		if (n == 0) return;

		ensureBuffers(context, n);
		vbuf.uploadFromVector(verts, 0, n);

		// stencil pass: even-odd INVERT, no colour
		context.setColorMask(false, false, false, false);
		context.setStencilReferenceValue(0, 0xFF, 0xFF);
		context.setStencilActions(Context3DTriangleFace.FRONT_AND_BACK, Context3DCompareMode.ALWAYS, Context3DStencilAction.INVERT,
			Context3DStencilAction.KEEP, Context3DStencilAction.KEEP);
		context.setProgram(progStencil);
		context.setVertexBufferAt(0, vbuf, 0, Context3DVertexBufferFormat.FLOAT_2);
		context.setVertexBufferAt(1, null);
		context.drawTriangles(ibuf, 0, Std.int(n / 3));

		// cover pass: full-screen quad where stencil != 0, reset stencil to 0
		var quad = new Vector<Float>();
		pushV(quad, -1, -1, r, g, b, a);
		pushV(quad, 1, -1, r, g, b, a);
		pushV(quad, -1, 1, r, g, b, a);
		pushV(quad, -1, 1, r, g, b, a);
		pushV(quad, 1, -1, r, g, b, a);
		pushV(quad, 1, 1, r, g, b, a);
		vbuf.uploadFromVector(quad, 0, 6);

		context.setColorMask(true, true, true, true);
		context.setStencilReferenceValue(0, 0xFF, 0xFF);
		context.setStencilActions(Context3DTriangleFace.FRONT_AND_BACK, Context3DCompareMode.NOT_EQUAL, Context3DStencilAction.ZERO,
			Context3DStencilAction.KEEP, Context3DStencilAction.KEEP);

		if (variant == VARIANT_UNIFORM)
		{
			context.setProgram(progUniform);
			context.setVertexBufferAt(0, vbuf, 0, Context3DVertexBufferFormat.FLOAT_2);
			context.setVertexBufferAt(1, null);
			// force the program to bind, then set the uniform directly
			context.__flushGLProgram();
			var gl = context.gl;
			gl.uniform4f(uColorLoc, r, g, b, a);
		}
		else
		{
			context.setProgram(progAttr);
			context.setVertexBufferAt(0, vbuf, 0, Context3DVertexBufferFormat.FLOAT_2);
			context.setVertexBufferAt(1, vbuf, 2, Context3DVertexBufferFormat.FLOAT_4);
		}
		context.drawTriangles(ibuf, 0, 2);

		_sub = [];
		_cur = null;
	}

	private static inline function pushV(v:Vector<Float>, x:Float, y:Float, r:Float, g:Float, b:Float, a:Float):Void
	{
		v.push(x);
		v.push(y);
		v.push(r);
		v.push(g);
		v.push(b);
		v.push(a);
	}

	private static inline function pushClip(lx:Float, ly:Float):Void
	{
		var x = lx - _bx, y = ly - _by;
		var px = _rt.a * x + _rt.c * y + _rt.tx;
		var py = _rt.b * x + _rt.d * y + _rt.ty;
		_cur.push(px / _w * 2 - 1);
		_cur.push(1 - py / _h * 2);
	}

	private static inline function segsFor(ax:Float, ay:Float, bx:Float, by:Float):Int
	{
		var pax = _rt.a * (ax - _bx) + _rt.c * (ay - _by) + _rt.tx;
		var pay = _rt.b * (ax - _bx) + _rt.d * (ay - _by) + _rt.ty;
		var pbx = _rt.a * (bx - _bx) + _rt.c * (by - _by) + _rt.tx;
		var pby = _rt.b * (bx - _bx) + _rt.d * (by - _by) + _rt.ty;
		var dx = pbx - pax, dy = pby - pay;
		var nn = Math.ceil(Math.sqrt(dx * dx + dy * dy) / 4);
		if (nn < 4) nn = 4;
		if (nn > 64) nn = 64;
		return nn;
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
		var nn = segsFor(_clx, _cly, ax, ay);
		var x0 = _clx, y0 = _cly, i = 1;
		while (i <= nn)
		{
			var t = i / nn, mt = 1 - t;
			pushClip(mt * mt * x0 + 2 * mt * t * cx + t * t * ax, mt * mt * y0 + 2 * mt * t * cy + t * t * ay);
			i++;
		}
		_clx = ax;
		_cly = ay;
	}

	private static function emitCubic(c1x:Float, c1y:Float, c2x:Float, c2y:Float, ax:Float, ay:Float):Void
	{
		if (_cur == null) emitMove(_clx, _cly);
		var nn = segsFor(_clx, _cly, ax, ay);
		var x0 = _clx, y0 = _cly, i = 1;
		while (i <= nn)
		{
			var t = i / nn, mt = 1 - t;
			var b0 = mt * mt * mt, b1 = 3 * mt * mt * t, b2 = 3 * mt * t * t, b3 = t * t * t;
			pushClip(b0 * x0 + b1 * c1x + b2 * c2x + b3 * ax, b0 * y0 + b1 * c1y + b2 * c2y + b3 * ay);
			i++;
		}
		_clx = ax;
		_cly = ay;
	}
	#end
}
#end
