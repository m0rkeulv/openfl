package openfl.display;

#if !flash
import openfl.display._internal.CanvasBitmap;
import openfl.display._internal.CanvasBitmapData;
import openfl.display._internal.CanvasDisplayObject;
import openfl.display._internal.CanvasDisplayObjectContainer;
import openfl.display._internal.CanvasGraphics;
import openfl.display._internal.CanvasSimpleButton;
import openfl.display._internal.CanvasTextField;
import openfl.display._internal.CanvasTilemap;
import openfl.display._internal.CanvasVideo;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
#if lime
import lime.graphics.Canvas2DRenderContext;
#end

/**
	**BETA**

	The CanvasRenderer API exposes support for HTML5 canvas render instructions within the
	`RenderEvent.RENDER_CANVAS` event
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.display.DisplayObject)
@:access(openfl.display.Graphics)
@:access(openfl.geom.Matrix)
@:access(openfl.geom.Rectangle)
@:access(openfl.display.IBitmapDrawable)
@:access(openfl.display.Stage)
@:access(openfl.display.Stage3D)
@:allow(openfl.display._internal)
@:allow(openfl.display)
@:allow(openfl.text)
class CanvasRenderer extends DisplayObjectRenderer
{
	/**
		The current HTML5 canvas render context
	**/
	@SuppressWarnings("checkstyle:Dynamic")
	public var context:#if lime Canvas2DRenderContext #else Dynamic #end;

	@:noCompletion private var __isDOM:Bool;
	@:noCompletion private var __tempMatrix:Matrix;
	@:noCompletion private var __blendGroupDepth:Int = 0;
	@:noCompletion private var __layerDepth:Int = 0;

	#if (js && html5)
	@:noCompletion private static var __groupCanvases:Array<js.html.CanvasElement> = [];
	@:noCompletion private static var __groupDepth:Int = 0;
	// the touched buffer of the LAYER group being drawn into (see __touch), once built: a canvas
	// in the same coordinates as the group's, kept per layer depth
	@:noCompletion private var __touched:js.html.CanvasElement;
	@:noCompletion private static var __touchedCanvases:Array<js.html.CanvasElement> = [];
	#end

	@SuppressWarnings("checkstyle:Dynamic")
	@:noCompletion private function new(context:#if lime Canvas2DRenderContext #else Dynamic #end)
	{
		super();

		this.context = context;

		__tempMatrix = new Matrix();

		#if lime
		__type = CANVAS;
		#end
	}

	/**
		Set whether smoothing should be enabled on a canvas context
	**/
	@SuppressWarnings("checkstyle:Dynamic")
	public function applySmoothing(context:#if lime Canvas2DRenderContext #else Dynamic #end, value:Bool):Void
	{
		context.imageSmoothingEnabled = value;
	}

	/**
		Set the matrix value for the current render context, or (optionally) another canvas
		context
	**/
	@SuppressWarnings("checkstyle:Dynamic")
	public function setTransform(transform:Matrix, context:#if lime Canvas2DRenderContext #else Dynamic #end = null):Void
	{
		if (context == null)
		{
			context = this.context;
		}
		else if (this.context == context && __worldTransform != null)
		{
			__tempMatrix.copyFrom(transform);
			__tempMatrix.concat(__worldTransform);
			transform = __tempMatrix;
		}

		if (__roundPixels)
		{
			context.setTransform(transform.a, transform.b, transform.c, transform.d, Std.int(transform.tx), Std.int(transform.ty));
		}
		else
		{
			context.setTransform(transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty);
		}
	}

	@:noCompletion private override function __clear():Void
	{
		if (__stage != null)
		{
			var cacheBlendMode = __blendMode;
			__blendMode = null;
			__setBlendMode(NORMAL);

			context.setTransform(1, 0, 0, 1, 0, 0);
			context.globalAlpha = 1;

			if (!__stage.__transparent && __stage.__clearBeforeRender)
			{
				context.fillStyle = __stage.__colorString;
				context.fillRect(0, 0, __stage.stageWidth * __stage.window.scale, __stage.stageHeight * __stage.window.scale);
			}
			else if (__stage.__transparent && __stage.__clearBeforeRender)
			{
				context.clearRect(0, 0, __stage.stageWidth * __stage.window.scale, __stage.stageHeight * __stage.window.scale);
			}

			__setBlendMode(cacheBlendMode);
		}
	}

	@:noCompletion private override function __popMask():Void
	{
		context.restore();
	}

	@:noCompletion private override function __popMaskObject(object:DisplayObject, handleScrollRect:Bool = true):Void
	{
		if (!object.__isCacheBitmapRender && object.__mask != null)
		{
			__popMask();
		}

		if (handleScrollRect && object.__scrollRect != null)
		{
			__popMaskRect();
		}
	}

	@:noCompletion private override function __popMaskRect():Void
	{
		context.restore();
	}

	@:noCompletion private override function __pushMask(mask:DisplayObject):Void
	{
		context.save();

		setTransform(mask.__renderTransform, context);

		context.beginPath();
		__renderDrawableMask(mask);
		context.closePath();

		context.clip();
	}

	@:noCompletion private override function __pushMaskObject(object:DisplayObject, handleScrollRect:Bool = true):Void
	{
		if (handleScrollRect && object.__scrollRect != null)
		{
			__pushMaskRect(object.__scrollRect, object.__renderTransform);
		}

		if (!object.__isCacheBitmapRender && object.__mask != null)
		{
			__pushMask(object.__mask);
		}
	}

	@:noCompletion private override function __pushMaskRect(rect:Rectangle, transform:Matrix):Void
	{
		context.save();

		setTransform(transform, context);

		context.beginPath();
		context.rect(rect.x, rect.y, rect.width, rect.height);
		context.clip();
	}

	@:noCompletion private override function __render(object:IBitmapDrawable):Void
	{
		// the root is rendered as it is, its own blend mode being its parent's to apply, unless
		// BitmapData.draw gave a blend mode: then the root is composited with it, as one object
		if (__overrideBlendMode != null && __overrideBlendMode != NORMAL) __renderDrawable(object);
		else __renderDrawableDirect(object);
	}

	@:noCompletion private function __renderDrawable(object:IBitmapDrawable):Void
	{
		if (object == null) return;

		#if (js && html5)
		if (object.__drawableType != BITMAP_DATA)
		{
			var displayObject:DisplayObject = cast object;

			// LAYER composes the subtree offscreen; the modes without a composite operation
			// are composed the same way (see __renderGroup)
			if (displayObject.__blendMode == LAYER && __blendGroupDepth == 0 && (__overrideBlendMode == null || __overrideBlendMode == NORMAL))
			{
				__renderGroup(displayObject, LAYER);
				__touch(displayObject, true);
				return;
			}

			if (__blendGroupDepth == 0)
			{
				var blendMode = __overrideBlendMode != null ? __overrideBlendMode : displayObject.__worldBlendMode;
				if (blendMode == __groupBlendMode) blendMode = NORMAL;

				switch (blendMode)
				{
					case SUBTRACT, INVERT, ERASE, ALPHA:
						__renderGroup(displayObject, blendMode);
						__touch(displayObject, true);
						return;
					default:
						if (__needsWholeObjectGroup(displayObject, blendMode))
						{
							__renderGroup(displayObject, blendMode);
							__touch(displayObject, true);
							return;
						}
				}
			}
		}
		#end

		__renderDrawableDirect(object);
		#if (js && html5)
		if (object.__drawableType != BITMAP_DATA) __touch(cast object);
		#end
	}

	/**
		Whether a container has to be rendered into a group before it is blended.

		Flash blends an object as a whole. If a container were drawn child by child with one of the
		modes this renderer blends in a single operation (ADD, MULTIPLY, SCREEN, DIFFERENCE, LIGHTEN,
		DARKEN, HARDLIGHT or OVERLAY), each child would be blended separately, and where two children
		overlap the backdrop would be blended twice. So a container with more than one piece, either
		several children or a child plus graphics of its own, is rendered into a group first, with
		children that only inherit its mode drawn as NORMAL, and the finished group is blended once. A
		shape never needs this, because its graphics are already rendered to a single image before they
		are drawn.
	**/
	@:noCompletion private function __needsWholeObjectGroup(displayObject:DisplayObject, blendMode:BlendMode):Bool
	{
		var operatorMode = switch (blendMode)
		{
			case ADD, MULTIPLY, SCREEN, DIFFERENCE, LIGHTEN, DARKEN, HARDLIGHT, OVERLAY: true;
			default: false;
		}
		if (!operatorMode) return false;
		var children = displayObject.__children;
		if (children == null || children.length == 0) return false;
		var graphics = displayObject.__graphics;
		return children.length > 1 || (graphics != null && graphics.__commands.length > 0);
	}

	#if (js && html5)
	/**
		Renders `displayObject` into a group the size of its bounds, then combines that group with the
		target according to `blendMode`.

		The group is a canvas. LAYER and the modes the canvas supports directly are a single drawImage
		with the matching composite operation. ERASE and ALPHA use destination-out and destination-in,
		clipped to the object's bounds because those operations would otherwise affect the whole target.
		INVERT and SUBTRACT are built from several operations: directly on the target when it is an
		opaque stage, and otherwise on a copy of the backdrop that is drawn back with source-atop, which
		keeps the backdrop's own alpha.
	**/
	@:noCompletion private function __renderGroup(displayObject:DisplayObject, blendMode:BlendMode):Void
	{
		if (!displayObject.__renderable || displayObject.__worldAlpha <= 0) return;

		var bounds = Rectangle.__pool.get();
		var visible = __getGroupBounds(displayObject, bounds);

		var x0 = Std.int(bounds.x);
		var y0 = Std.int(bounds.y);
		var width = Std.int(bounds.width);
		var height = Std.int(bounds.height);

		Rectangle.__pool.release(bounds);
		if (!visible) return;

		// four canvases per nesting level: the object, a backdrop copy, the uncovered object, coverage
		var level = __groupDepth * 4;
		var object = __beginGroupCanvas(level, width, height);
		__renderIntoGroup(displayObject, object.getContext2d(), x0, y0, blendMode);

		// the object's alpha applies once, to the whole object: __compositeDirect (LAYER and the
		// operator modes) draws with it, the four formula composites get the group scaled by it here
		var formulaMode = blendMode == SUBTRACT || blendMode == INVERT || blendMode == ERASE || blendMode == ALPHA;
		var alpha = __getAlpha(displayObject.__worldAlpha);
		if (formulaMode && alpha < 1)
		{
			var objectContext = object.getContext2d();
			objectContext.setTransform(1, 0, 0, 1, 0, 0);
			objectContext.globalAlpha = 1;
			objectContext.globalCompositeOperation = "destination-in";
			objectContext.fillStyle = "rgba(0, 0, 0, " + alpha + ")";
			objectContext.fillRect(0, 0, width, height);
		}

		// Flash applies these four modes to the part of every pixel that earlier objects have
		// covered (see __touch), and draws the object as it is over the rest. Without a touched
		// buffer, everything counts as covered. ALPHA and ERASE work with composite operations,
		// and so do SUBTRACT and INVERT on an opaque target, whose formulas then have an opaque
		// backdrop. On a transparent target SUBTRACT and INVERT are done pixel by pixel: their
		// formulas take the covered part's color, which no operation can give
		if (formulaMode) __ensureTouched(displayObject);
		var pixels = (blendMode == SUBTRACT || blendMode == INVERT) && !__backdropIsOpaque();
		var uncovered:js.html.CanvasElement = null;
		if (formulaMode && !pixels && __touchedActive)
		{
			// the object over what is not covered, added back after the composite
			uncovered = __getGroupCanvas(level + 2, width, height);
			var uncoveredContext = uncovered.getContext2d();
			uncoveredContext.setTransform(1, 0, 0, 1, 0, 0);
			uncoveredContext.globalAlpha = 1;
			uncoveredContext.globalCompositeOperation = "copy";
			uncoveredContext.drawImage(object, 0, 0, width, height, 0, 0, width, height);
			uncoveredContext.globalCompositeOperation = "destination-out";
			uncoveredContext.drawImage(__touched, x0, y0, width, height, 0, 0, width, height);
		}

		// compose the group onto the target. No clip here: an advanced blend mode under a
		// clip takes a slow path on the accelerated canvas, and every composite except
		// ALPHA / ERASE is bounded by what it draws
		context.save();
		context.setTransform(1, 0, 0, 1, 0, 0);
		context.globalAlpha = 1;

		if (pixels)
		{
			__compositeFormulaPixels(object, x0, y0, width, height, blendMode);
		}
		else
		{
			switch (blendMode)
			{
				case ALPHA, ERASE:
					__compositeAlphaErase(object, level, x0, y0, width, height, blendMode, displayObject);
				case INVERT:
					__compositeInvert(object, level, x0, y0, width, height);
				case SUBTRACT:
					__compositeSubtract(object, level, x0, y0, width, height);
				default:
					__compositeDirect(object, displayObject, x0, y0, width, height, blendMode);
			}

			if (uncovered != null)
			{
				context.globalCompositeOperation = "lighter";
				context.drawImage(uncovered, 0, 0, width, height, x0, y0, width, height);
			}
		}

		context.restore();
	}

	/**
		Works out the rectangle a group needs on the target: the object's bounds including filters,
		rounded out to whole pixels and clamped to the target, which inside a group is the enclosing
		group. Returns false if nothing of it is left.
	**/
	@:noCompletion private function __getGroupBounds(displayObject:DisplayObject, bounds:Rectangle):Bool
	{
		displayObject.__getFilterBounds(bounds, displayObject.__renderTransform);
		bounds.__transform(bounds, __worldTransform);

		var x0 = Math.floor(bounds.x), y0 = Math.floor(bounds.y);
		var x1 = Math.ceil(bounds.right), y1 = Math.ceil(bounds.bottom);

		var target:js.html.CanvasElement = context.canvas;

		if (x0 < 0) x0 = 0;
		if (y0 < 0) y0 = 0;
		if (x1 > target.width) x1 = target.width;
		if (y1 > target.height) y1 = target.height;

		bounds.setTo(x0, y0, x1 - x0, y1 - y0);
		return bounds.width > 0 && bounds.height > 0;
	}

	/**
		Returns the group canvas for this nesting level, with its drawing state reset and the area the
		group will use cleared.
	**/
	@:noCompletion private function __beginGroupCanvas(level:Int, width:Int, height:Int):js.html.CanvasElement
	{
		var canvas = __getGroupCanvas(level, width, height);
		var canvasContext = canvas.getContext2d();

		canvasContext.setTransform(1, 0, 0, 1, 0, 0);
		canvasContext.globalCompositeOperation = "source-over";
		canvasContext.globalAlpha = 1;
		canvasContext.clearRect(0, 0, width, height);

		return canvas;
	}

	/**
		Renders `displayObject` into a group canvas by pointing the renderer at that canvas for the
		duration. The world transform is shifted so that (x0, y0) of the target lands at the group's
		origin, which lets every object keep its usual render transform.

		The object's alpha is taken out of its children, because it is applied once to the whole group
		afterwards. In a LAYER group, and in the group of any other mode this renderer composites in a
		single draw (see `__compositeDirect`), children that only inherit the object's mode are drawn as
		NORMAL. In the groups of the remaining modes, every child is drawn as NORMAL. All renderer state
		is restored afterwards.
	**/
	@:noCompletion private function __renderIntoGroup(displayObject:DisplayObject, groupContext:js.html.CanvasRenderingContext2D, x0:Int, y0:Int,
			blendMode:BlendMode):Void
	{
		var layer = switch (blendMode)
		{
			case SUBTRACT, INVERT, ERASE, ALPHA: false;
			default: true;
		}
		__groupDepth++;
		if (layer) __layerDepth++; else __blendGroupDepth++;

		var cacheContext = context;
		var cacheWorldTransform = __worldTransform;
		var cacheOverrideBlendMode = __overrideBlendMode;
		var cacheGroupBlendMode = __groupBlendMode;
		var cacheWorldAlpha = __worldAlpha;
		// a LAYER tracks what its children touch, from the moment a child needs it (see __touch);
		// inside a formula group no further group opens, so nothing there reads the tracking
		var cacheTouchedRoot = __touchedRoot, cacheTouched = __touched, cacheTouchedActive = __touchedActive;
		__touchedRoot = layer ? displayObject : null;
		__touched = null;
		__touchedActive = false;

		var worldTransform = Matrix.__pool.get();
		worldTransform.copyFrom(__worldTransform);
		worldTransform.translate(-x0, -y0);

		__worldTransform = worldTransform;
		context = groupContext;

		// the object's alpha applies once, to the composite (see __renderGroup): divided out here
		__worldAlpha = 1 / displayObject.__worldAlpha;
		// the mode this group is composited with: children that only inherit it render NORMAL in a
		// LAYER-like group, every child renders NORMAL in a formula group, and shapes rendered
		// inside either know whether their coverage is wanted (__isCompositedWithAlpha)
		if (blendMode != LAYER) __groupBlendMode = blendMode;
		if (!layer) __overrideBlendMode = NORMAL;

		__blendMode = null;
		__setBlendMode(NORMAL);
		__renderDrawableDirect(displayObject);

		Matrix.__pool.release(worldTransform);

		__worldTransform = cacheWorldTransform;
		context = cacheContext;
		__worldAlpha = cacheWorldAlpha;
		__touchedRoot = cacheTouchedRoot;
		__touched = cacheTouched;
		__touchedActive = cacheTouchedActive;
		__overrideBlendMode = cacheOverrideBlendMode;
		__groupBlendMode = cacheGroupBlendMode;
		__blendMode = null;
		__groupDepth--;
		if (layer) __layerDepth--;
		else
			__blendGroupDepth--;
	}

	/**
		Draws a finished group onto the target as one image, with the object's alpha applied once to the
		whole of it. The composite operation of `blendMode` does the blending. This handles LAYER and
		every mode the canvas supports directly.
	**/
	@:noCompletion private function __compositeDirect(object:js.html.CanvasElement, displayObject:DisplayObject, x0:Int, y0:Int, width:Int, height:Int,
			blendMode:BlendMode):Void
	{
		__setBlendModeContext(context, blendMode); // LAYER: source-over
		context.globalAlpha = __getAlpha(displayObject.__worldAlpha);
		context.drawImage(object, 0, 0, width, height, x0, y0, width, height);
	}

	@:noCompletion private function __compositeAlphaErase(object:js.html.CanvasElement, level:Int, x0:Int, y0:Int, width:Int, height:Int,
			blendMode:BlendMode, displayObject:DisplayObject):Void
	{
		if (blendMode == ALPHA && __alphaNeedsMask(displayObject))
		{
			// Flash's ALPHA masks with what the object's leaves cover: a Bitmap its footprint,
			// transparent pixels included, a shape the fills and strokes of its graphics, and the
			// part of the object's box that no leaf covers keeps the backdrop. destination-in cuts
			// wherever the source is transparent, so the mask is 1 - coverage + alpha, built on the
			// coverage canvas with composite operations alone: opaque, the coverage taken out, the
			// object added (lighter clamps at 1)
			var mask = __getGroupCanvas(level + 3, width, height);
			var maskContext = mask.getContext2d();
			maskContext.setTransform(1, 0, 0, 1, 0, 0);
			maskContext.globalAlpha = 1;
			maskContext.globalCompositeOperation = "source-over";
			maskContext.clearRect(0, 0, width, height);
			maskContext.fillStyle = "#000000";
			maskContext.fillRect(0, 0, width, height);
			maskContext.globalCompositeOperation = "destination-out";
			__drawCoverage(maskContext, displayObject, x0, y0);
			maskContext.setTransform(1, 0, 0, 1, 0, 0);
			maskContext.globalCompositeOperation = "lighter";
			maskContext.drawImage(object, 0, 0, width, height, 0, 0, width, height);
			object = mask;
		}

		context.beginPath();
		context.rect(x0, y0, width, height);
		context.clip();
		context.globalCompositeOperation = (blendMode == ERASE) ? "destination-out" : "destination-in";
		context.drawImage(object, 0, 0, width, height, x0, y0, width, height);

		if (__backdropIsOpaque())
		{
			// Flash keeps the stage opaque: black behind the cut out pixels, not the page
			context.globalCompositeOperation = "destination-over";
			context.fillStyle = "#000000";
			context.fillRect(x0, y0, width, height);
		}
	}

	/**
		Paints the area covered by `displayObject` and all its descendants into `coverage`, a context
		whose origin sits at (x0, y0) of the target, using the composite operation currently set on it.

		For a shape, this is the area of its fills and strokes, taken from its coverage render, which
		is made now if the shape has none yet. For a text field, it is the alpha of its rendered text.
		For any other object without children, it is the object's bounding box. Every piece is placed
		with the same transform it is drawn with.
	**/
	@:noCompletion private function __drawCoverage(coverage:js.html.CanvasRenderingContext2D, displayObject:DisplayObject, x0:Int, y0:Int):Void
	{
		if (!displayObject.__renderable) return;
		var graphics = displayObject.__graphics;
		var bounds = Rectangle.__pool.get();
		var matrix = Matrix.__pool.get();

		if (graphics != null) __drawGraphicsCoverage(coverage, displayObject, x0, y0);

		if (displayObject.__children != null)
		{
			for (child in displayObject.__children) __drawCoverage(coverage, child, x0, y0);
		}
		else if (graphics == null)
		{
			displayObject.__getBounds(bounds, Matrix.__identity);
			matrix.copyFrom(displayObject.__renderTransform);
			__coverageRect(coverage, matrix, bounds, x0, y0);
		}

		Matrix.__pool.release(matrix);
		Rectangle.__pool.release(bounds);
	}

	/**
		Paints the area covered by the fills and strokes of the graphics of `displayObject` into
		`coverage`, placed with the same transform they are drawn with (see `__drawCoverage`).
	**/
	@:noCompletion private function __drawGraphicsCoverage(coverage:js.html.CanvasRenderingContext2D, displayObject:DisplayObject, x0:Int, y0:Int):Void
	{
		var graphics = displayObject.__graphics;
		var bounds = Rectangle.__pool.get();
		var matrix = Matrix.__pool.get();

		if (graphics.__managed)
		{
			// a text field draws straight into its canvas, in colors that are always opaque, so the
			// canvas's own alpha is its coverage: drawn where CanvasShape draws it
			if (graphics.__canvas != null)
			{
				matrix.scale(1 / graphics.__bitmapScaleX, 1 / graphics.__bitmapScaleY);
				matrix.concat(graphics.__worldTransform);
				__coverageRect(coverage, matrix, bounds, x0, y0, graphics);
			}
		}
		else
		{
			CanvasGraphics.render(graphics, this, true);
			if (graphics.__bounds != null)
			{
				bounds.copyFrom(graphics.__bounds);
				matrix.copyFrom(displayObject.__renderTransform);
				__coverageRect(coverage, matrix, bounds, x0, y0, graphics);
			}
		}

		Matrix.__pool.release(matrix);
		Rectangle.__pool.release(bounds);
	}

	/**
		Builds the current group's touched buffer if the group tracks one and it has not been built yet
		(see `__touch`): the coverage of everything drawn into the group before `displayObject`, which
		is about to be composited with a mode that reads it. From then on, every object drawn into the
		group adds itself as it is drawn. The buffer is a canvas the size of the group's, kept per
		layer depth.
	**/
	@:noCompletion private function __ensureTouched(displayObject:DisplayObject):Void
	{
		if (__touchedRoot == null || __touchedActive) return;

		var canvas = __touchedCanvases[__layerDepth];
		if (canvas == null)
		{
			canvas = js.Browser.document.createCanvasElement();
			__touchedCanvases[__layerDepth] = canvas;
		}
		var target:js.html.CanvasElement = context.canvas;
		if (canvas.width < target.width) canvas.width = target.width;
		if (canvas.height < target.height) canvas.height = target.height;
		var touchedContext = canvas.getContext2d();
		touchedContext.setTransform(1, 0, 0, 1, 0, 0);
		touchedContext.globalAlpha = 1;
		touchedContext.globalCompositeOperation = "source-over";
		touchedContext.clearRect(0, 0, canvas.width, canvas.height);

		__touched = canvas;
		__touchedActive = true;
		__walkTouched(__touchedRoot, displayObject);
	}

	@:noCompletion private override function __drawTouched(displayObject:DisplayObject, graphicsOnly:Bool):Void
	{
		var touchedContext = __touched.getContext2d();
		touchedContext.globalAlpha = 1;
		touchedContext.globalCompositeOperation = "source-over";
		touchedContext.fillStyle = "#000000";
		if (graphicsOnly) __drawGraphicsCoverage(touchedContext, displayObject, 0, 0);
		else __drawCoverage(touchedContext, displayObject, 0, 0);
	}

	/**
		Composites `object`, a group canvas, onto a transparent target with SUBTRACT or INVERT, pixel by
		pixel, over the rectangle (x0, y0, width, height) of the target.

		For every pixel, c is how much of it earlier objects have covered (the touched buffer, or all
		of it without one), and the backdrop is c of the covered part's color. The mode's formula is
		applied to that color, opaque where the object is opaque, and the result is mixed with the
		object as it is by c. Where the covered part is transparent, SUBTRACT gives black and INVERT
		white. The canvas gives and takes its pixels with straight alpha, so they are premultiplied
		on the way in and divided out on the way out.
	**/
	@:noCompletion private function __compositeFormulaPixels(object:js.html.CanvasElement, x0:Int, y0:Int, width:Int, height:Int, blendMode:BlendMode):Void
	{
		var target = context.getImageData(x0, y0, width, height);
		var source = object.getContext2d().getImageData(0, 0, width, height);
		var touched = __touchedActive ? __touched.getContext2d().getImageData(x0, y0, width, height) : null;
		var d = target.data, s = source.data;
		var t = touched != null ? touched.data : null;
		var invert = blendMode == INVERT;
		var i = 0, n = width * height * 4;

		while (i < n)
		{
			var sa = s[i + 3];
			var c = t != null ? t[i + 3] : 255;
			// where the object is transparent both formulas leave the backdrop as it is
			if (sa == 0) {}
			else if (c == 0)
			{
				d[i] = s[i];
				d[i + 1] = s[i + 1];
				d[i + 2] = s[i + 2];
				d[i + 3] = sa;
			}
			else
			{
				var da = d[i + 3];
				// premultiplied: the object, and the covered part's color, of which the backdrop is c
				var sr = Std.int(s[i] * sa / 255), sg = Std.int(s[i + 1] * sa / 255), sb = Std.int(s[i + 2] * sa / 255);
				var cr = Std.int(d[i] * da / c), cg = Std.int(d[i + 1] * da / c), cb = Std.int(d[i + 2] * da / c), ca = Std.int(da * 255 / c);
				if (cr > 255) cr = 255;
				if (cg > 255) cg = 255;
				if (cb > 255) cb = 255;
				if (ca > 255) ca = 255;
				var fr, fg, fb;
				if (invert)
				{
					fr = cr + Std.int(sa * (255 - 2 * cr) / 255);
					fg = cg + Std.int(sa * (255 - 2 * cg) / 255);
					fb = cb + Std.int(sa * (255 - 2 * cb) / 255);
				}
				else
				{
					fr = cr > sr ? cr - sr : 0;
					fg = cg > sg ? cg - sg : 0;
					fb = cb > sb ? cb - sb : 0;
				}
				var fa = sa + Std.int(ca * (255 - sa) / 255);
				// mixed with the object as it is by c, then with the alpha divided out again
				var oa = Std.int(((255 - c) * sa + c * fa + 127) / 255);
				if (oa > 0)
				{
					d[i] = Std.int((((255 - c) * sr + c * fr + 127) / 255) * 255 / oa);
					d[i + 1] = Std.int((((255 - c) * sg + c * fg + 127) / 255) * 255 / oa);
					d[i + 2] = Std.int((((255 - c) * sb + c * fb + 127) / 255) * 255 / oa);
				}
				else
				{
					d[i] = 0;
					d[i + 1] = 0;
					d[i + 2] = 0;
				}
				d[i + 3] = oa;
			}
			i += 4;
		}

		context.putImageData(target, x0, y0);
	}

	@:noCompletion private function __coverageRect(coverage:js.html.CanvasRenderingContext2D, matrix:Matrix, bounds:Rectangle, x0:Int, y0:Int,
			graphics:Graphics = null):Void
	{
		if (__worldTransform != null) matrix.concat(__worldTransform);
		if (__roundPixels)
		{
			matrix.tx = Math.round(matrix.tx);
			matrix.ty = Math.round(matrix.ty);
		}
		matrix.translate(-x0, -y0);
		coverage.setTransform(matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty);
		if (graphics != null && graphics.__managed)
		{
			coverage.drawImage(graphics.__canvas, 0, 0);
		}
		else if (graphics != null && graphics.__coverage != null)
		{
			// the coverage canvas holds the fills at the render scale, its origin at the bounds origin
			coverage.translate(bounds.x, bounds.y);
			coverage.scale(1 / graphics.__renderTransform.a, 1 / graphics.__renderTransform.d);
			coverage.drawImage(cast graphics.__coverage.image.src, 0, 0);
		}
		else
		{
			coverage.fillRect(bounds.x, bounds.y, bounds.width, bounds.height);
		}
	}

	@:noCompletion private function __compositeInvert(object:js.html.CanvasElement, level:Int, x0:Int, y0:Int, width:Int, height:Int):Void
	{
		// rendering the object left the last child's transform and alpha on the group context
		var objectContext = object.getContext2d();
		objectContext.setTransform(1, 0, 0, 1, 0, 0);
		objectContext.globalAlpha = 1;
		objectContext.globalCompositeOperation = "source-in";
		objectContext.fillStyle = "#FFFFFF";
		objectContext.fillRect(0, 0, width, height);

		if (__backdropIsOpaque())
		{
			// in place: nothing to preserve, no copy
			context.globalCompositeOperation = "difference";
			context.drawImage(object, 0, 0, width, height, x0, y0, width, height);
			return;
		}

		var backdropContext = __copyBackdrop(level, x0, y0, width, height);
		backdropContext.globalCompositeOperation = "difference";
		backdropContext.drawImage(object, 0, 0, width, height, 0, 0, width, height);

		context.globalCompositeOperation = "source-atop";
		context.drawImage(backdropContext.canvas, 0, 0, width, height, x0, y0, width, height);
	}

	@:noCompletion private function __compositeSubtract(object:js.html.CanvasElement, level:Int, x0:Int, y0:Int, width:Int, height:Int):Void
	{
		if (__backdropIsOpaque())
		{
			// in place: nothing to preserve, no copy
			context.fillStyle = "#FFFFFF";
			context.globalCompositeOperation = "difference";
			context.fillRect(x0, y0, width, height);
			context.globalCompositeOperation = "lighter";
			context.drawImage(object, 0, 0, width, height, x0, y0, width, height);
			context.globalCompositeOperation = "difference";
			context.fillRect(x0, y0, width, height);
			return;
		}

		var backdropContext = __copyBackdrop(level, x0, y0, width, height);
		backdropContext.fillStyle = "#FFFFFF";

		backdropContext.globalCompositeOperation = "difference";
		backdropContext.fillRect(0, 0, width, height);

		backdropContext.globalCompositeOperation = "lighter";
		backdropContext.drawImage(object, 0, 0, width, height, 0, 0, width, height);

		backdropContext.globalCompositeOperation = "difference";
		backdropContext.fillRect(0, 0, width, height);

		context.globalCompositeOperation = "source-atop";
		context.drawImage(backdropContext.canvas, 0, 0, width, height, x0, y0, width, height);
	}

	/**
		Whether the current target is fully opaque, so that a composite can work on it directly without
		having to preserve its alpha.

		That is the case when drawing straight onto an opaque stage, and when drawing into an opaque
		BitmapData with `BitmapData.draw`. It is not the case inside any group this renderer has opened,
		on a transparent stage, or while rendering the cache bitmap of an object with filters or
		cacheAsBitmap, whose renderer is given the stage as well but actually draws into a transparent
		bitmap.
	**/
	@:noCompletion private inline function __backdropIsOpaque():Bool
	{
		return __layerDepth == 0 && (__stage != null ? (!__stage.__transparent && __stage.__renderer == this) : !__transparent);
	}

	/**
		Copies the part of the target under the group into this level's backdrop canvas, and returns
		that canvas's context, ready for compositing.
	**/
	@:noCompletion private function __copyBackdrop(level:Int, x0:Int, y0:Int, width:Int, height:Int):js.html.CanvasRenderingContext2D
	{
		var backdropCanvas = __getGroupCanvas(level + 1, width, height);
		var backdropContext = backdropCanvas.getContext2d();
		backdropContext.setTransform(1, 0, 0, 1, 0, 0);
		backdropContext.globalAlpha = 1;
		// clearRect + source-over rather than the "copy" operation, which clears the whole canvas
		backdropContext.globalCompositeOperation = "source-over";
		backdropContext.clearRect(0, 0, width, height);
		backdropContext.drawImage(context.canvas, x0, y0, width, height, 0, 0, width, height);
		return backdropContext;
	}

	@:noCompletion private static function __getGroupCanvas(level:Int, width:Int, height:Int):js.html.CanvasElement
	{
		var canvas = __groupCanvases[level];

		if (canvas == null)
		{
			canvas = js.Browser.document.createCanvasElement();
			__groupCanvases[level] = canvas;
		}

		// grow only: a new size clears the canvas
		if (canvas.width < width) canvas.width = width;
		if (canvas.height < height) canvas.height = height;

		return canvas;
	}
	#end

	@:noCompletion private function __renderDrawableDirect(object:IBitmapDrawable):Void
	{
		switch (object.__drawableType)
		{
			case BITMAP_DATA:
				CanvasBitmapData.renderDrawable(cast object, this);
			case STAGE, SPRITE:
				CanvasDisplayObjectContainer.renderDrawable(cast object, this);
			case BITMAP:
				CanvasBitmap.renderDrawable(cast object, this);
			case SHAPE:
				CanvasDisplayObject.renderDrawable(cast object, this);
			case SIMPLE_BUTTON:
				CanvasSimpleButton.renderDrawable(cast object, this);
			case TEXT_FIELD:
				CanvasTextField.renderDrawable(cast object, this);
			case VIDEO:
				CanvasVideo.renderDrawable(cast object, this);
			case TILEMAP:
				CanvasTilemap.renderDrawable(cast object, this);
			default:
		}
	}

	@:noCompletion private function __renderDrawableMask(object:IBitmapDrawable):Void
	{
		if (object == null) return;

		switch (object.__drawableType)
		{
			case BITMAP_DATA:
				CanvasBitmapData.renderDrawableMask(cast object, this);
			case STAGE, SPRITE:
				CanvasDisplayObjectContainer.renderDrawableMask(cast object, this);
			case BITMAP:
				CanvasBitmap.renderDrawableMask(cast object, this);
			case SHAPE:
				CanvasDisplayObject.renderDrawableMask(cast object, this);
			case SIMPLE_BUTTON:
				CanvasSimpleButton.renderDrawableMask(cast object, this);
			case TEXT_FIELD:
				CanvasTextField.renderDrawableMask(cast object, this);
			case VIDEO:
				CanvasVideo.renderDrawableMask(cast object, this);
			case TILEMAP:
				CanvasTilemap.renderDrawableMask(cast object, this);
			default:
		}
	}

	@:noCompletion private override function __setBlendMode(value:BlendMode, force:Bool = false):Void
	{
		if (__overrideBlendMode != null) value = __overrideBlendMode;
		if (value == __groupBlendMode) value = NORMAL;
		if (!force && __blendMode == value) return;

		__blendMode = value;
		__setBlendModeContext(context, value);
	}

	@SuppressWarnings("checkstyle:Dynamic")
	@:noCompletion private function __setBlendModeContext(context:#if lime Canvas2DRenderContext #else Dynamic #end, value:BlendMode):Void
	{
		switch (value)
		{
			//NOTE: ALPHA, ERASE, INVERT, SUBTRACT and LAYER are composed by __renderGroup

			case ADD:
				context.globalCompositeOperation = "lighter";

			case DARKEN:
				context.globalCompositeOperation = "darken";

			case DIFFERENCE:
				context.globalCompositeOperation = "difference";

			case HARDLIGHT:
				context.globalCompositeOperation = "hard-light";

			case LIGHTEN:
				context.globalCompositeOperation = "lighten";

			case MULTIPLY:
				context.globalCompositeOperation = "multiply";

			case OVERLAY:
				context.globalCompositeOperation = "overlay";

			case SCREEN:
				context.globalCompositeOperation = "screen";

			// case SHADER:

			// context.globalCompositeOperation = "";

			default:
				context.globalCompositeOperation = "source-over";
		}
	}
}
#else
typedef CanvasRenderer = Dynamic;
#end

