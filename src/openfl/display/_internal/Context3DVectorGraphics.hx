package openfl.display._internal;

#if !flash
import openfl.display.CapsStyle;
import openfl.display.Graphics;
import openfl.display.GradientType;
import openfl.display.JointStyle;
import openfl.display.LineScaleMode;
import openfl.display.OpenGLRenderer;
import openfl.display.SpreadMethod;
import openfl.display._internal.DrawCommandReader;
#if (js && html5)
import openfl.display.BitmapData;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DBlendFactor;
import openfl.display3D.Context3DBufferUsage;
import openfl.display3D.Context3DCompareMode;
import openfl.display3D.Context3DMipFilter;
import openfl.display3D.Context3DProgramFormat;
import openfl.display3D.Context3DProgramType;
import openfl.display3D.Context3DStencilAction;
import openfl.display3D.Context3DTextureFilter;
import openfl.display3D.Context3DTextureFormat;
import openfl.display3D.Context3DTriangleFace;
import openfl.display3D.Context3DVertexBufferFormat;
import openfl.display3D.Context3DWrapMode;
import openfl.display3D.IndexBuffer3D;
import openfl.display3D.Program3D;
import openfl.display3D.VertexBuffer3D;
import openfl.display3D.textures.RectangleTexture;
import openfl.display3D.textures.TextureBase;
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
	setStencilActions, drawTriangles, setProgramConstantsFromVector, setTextureAt)
	so it stays one technology and doesn't desync Context3D's state cache.

	Fills: solid colour, linear/radial gradients (PAD/REPEAT/REFLECT, sRGB
	interpolation), and bitmap fills (repeat + smoothing). Solid strokes are
	tessellated to fill geometry (segment quads + joints + caps) and drawn with a
	union-coverage stencil after all fills, so they sit on top. Per-fill data
	reaches the GLSL shaders through Context3D fragment constants (fc0..fc2) and
	samplers (sampler0) -- OpenFL's GLSL-uniform path was completed for this (see
	Program3D __buildAGALUniformList / __flush / __enable).

	Shapes with gradient/bitmap line styles (rare) return false so the caller
	falls back to the raw-WebGL OpenGLGraphics renderer.
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

	private static inline var MODE_SOLID = 0;
	private static inline var MODE_LINEAR = 1;
	private static inline var MODE_RADIAL = 2;
	private static inline var MODE_BITMAP = 3;

	#if (js && html5)
	private static var supported:Bool = true;
	private static var inited:Bool = false;
	private static var progStencil:Program3D;
	private static var progSolid:Program3D;
	private static var progGradient:Program3D;
	private static var progBitmap:Program3D;
	private static var vbuf:VertexBuffer3D;
	private static var vbufCap:Int = 0;
	private static var vbufStride:Int = 4; // clip.xy, pixel.xy
	private static var ibuf:IndexBuffer3D;
	private static var ibufCap:Int = 0;
	private static var rampTex:RectangleTexture;
	private static var rampBmd:BitmapData;

	// render transform + inverse (pixel -> shape-local, bounds folded in)
	private static var _rt:Matrix;
	private static var _bx:Float;
	private static var _by:Float;
	private static var _w:Float;
	private static var _h:Float;
	private static var _invA:Float;
	private static var _invB:Float;
	private static var _invC:Float;
	private static var _invD:Float;
	private static var _invTX:Float;
	private static var _invTY:Float;
	private static var _sub:Array<Array<Float>>; // PIXEL coords (fills+strokes share)
	private static var _cur:Array<Float>;
	private static var _clx:Float;
	private static var _cly:Float;

	// current fill state
	private static var _mode:Int = MODE_SOLID;
	private static var _r:Float = 0;
	private static var _g:Float = 0;
	private static var _b:Float = 0;
	private static var _a:Float = 0;
	private static var _spread:Float = 0; // 0 pad, 1 reflect, 2 repeat
	// pixel -> gradient/uv matrix rows: gx = mA*px + mC*py + mTX; gy = mB*px + mD*py + mTY
	private static var _mA:Float = 1;
	private static var _mB:Float = 0;
	private static var _mC:Float = 0;
	private static var _mD:Float = 1;
	private static var _mTX:Float = 0;
	private static var _mTY:Float = 0;
	private static var _bmp:BitmapData;
	private static var _bmpRepeat:Bool = false;
	private static var _bmpSmooth:Bool = false;

	// current stroke (line) descriptor -- tessellated to fill geometry
	private static var _hasStroke:Bool = false;
	private static var _shw:Float = 0; // half thickness, pixels
	private static var _scaps:Int = 0; // 0 butt, 1 round, 2 square
	private static var _sjoints:Int = 0; // 0 bevel, 1 miter, 2 round
	private static var _smiter:Float = 3;
	private static var _slr:Float = 0;
	private static var _slg:Float = 0;
	private static var _slb:Float = 0;
	private static var _sla:Float = 1;
	// stroke batches, rendered after all fills so strokes sit on top
	private static var _strokeBatches:Array<{verts:Vector<Float>, r:Float, g:Float, b:Float, a:Float}>;
	#end

	// Solid / gradient / bitmap fills + solid strokes + path ops. Shapes with
	// gradient/bitmap line styles are rejected so the caller falls back.
	public static function isCompatible(graphics:Graphics):Bool
	{
		#if (js && html5)
		if (graphics.__commands == null) return false;
		var hasContent = false;
		var data = new DrawCommandReader(graphics.__commands);
		var ok = true;
		for (type in graphics.__commands.types)
		{
			switch (type)
			{
				case BEGIN_FILL, BEGIN_GRADIENT_FILL, BEGIN_BITMAP_FILL, LINE_STYLE:
					hasContent = true;
					data.skip(type);
				case END_FILL, MOVE_TO, LINE_TO, CURVE_TO, CUBIC_CURVE_TO, WINDING_EVEN_ODD, WINDING_NON_ZERO:
					data.skip(type);
				default:
					// line gradient/bitmap styles, DRAW_* primitives, shader fills -> fallback
					ok = false;
					data.skip(type);
			}
			if (!ok) break;
		}
		data.destroy();
		return ok && hasContent;
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

		// inverse render transform (pixel -> shape-local, bounds folded in)
		var det = _rt.a * _rt.d - _rt.b * _rt.c;
		if (det == 0) return false;
		var idet = 1.0 / det;
		_invA = _rt.d * idet;
		_invB = -_rt.b * idet;
		_invC = -_rt.c * idet;
		_invD = _rt.a * idet;
		_invTX = -(_invA * _rt.tx + _invC * _rt.ty) + _bx;
		_invTY = -(_invB * _rt.tx + _invD * _rt.ty) + _by;

		_sub = [];
		_cur = null;
		_mode = MODE_SOLID;
		_hasStroke = false;
		_strokeBatches = [];

		context.setRenderToTexture(tex, true, OpenGLGraphics.samples);
		context.clear(0, 0, 0, 0, 1, 0);
		context.setDepthTest(false, Context3DCompareMode.ALWAYS);
		context.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA);

		var data = new DrawCommandReader(graphics.__commands);
		var hasFill = false;

		for (type in graphics.__commands.types)
		{
			switch (type)
			{
				case BEGIN_FILL:
					if (hasFill) flushFill(context);
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
					if (hasFill) flushFill(context);
					var c = data.readBeginGradientFill();
					setupGradient(c.type, c.colors, c.alphas, c.ratios, c.matrix, c.spreadMethod);
					hasFill = true;
					collectStrokes();
					_sub = [];
					_cur = null;

				case BEGIN_BITMAP_FILL:
					if (hasFill) flushFill(context);
					var c = data.readBeginBitmapFill();
					if (!setupBitmap(c.bitmap, c.matrix, c.repeat, c.smooth))
					{
						data.destroy();
						context.setRenderToBackBuffer();
						return false;
					}
					hasFill = true;
					collectStrokes();
					_sub = [];
					_cur = null;

				case END_FILL:
					data.skip(type);
					if (hasFill) flushFill(context);
					hasFill = false;
					collectStrokes();
					_sub = [];
					_cur = null;

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
		if (hasFill) flushFill(context);
		collectStrokes();
		renderStrokeBatches(context);
		data.destroy();

		context.setRenderToBackBuffer();
		// leave no samplers bound into the compositor's state
		context.setTextureAt(0, null);

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
			// stencil pass: position only, no colour output (masked off anyway)
			progStencil = context.createProgram(Context3DProgramFormat.GLSL);
			progStencil.uploadSources("attribute vec2 va0;\nvoid main(){ gl_Position = vec4(va0, 0.0, 1.0); }",
				"void main(){ gl_FragColor = vec4(0.0); }");

			// solid: premultiplied colour from fragment constant fc0
			progSolid = context.createProgram(Context3DProgramFormat.GLSL);
			progSolid.uploadSources("attribute vec2 va0;\nvoid main(){ gl_Position = vec4(va0, 0.0, 1.0); }", [
				"uniform vec4 fc0;", // rgb, a (straight)
				"void main(){ gl_FragColor = vec4(fc0.rgb * fc0.a, fc0.a); }"
			].join("\n"));

			// gradient: pixel coord -> gradient coord (fc1/fc2 matrix), sample ramp
			progGradient = context.createProgram(Context3DProgramFormat.GLSL);
			progGradient.uploadSources([
				"attribute vec2 va0;",
				"attribute vec2 va1;",
				"varying vec2 vPixel;",
				"void main(){ vPixel = va1; gl_Position = vec4(va0, 0.0, 1.0); }"
			].join("\n"), [
				"varying vec2 vPixel;",
				"uniform vec4 fc0;", // mode, spread, 0, 0
				"uniform vec4 fc1;", // mA, mB, mC, mD
				"uniform vec4 fc2;", // mTX, mTY, 0, 0
				"uniform sampler2D sampler0;",
				"float sprd(float t, float m){ if(m<0.5) return clamp(t,0.0,1.0); if(m>1.5) return fract(t); float f=fract(t*0.5)*2.0; return f>1.0?2.0-f:f; }",
				"void main(){",
				"  float gx = fc1.x*vPixel.x + fc1.z*vPixel.y + fc2.x;",
				"  float gy = fc1.y*vPixel.x + fc1.w*vPixel.y + fc2.y;",
				"  vec4 c;",
				"  if (fc0.x < 1.5) c = texture2D(sampler0, vec2(sprd((gx+819.2)/1638.4, fc0.y), 0.5));",
				"  else c = texture2D(sampler0, vec2(sprd(length(vec2(gx,gy))/819.2, fc0.y), 0.5));",
				"  gl_FragColor = vec4(c.rgb*c.a, c.a);",
				"}"
			].join("\n"));

			// bitmap: pixel coord -> uv (fc1/fc2 matrix, already normalized), sample
			progBitmap = context.createProgram(Context3DProgramFormat.GLSL);
			progBitmap.uploadSources([
				"attribute vec2 va0;",
				"attribute vec2 va1;",
				"varying vec2 vPixel;",
				"void main(){ vPixel = va1; gl_Position = vec4(va0, 0.0, 1.0); }"
			].join("\n"), [
				"varying vec2 vPixel;",
				"uniform vec4 fc1;", // mA, mB, mC, mD
				"uniform vec4 fc2;", // mTX, mTY, 0, 0
				"uniform sampler2D sampler0;",
				"void main(){",
				"  float u = fc1.x*vPixel.x + fc1.z*vPixel.y + fc2.x;",
				"  float v = fc1.y*vPixel.x + fc1.w*vPixel.y + fc2.y;",
				"  vec4 c = texture2D(sampler0, vec2(u, v));",
				"  gl_FragColor = vec4(c.rgb*c.a, c.a);",
				"}"
			].join("\n"));

			// 256x1 gradient ramp, straight RGBA (shader premultiplies)
			rampTex = context.createRectangleTexture(256, 1, Context3DTextureFormat.BGRA, false);
			rampBmd = new BitmapData(256, 1, true, 0xFF000000);
			rampTex.uploadFromBitmapData(rampBmd);

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

	private static function flushFill(context:Context3D):Void
	{
		if (_sub == null || _sub.length == 0) return;

		// build stencil fan triangles (pixel coords -> clip); pixel slots unused here
		var verts = new Vector<Float>();
		var n = 0;
		for (sp in _sub)
		{
			var cnt = sp.length >> 1;
			if (cnt < 3) continue;
			var ax = clipX(sp[0]), ay = clipY(sp[1]);
			var i = 1;
			while (i < cnt - 1)
			{
				pushV(verts, ax, ay, 0, 0);
				pushV(verts, clipX(sp[i * 2]), clipY(sp[i * 2 + 1]), 0, 0);
				pushV(verts, clipX(sp[i * 2 + 2]), clipY(sp[i * 2 + 3]), 0, 0);
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

		// cover pass: full-screen quad where stencil != 0, reset stencil to 0.
		// va1 carries render-target pixel coords for gradient/bitmap shading.
		uploadCoverQuad(context);

		context.setColorMask(true, true, true, true);
		context.setStencilReferenceValue(0, 0xFF, 0xFF);
		context.setStencilActions(Context3DTriangleFace.FRONT_AND_BACK, Context3DCompareMode.NOT_EQUAL, Context3DStencilAction.ZERO,
			Context3DStencilAction.KEEP, Context3DStencilAction.KEEP);

		coverPass(context);
		context.drawTriangles(ibuf, 0, 2);
		// NOTE: does not reset _sub -- the caller resets after collectStrokes(),
		// so the same path can be both filled and stroked.
	}

	private static inline function uploadCoverQuad(context:Context3D):Void
	{
		var quad = new Vector<Float>();
		pushV(quad, -1, -1, 0, _h);
		pushV(quad, 1, -1, _w, _h);
		pushV(quad, -1, 1, 0, 0);
		pushV(quad, -1, 1, 0, 0);
		pushV(quad, 1, -1, _w, _h);
		pushV(quad, 1, 1, _w, 0);
		vbuf.uploadFromVector(quad, 0, 6);
	}

	private static function coverPass(context:Context3D):Void
	{
		var consts = new Vector<Float>();
		switch (_mode)
		{
			case MODE_SOLID:
				context.setProgram(progSolid);
				context.setVertexBufferAt(0, vbuf, 0, Context3DVertexBufferFormat.FLOAT_2);
				context.setVertexBufferAt(1, null);
				consts.push(_r);
				consts.push(_g);
				consts.push(_b);
				consts.push(_a);
				context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, consts);

			case MODE_LINEAR, MODE_RADIAL:
				context.setProgram(progGradient);
				context.setVertexBufferAt(0, vbuf, 0, Context3DVertexBufferFormat.FLOAT_2);
				context.setVertexBufferAt(1, vbuf, 2, Context3DVertexBufferFormat.FLOAT_2);
				consts.push(_mode == MODE_RADIAL ? 2.0 : 1.0);
				consts.push(_spread);
				consts.push(0);
				consts.push(0);
				consts.push(_mA);
				consts.push(_mB);
				consts.push(_mC);
				consts.push(_mD);
				consts.push(_mTX);
				consts.push(_mTY);
				consts.push(0);
				consts.push(0);
				context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, consts);
				context.setTextureAt(0, rampTex);
				context.setSamplerStateAt(0, Context3DWrapMode.CLAMP, Context3DTextureFilter.LINEAR, Context3DMipFilter.MIPNONE);

			case MODE_BITMAP:
				context.setProgram(progBitmap);
				context.setVertexBufferAt(0, vbuf, 0, Context3DVertexBufferFormat.FLOAT_2);
				context.setVertexBufferAt(1, vbuf, 2, Context3DVertexBufferFormat.FLOAT_2);
				consts.push(0);
				consts.push(0);
				consts.push(0);
				consts.push(0);
				consts.push(_mA);
				consts.push(_mB);
				consts.push(_mC);
				consts.push(_mD);
				consts.push(_mTX);
				consts.push(_mTY);
				consts.push(0);
				consts.push(0);
				context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, consts);
				var bt:TextureBase = _bmp.getTexture(context);
				context.setTextureAt(0, bt);
				context.setSamplerStateAt(0, _bmpRepeat ? Context3DWrapMode.REPEAT : Context3DWrapMode.CLAMP,
					_bmpSmooth ? Context3DTextureFilter.LINEAR : Context3DTextureFilter.NEAREST, Context3DMipFilter.MIPNONE);
		}
	}

	// ---- strokes: tessellated to fill geometry, union-stencil coverage ----

	// Build stroke triangles for every subpath currently in _sub (under the
	// active line style) into a batch, drawn after all fills so strokes sit on
	// top. A line-style change mid-path applies the final style to the group.
	private static function collectStrokes():Void
	{
		if (!_hasStroke || _sub == null || _sub.length == 0) return;
		var out = new Vector<Float>();
		for (sp in _sub)
			strokeSubpath(sp, out);
		if (out.length > 0) _strokeBatches.push({verts: out, r: _slr, g: _slg, b: _slb, a: _sla});
	}

	private static function renderStrokeBatches(context:Context3D):Void
	{
		if (_strokeBatches == null) return;
		for (batch in _strokeBatches)
			flushStrokeBatch(context, batch.verts, batch.r, batch.g, batch.b, batch.a);
	}

	// Draw a stroke batch's tessellated triangles directly (stencil test off).
	// Opaque strokes are exact; overdraw at joints/caps is invisible. For
	// translucent strokes those overlaps blend twice (a minor darkening) -- a
	// union-coverage stencil would fix that, but the stencil write does not
	// persist across passes on this Context3D render-to-texture path, so we draw
	// directly. Gradient/bitmap line styles fall back to the raw-WebGL renderer.
	private static function flushStrokeBatch(context:Context3D, verts:Vector<Float>, r:Float, g:Float, b:Float, a:Float):Void
	{
		var n = Std.int(verts.length / vbufStride);
		if (n < 3) return;

		ensureBuffers(context, n);
		vbuf.uploadFromVector(verts, 0, n);

		context.setColorMask(true, true, true, true);
		context.setStencilReferenceValue(0, 0xFF, 0xFF);
		context.setStencilActions(Context3DTriangleFace.FRONT_AND_BACK, Context3DCompareMode.ALWAYS, Context3DStencilAction.KEEP,
			Context3DStencilAction.KEEP, Context3DStencilAction.KEEP);
		context.setProgram(progSolid);
		context.setVertexBufferAt(0, vbuf, 0, Context3DVertexBufferFormat.FLOAT_2);
		context.setVertexBufferAt(1, null);
		var consts = new Vector<Float>();
		consts.push(r);
		consts.push(g);
		consts.push(b);
		consts.push(a);
		context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, consts);
		context.drawTriangles(ibuf, 0, Std.int(n / 3));
	}

	// push a clip-space triangle (pixel coords in), stride-4 with unused pixel slots
	private static inline function sTri(out:Vector<Float>, ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float):Void
	{
		pushV(out, clipX(ax), clipY(ay), 0, 0);
		pushV(out, clipX(bx), clipY(by), 0, 0);
		pushV(out, clipX(cx), clipY(cy), 0, 0);
	}

	private static function sDisc(out:Vector<Float>, cx:Float, cy:Float, r:Float):Void
	{
		var seg = 16, i = 0;
		while (i < seg)
		{
			var a0 = i / seg * 2 * Math.PI, a1 = (i + 1) / seg * 2 * Math.PI;
			sTri(out, cx, cy, cx + Math.cos(a0) * r, cy + Math.sin(a0) * r, cx + Math.cos(a1) * r, cy + Math.sin(a1) * r);
			i++;
		}
	}

	// Tessellate one subpath (pixel coords in sp) into stroke triangles.
	private static function strokeSubpath(sp:Array<Float>, out:Vector<Float>):Void
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

	private static function sSeg(out:Vector<Float>, ax:Float, ay:Float, bx:Float, by:Float, hw:Float):Void
	{
		var dx = bx - ax, dy = by - ay;
		var len = Math.sqrt(dx * dx + dy * dy);
		if (len < 1e-6) return;
		var nx = -dy / len * hw, ny = dx / len * hw;
		sTri(out, ax + nx, ay + ny, ax - nx, ay - ny, bx + nx, by + ny);
		sTri(out, bx + nx, by + ny, ax - nx, ay - ny, bx - nx, by - ny);
	}

	private static function sJoint(out:Vector<Float>, px:Float, py:Float, vx:Float, vy:Float, qx:Float, qy:Float, hw:Float):Void
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
	private static function sCap(out:Vector<Float>, ex:Float, ey:Float, tx:Float, ty:Float, hw:Float):Void
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

	// pixel -> gradient-local matrix + ramp, matching OpenGLGraphics.setupGradient
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

		// compose gInv (after) with invRender (first)
		_mA = ga * _invA + gc * _invB;
		_mC = ga * _invC + gc * _invD;
		_mTX = ga * _invTX + gc * _invTY + gtx;
		_mB = gb * _invA + gd * _invB;
		_mD = gb * _invC + gd * _invD;
		_mTY = gb * _invTX + gd * _invTY + gty;

		buildRamp(colors, alphas, ratios);
	}

	// Build a 256x1 straight-RGBA ramp from the colour stops and upload it.
	private static function buildRamp(colors:Array<Int>, alphas:Array<Float>, ratios:Array<Int>):Void
	{
		var n = colors.length;
		var si = 0;
		for (i in 0...256)
		{
			var t = i / 255.0;
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
			var ai = Std.int(a);
			var col = (ai << 24) | (Std.int(r) << 16) | (Std.int(g) << 8) | Std.int(b);
			rampBmd.setPixel32(i, 0, col);
		}
		rampTex.uploadFromBitmapData(rampBmd);
	}

	// pixel -> normalized uv matrix for a bitmap fill; returns false if the
	// bitmap can't provide a texture (caller falls back to software).
	private static function setupBitmap(bitmap:BitmapData, matrix:Matrix, repeat:Bool, smooth:Bool):Bool
	{
		if (bitmap == null) return false;

		_mode = MODE_BITMAP;
		_bmp = bitmap;
		_bmpRepeat = repeat;
		_bmpSmooth = smooth;

		var tw = bitmap.width, th = bitmap.height;
		if (tw < 1 || th < 1) return false;

		// inverse of bitmap matrix (shape-local -> bitmap pixels)
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
		_mA = (ba * _invA + bc * _invB) / tw;
		_mC = (ba * _invC + bc * _invD) / tw;
		_mTX = (ba * _invTX + bc * _invTY + btx) / tw;
		_mB = (bb * _invA + bd * _invB) / th;
		_mD = (bb * _invC + bd * _invD) / th;
		_mTY = (bb * _invTX + bd * _invTY + bty) / th;
		return true;
	}

	private static inline function pushV(v:Vector<Float>, x:Float, y:Float, px:Float, py:Float):Void
	{
		v.push(x);
		v.push(y);
		v.push(px);
		v.push(py);
	}

	private static inline function clipX(px:Float):Float
	{
		return px / _w * 2 - 1;
	}

	private static inline function clipY(py:Float):Float
	{
		return 1 - py / _h * 2;
	}

	// store PIXEL coords (shared by fills and stroke tessellation); the
	// fill/stroke passes convert to clip space at emit time.
	private static inline function pushClip(lx:Float, ly:Float):Void
	{
		var x = lx - _bx, y = ly - _by;
		_cur.push(_rt.a * x + _rt.c * y + _rt.tx);
		_cur.push(_rt.b * x + _rt.d * y + _rt.ty);
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
