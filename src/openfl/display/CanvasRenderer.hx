package openfl.display;

#if !flash
import openfl.display._internal.CanvasBitmap;
import openfl.display._internal.CanvasBitmapData;
import openfl.display._internal.CanvasDisplayObject;
import openfl.display._internal.CanvasDisplayObjectContainer;
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
				__markDrawn(displayObject);
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
						__markDrawn(displayObject);
						return;
					default:
						if (__needsContainerGroup(displayObject, blendMode))
						{
							__renderGroup(displayObject, blendMode);
							__markDrawn(displayObject);
							return;
						}
				}
			}
		}
		#end

		__renderDrawableDirect(object);
		#if (js && html5)
		if (object.__drawableType != BITMAP_DATA) __markDrawn(cast object);
		#end
	}

	/**
		Flash blends an object as a whole: a container of several pieces under one of the
		operator modes would otherwise have each child blended on its own (a child over a
		sibling adds twice). Such a container is rendered into a group first, children
		that only inherit its mode drawing NORMAL, and the group is composited with the
		mode. A shape is already one piece here: its graphics are rendered to a surface
		before drawing.
	**/
	@:noCompletion private function __needsContainerGroup(displayObject:DisplayObject, blendMode:BlendMode):Bool
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
		Renders `displayObject` into a group canvas covering its bounds and composes it onto
		the current context: LAYER and the operator modes as one drawImage of the group with
		the mode's composite operation, ERASE and ALPHA through
		destination-out / destination-in (unbounded operations, so clipped to the bounds),
		INVERT and SUBTRACT in place on the opaque stage or else on a copy of the backdrop
		that goes back with source-atop, keeping the backdrop alpha.
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

		// the object's alpha applies once, to the whole object: __compositeLayer (LAYER and the
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

		// where nothing has been drawn into the target yet Flash draws the object as it is,
		// under every mode (see __markDrawn). None of the composites below does that, so the
		// object is kept outside the drawn rectangle and added back after the composite.
		// Inside it, over a backdrop a mask left transparent, the composites give what Flash
		// gives: nothing for ALPHA and ERASE, and for SUBTRACT and INVERT a black or white
		// silhouette of the object, drawn under the result
		var drawn = Rectangle.__pool.get();
		var drawnAll = __drawnWithin(x0, y0, width, height, drawn);
		var uncovered:js.html.CanvasElement = null;
		if (formulaMode && (!drawnAll || drawn.width < width || drawn.height < height))
		{
			uncovered = __getGroupCanvas(level + 2, width, height);
			var uncoveredContext = uncovered.getContext2d();
			uncoveredContext.setTransform(1, 0, 0, 1, 0, 0);
			uncoveredContext.globalAlpha = 1;
			uncoveredContext.globalCompositeOperation = "copy";
			uncoveredContext.drawImage(object, 0, 0, width, height, 0, 0, width, height);
			if (drawnAll)
			{
				uncoveredContext.globalCompositeOperation = "destination-out";
				uncoveredContext.fillRect(drawn.x - x0, drawn.y - y0, drawn.width, drawn.height);
			}
		}

		// compose the group onto the target. No clip here: an advanced blend mode under a
		// clip takes a slow path on the accelerated canvas, and every composite except
		// ALPHA / ERASE is bounded by what it draws
		context.save();
		context.setTransform(1, 0, 0, 1, 0, 0);
		context.globalAlpha = 1;

		switch (blendMode)
		{
			case ALPHA, ERASE:
				__compositeAlphaErase(object, level, x0, y0, width, height, blendMode, displayObject);
			case INVERT:
				__compositeInvert(object, level, x0, y0, width, height);
			case SUBTRACT:
				__compositeSubtract(object, level, x0, y0, width, height);
			default:
				__compositeLayer(object, displayObject, x0, y0, width, height, blendMode);
		}

		if (uncovered != null)
		{
			context.globalCompositeOperation = "lighter";
			context.drawImage(uncovered, 0, 0, width, height, x0, y0, width, height);
		}

		if (drawnAll && (blendMode == SUBTRACT || blendMode == INVERT) && !__backdropIsOpaque())
		{
			var silhouette = __getGroupCanvas(level + 2, width, height);
			var silhouetteContext = silhouette.getContext2d();
			silhouetteContext.setTransform(1, 0, 0, 1, 0, 0);
			silhouetteContext.globalAlpha = 1;
			silhouetteContext.globalCompositeOperation = "copy";
			silhouetteContext.drawImage(object, 0, 0, width, height, 0, 0, width, height);
			silhouetteContext.globalCompositeOperation = "source-in";
			silhouetteContext.fillStyle = (blendMode == SUBTRACT) ? "#000000" : "#FFFFFF";
			silhouetteContext.fillRect(0, 0, width, height);
			context.save();
			context.beginPath();
			context.rect(drawn.x, drawn.y, drawn.width, drawn.height);
			context.clip();
			context.globalCompositeOperation = "destination-over";
			context.drawImage(silhouette, 0, 0, width, height, x0, y0, width, height);
			context.restore();
		}
		Rectangle.__pool.release(drawn);

		context.restore();
	}

	/**
		The group's rectangle in target pixels: the object's bounds including filters,
		rounded outward to whole pixels and clamped to the target. Returns false when
		nothing is left.
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
		The level's group canvas with default state and the group's area cleared.
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
		Renders the object into the group with the renderer redirected to it: the
		world transform moves the group origin to (x0, y0) so objects keep their render
		transforms. Inside a LAYER, or a container group of an operator mode, the object's
		alpha is divided out of the children (it applies once, on the composite) and
		children that only inherit the object's mode render NORMAL; inside the other groups
		the children's blend modes are forced to NORMAL. Every piece of renderer state is
		put back afterwards.
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
		// a LAYER tracks what its children draw; nothing can read the bounds inside a formula group
		var cacheDrawnBounds = __drawnBounds;
		__drawnBounds = layer ? Rectangle.__pool.get() : null;
		if (layer) __drawnBounds.setTo(0, 0, 0, 0);

		var worldTransform = Matrix.__pool.get();
		worldTransform.copyFrom(__worldTransform);
		worldTransform.translate(-x0, -y0);

		__worldTransform = worldTransform;
		context = groupContext;

		// the object's alpha applies once, to the composite (see __renderGroup): divided out here
		__worldAlpha = 1 / displayObject.__worldAlpha;
		// the mode this group is composited with: children that only inherit it render NORMAL in a
		// LAYER-like group, every child renders NORMAL in a formula group, and shapes rendered
		// inside either know whether their coverage is wanted (__wantsCoverage)
		if (blendMode != LAYER) __groupBlendMode = blendMode;
		if (!layer) __overrideBlendMode = NORMAL;

		__blendMode = null;
		__setBlendMode(NORMAL);
		__renderDrawableDirect(displayObject);

		Matrix.__pool.release(worldTransform);

		__worldTransform = cacheWorldTransform;
		context = cacheContext;
		__worldAlpha = cacheWorldAlpha;
		if (layer) Rectangle.__pool.release(__drawnBounds);
		__drawnBounds = cacheDrawnBounds;
		__overrideBlendMode = cacheOverrideBlendMode;
		__groupBlendMode = cacheGroupBlendMode;
		__blendMode = null;
		__groupDepth--;
		if (layer) __layerDepth--;
		else
			__blendGroupDepth--;
	}

	/**
		LAYER: the group goes on as one object with the layer's alpha.
	**/
	@:noCompletion private function __compositeLayer(object:js.html.CanvasElement, displayObject:DisplayObject, x0:Int, y0:Int, width:Int, height:Int,
			blendMode:BlendMode):Void
	{
		__setBlendModeContext(context, blendMode); // LAYER: source-over
		context.globalAlpha = __getAlpha(displayObject.__worldAlpha);
		context.drawImage(object, 0, 0, width, height, x0, y0, width, height);
	}

	@:noCompletion private function __compositeAlphaErase(object:js.html.CanvasElement, level:Int, x0:Int, y0:Int, width:Int, height:Int,
			blendMode:BlendMode, displayObject:DisplayObject):Void
	{
		if (blendMode == ALPHA && __alphaNeedsCoverage(displayObject))
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
		Fills what `displayObject` and its descendants cover into `coverage`, a context whose origin
		is at (x0, y0) of the target, with its current composite operation: a shape the fills and
		strokes of its graphics (their bounds when they have no coverage render), any other leaf
		its local bounds, each under the transform it is drawn with.
	**/
	@:noCompletion private function __drawCoverage(coverage:js.html.CanvasRenderingContext2D, displayObject:DisplayObject, x0:Int, y0:Int):Void
	{
		if (!displayObject.__renderable) return;
		var graphics = displayObject.__graphics;
		var bounds = Rectangle.__pool.get();
		var matrix = Matrix.__pool.get();

		if (graphics != null && graphics.__bounds != null)
		{
			bounds.copyFrom(graphics.__bounds);
			matrix.copyFrom(displayObject.__renderTransform);
			__coverageRect(coverage, matrix, bounds, x0, y0, graphics);
		}

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
		if (graphics != null && graphics.__coverage != null)
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
		True when the current target is the opaque stage itself: not a LAYER group, a
		transparent stage, a bitmap, or the cache bitmap of a filtered or cacheAsBitmap object
		(its renderer is given the stage too, but draws into a transparent bitmap). Without a
		stage, the target is a BitmapData and __transparent says whether it is opaque. The composites can then work in place, since
		there is no backdrop alpha to preserve, which saves the copy and the way back.
	**/
	@:noCompletion private inline function __backdropIsOpaque():Bool
	{
		return __layerDepth == 0 && (__stage != null ? (!__stage.__transparent && __stage.__renderer == this) : !__transparent);
	}

	/**
		Copies the group's region of the current target into the level's backdrop
		canvas and returns that canvas' context, ready for compositing.
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

