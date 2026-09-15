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
	// group canvases per nesting level, shared by every renderer. Browsers keep canvases below
	// about 128x128 pixels in CPU memory and accelerate larger ones: drawing from a small
	// canvas after modifying it costs a few microseconds, from an accelerated one about 80
	// plus its area (it waits for the GPU), and onto an accelerated target the small source
	// costs by its own area. So objects up to 120 pixels get a canvas of about their size
	// (16 pixel steps, at most 64 per level), larger objects share one canvas that grows
	@:noCompletion private static var __groupCanvases:Array<Array<js.html.CanvasElement>> = [];
	@:noCompletion private static inline var SMALL_GROUP_CANVAS = 120;
	@:noCompletion private static inline var SMALL_GROUP_STEP = 16;
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
		__renderDrawable(object);
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
			if (displayObject.__blendMode == LAYER && __blendGroupDepth == 0)
			{
				__renderGroup(displayObject, LAYER);
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
						return;
					default:
						if (__needsContainerGroup(displayObject, blendMode))
						{
							__renderGroup(displayObject, blendMode);
							return;
						}
				}
			}
		}
		#end

		__renderDrawableDirect(object);
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
		INVERT and SUBTRACT in place on the opaque stage or else as pixel loops on the
		region, keeping the backdrop alpha.
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

		var level = __groupDepth;
		var object = __beginGroupCanvas(level, width, height);
		__renderIntoGroup(displayObject, object.getContext2d(), x0, y0, blendMode);

		// compose the group onto the target. No clip here: an advanced blend mode under a
		// clip takes a slow path on the accelerated canvas, and every composite except
		// ALPHA / ERASE is bounded by what it draws
		context.save();
		context.setTransform(1, 0, 0, 1, 0, 0);
		context.globalAlpha = 1;

		switch (blendMode)
		{
			case ALPHA, ERASE:
				__compositeAlphaErase(object, x0, y0, width, height, blendMode);
			case INVERT:
				__compositeInvert(object, x0, y0, width, height);
			case SUBTRACT:
				__compositeSubtract(object, x0, y0, width, height);
			default:
				__compositeLayer(object, displayObject, x0, y0, width, height, blendMode);
		}

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

		var worldTransform = Matrix.__pool.get();
		worldTransform.copyFrom(__worldTransform);
		worldTransform.translate(-x0, -y0);

		__worldTransform = worldTransform;
		context = groupContext;

		if (layer)
		{
			__worldAlpha = 1 / displayObject.__worldAlpha;
			if (blendMode != LAYER) __groupBlendMode = blendMode;
		}
		else
		{
			__overrideBlendMode = NORMAL;
		}

		__blendMode = null;
		__setBlendMode(NORMAL);
		__renderDrawableDirect(displayObject);

		Matrix.__pool.release(worldTransform);

		__worldTransform = cacheWorldTransform;
		context = cacheContext;
		__worldAlpha = cacheWorldAlpha;
		__overrideBlendMode = cacheOverrideBlendMode;
		__groupBlendMode = cacheGroupBlendMode;
		__blendMode = null;
		__groupDepth--;
		if (layer) __layerDepth--; else __blendGroupDepth--;
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

	/**
		ALPHA and ERASE: destination-in / destination-out through the object. Both
		operations are unbounded (they touch the whole canvas), hence the clip to the
		group's bounds. Inside a LAYER group that cuts the layer; on the opaque stage
		the cut out pixels go black, as in Flash.
	**/
	@:noCompletion private function __compositeAlphaErase(object:js.html.CanvasElement, x0:Int, y0:Int, width:Int, height:Int, blendMode:BlendMode):Void
	{
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
		INVERT: (1 - a) * x + a * (1 - x) per channel through the object's alpha a, the
		backdrop keeps its own alpha. On the opaque stage that is a white silhouette of
		the object (source-in) drawn with difference. Elsewhere the backdrop may be
		transparent, and drawing the target canvas into another canvas costs a snapshot of
		its whole area, so the region is read back and computed directly instead.
	**/
	@:noCompletion private function __compositeInvert(object:js.html.CanvasElement, x0:Int, y0:Int, width:Int, height:Int):Void
	{
		if (__backdropIsOpaque())
		{
			var objectContext = object.getContext2d();
			objectContext.globalCompositeOperation = "source-in";
			objectContext.fillStyle = "#FFFFFF";
			objectContext.fillRect(0, 0, width, height);

			context.globalCompositeOperation = "difference";
			context.drawImage(object, 0, 0, width, height, x0, y0, width, height);
			return;
		}

		var backdrop = context.getImageData(x0, y0, width, height);
		var d = backdrop.data;
		var o = object.getContext2d().getImageData(0, 0, width, height).data;
		var n = width * height * 4;
		var i = 0;

		while (i < n)
		{
			var a = o[i + 3] / 255;
			if (a > 0)
			{
				d[i] = __clampByte(d[i] + (255 - 2 * d[i]) * a);
				d[i + 1] = __clampByte(d[i + 1] + (255 - 2 * d[i + 1]) * a);
				d[i + 2] = __clampByte(d[i + 2] + (255 - 2 * d[i + 2]) * a);
			}
			i += 4;
		}

		context.putImageData(backdrop, x0, y0);
	}

	/**
		SUBTRACT: max(0, x - p) with the premultiplied object p, the backdrop keeps its
		own alpha. Canvas has no subtract operation: on the opaque stage it is built in
		place as invert(invert(x) + p), a white difference, lighter with the object, a
		white difference. Elsewhere the backdrop may be transparent, and drawing the
		target canvas into another canvas costs a snapshot of its whole area, so the
		region is read back and computed directly instead.
	**/
	@:noCompletion private function __compositeSubtract(object:js.html.CanvasElement, x0:Int, y0:Int, width:Int, height:Int):Void
	{
		if (__backdropIsOpaque())
		{
			context.fillStyle = "#FFFFFF";
			context.globalCompositeOperation = "difference";
			context.fillRect(x0, y0, width, height);
			context.globalCompositeOperation = "lighter";
			context.drawImage(object, 0, 0, width, height, x0, y0, width, height);
			context.globalCompositeOperation = "difference";
			context.fillRect(x0, y0, width, height);
			return;
		}

		var backdrop = context.getImageData(x0, y0, width, height);
		var d = backdrop.data;
		var o = object.getContext2d().getImageData(0, 0, width, height).data;
		var n = width * height * 4;
		var i = 0;

		while (i < n)
		{
			var da = d[i + 3];
			var sa = o[i + 3];
			if (da > 0 && sa > 0)
			{
				// straight colours: (x * da - s * sa) / da = x - s * sa / da
				var k = sa / da;
				d[i] = __clampByte(d[i] - o[i] * k);
				d[i + 1] = __clampByte(d[i + 1] - o[i + 1] * k);
				d[i + 2] = __clampByte(d[i + 2] - o[i + 2] * k);
			}
			i += 4;
		}

		context.putImageData(backdrop, x0, y0);
	}

	@:noCompletion private static inline function __clampByte(value:Float):Int
	{
		return value <= 0 ? 0 : (value >= 255 ? 255 : Std.int(value + 0.5));
	}

	/**
		True when the current target is the opaque stage itself: not a LAYER group, a
		transparent stage or a bitmap. The composites can then work in place, since
		there is no backdrop alpha to preserve, which saves the copy and the way back.
	**/
	@:noCompletion private inline function __backdropIsOpaque():Bool
	{
		return __layerDepth == 0 && __stage != null && !__stage.__transparent;
	}

	@:noCompletion private static function __getGroupCanvas(level:Int, width:Int, height:Int):js.html.CanvasElement
	{
		var canvases = __groupCanvases[level];
		if (canvases == null) __groupCanvases[level] = canvases = [];

		// index 0: the large canvas; then one per (width, height) step for small objects
		var index = 0, stepsX = 0, stepsY = 0;
		if (width <= SMALL_GROUP_CANVAS && height <= SMALL_GROUP_CANVAS)
		{
			stepsX = Math.ceil(width / SMALL_GROUP_STEP);
			stepsY = Math.ceil(height / SMALL_GROUP_STEP);
			index = 1 + (stepsX - 1) * Math.ceil(SMALL_GROUP_CANVAS / SMALL_GROUP_STEP) + (stepsY - 1);
		}

		var canvas = canvases[index];
		if (canvas == null)
		{
			canvas = js.Browser.document.createCanvasElement();
			if (index > 0)
			{
				canvas.width = stepsX * SMALL_GROUP_STEP;
				canvas.height = stepsY * SMALL_GROUP_STEP;
			}
			canvases[index] = canvas;
		}

		if (index == 0)
		{
			// grow only: a new size clears the canvas
			if (canvas.width < width) canvas.width = width;
			if (canvas.height < height) canvas.height = height;
		}

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

	@:noCompletion private override function __setBlendMode(value:BlendMode):Void
	{
		if (__overrideBlendMode != null) value = __overrideBlendMode;
		if (value == __groupBlendMode) value = NORMAL;
		if (__blendMode == value) return;

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
