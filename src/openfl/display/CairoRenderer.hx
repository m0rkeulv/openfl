package openfl.display;

#if !flash
import openfl.display._internal.CairoBitmap;
import openfl.display._internal.CairoBitmapData;
import openfl.display._internal.CairoDisplayObject;
import openfl.display._internal.CairoDisplayObjectContainer;
import openfl.display._internal.CairoGraphics;
import openfl.display._internal.CairoShape;
import openfl.display._internal.CairoSimpleButton;
import openfl.display._internal.CairoTextField;
import openfl.display._internal.CairoTilemap;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
#if lime
import lime.graphics.cairo.Cairo;
import lime.graphics.cairo.CairoContent;
import lime.graphics.cairo.CairoOperator;
import lime.graphics.cairo.CairoPattern;
import lime.graphics.cairo.CairoSurface;
import lime.graphics.CairoRenderContext;
import lime.math.Matrix3;
#end

/**
	**BETA**

	The CairoRenderer API exposes support for native Cairo render instructions within the
	`RenderEvent.RENDER_CAIRO` event
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.display.DisplayObject)
@:access(openfl.display.Graphics)
@:access(openfl.display.IBitmapDrawable)
@:access(openfl.display.Stage)
@:access(openfl.display.Stage3D)
@:allow(openfl.display._internal)
@:allow(openfl.display)
@:access(openfl.geom.Rectangle)
class CairoRenderer extends DisplayObjectRenderer
{
	/**
		The current Cairo render context
	**/
	@SuppressWarnings("checkstyle:Dynamic")
	public var cairo:#if lime CairoRenderContext #else Dynamic #end;

	@:noCompletion private var __matrix:Matrix;
	@SuppressWarnings("checkstyle:Dynamic") @:noCompletion private var __matrix3:#if lime Matrix3 #else Dynamic #end;

	@SuppressWarnings("checkstyle:Dynamic")
	@:noCompletion private function new(cairo:#if lime Cairo #else Dynamic #end)
	{
		super();

		#if lime_cairo
		this.cairo = cairo;

		__matrix = new Matrix();
		__matrix3 = new Matrix3();

		__type = CAIRO;
		#end
	}

	/**
		Set the matrix value for the current render context, or (optionally) another Cairo
		object
	**/
	@SuppressWarnings("checkstyle:Dynamic")
	public function applyMatrix(transform:Matrix, cairo:#if lime Cairo #else Dynamic #end = null):Void
	{
		if (cairo == null) cairo = this.cairo;

		__matrix.copyFrom(transform);

		if (this.cairo == cairo && __worldTransform != null)
		{
			__matrix.concat(__worldTransform);
		}

		__matrix3.a = __matrix.a;
		__matrix3.b = __matrix.b;
		__matrix3.c = __matrix.c;
		__matrix3.d = __matrix.d;

		if (__roundPixels)
		{
			__matrix3.tx = Math.round(__matrix.tx);
			__matrix3.ty = Math.round(__matrix.ty);
		}
		else
		{
			__matrix3.tx = __matrix.tx;
			__matrix3.ty = __matrix.ty;
		}

		cairo.matrix = __matrix3;
	}

	@:noCompletion private override function __clear():Void
	{
		if (cairo == null) return;

		cairo.identityMatrix();

		if (__stage != null && __stage.__clearBeforeRender)
		{
			var cacheBlendMode = __blendMode;
			__setBlendMode(NORMAL);

			cairo.setSourceRGB(__stage.__colorSplit[0], __stage.__colorSplit[1], __stage.__colorSplit[2]);
			cairo.paint();

			__setBlendMode(cacheBlendMode);
		}
	}

	@:noCompletion private override function __popMask():Void
	{
		cairo.restore();
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
		cairo.restore();
	}

	@:noCompletion private override function __pushMask(mask:DisplayObject):Void
	{
		cairo.save();

		applyMatrix(mask.__renderTransform, cairo);

		cairo.newPath();
		__renderDrawableMask(mask);
		cairo.clip();
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
		cairo.save();

		applyMatrix(transform, cairo);

		cairo.newPath();
		cairo.rectangle(rect.x, rect.y, rect.width, rect.height);
		cairo.clip();
	}

	@:noCompletion private override function __render(object:IBitmapDrawable):Void
	{
		if (cairo == null) return;

		__renderDrawable(object);
	}

	@:noCompletion private function __renderDrawable(object:IBitmapDrawable):Void
	{
		if (object == null) return;

		#if lime
		if (object.__drawableType != BITMAP_DATA)
		{
			var displayObject:DisplayObject = cast object;
			// a LAYER container is rendered into its own group, so ERASE and ALPHA
			// children only affect what is inside it, as in Flash
			if (displayObject.__blendMode == LAYER && __blendGroupDepth == 0)
			{
				__renderLayerGroup(object);
				return;
			}
			// SUBTRACT and INVERT have no Cairo operator, ERASE and ALPHA need a
			// clip: the object is rendered into a group and composited afterwards
			if (__blendGroupDepth == 0)
			{
				var blendMode = __overrideBlendMode != null ? __overrideBlendMode : displayObject.__worldBlendMode;
				if (blendMode == __groupBlendMode) blendMode = NORMAL;
				if (blendMode == SUBTRACT || blendMode == INVERT || blendMode == ALPHA || blendMode == ERASE)
				{
					__renderBlendGroup(object, blendMode);
					return;
				}
				if (__needsContainerGroup(displayObject, blendMode))
				{
					__renderOperatorGroup(object, blendMode);
					return;
				}
			}
		}
		#end

		__renderDrawableDirect(object);
	}

	/**
		Flash blends an object as a whole. If a container with several children were drawn
		child by child under one of the operator modes, the mode would apply to each child
		separately, and where a child overlaps a sibling it would be blended twice. So such a
		container is first rendered into a group, with children that only inherit its mode
		drawing as NORMAL, and the finished group is then composited with the mode once.
		A shape needs none of this: its graphics are rendered to a surface before drawing,
		so it is already a single piece.
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

	@:noCompletion private function __renderOperatorGroup(object:IBitmapDrawable, blendMode:BlendMode):Void
	{
		#if lime
		var previousGroupBlendMode = __groupBlendMode;
		__layerDepth++;

		cairo.save();
		cairo.identityMatrix();

		// clip to the container's bounds: the group is then allocated at that size
		var displayObject:DisplayObject = cast object;
		var bounds = Rectangle.__pool.get();
		displayObject.__getFilterBounds(bounds, displayObject.__renderTransform);
		if (__worldTransform != null) bounds.__transform(bounds, __worldTransform);
		var x0 = Math.floor(bounds.x), y0 = Math.floor(bounds.y);
		cairo.rectangle(x0, y0, Math.ceil(bounds.right) - x0, Math.ceil(bounds.bottom) - y0);
		cairo.clip();
		Rectangle.__pool.release(bounds);

		cairo.pushGroupWithContent(CairoContent.COLOR_ALPHA);
		__groupBlendMode = blendMode;
		__blendMode = null;
		__renderDrawableDirect(object);
		__groupBlendMode = previousGroupBlendMode;

		cairo.identityMatrix();
		cairo.popGroupToSource();
		__setBlendModeCairo(cairo, blendMode);
		cairo.paint();

		cairo.restore();
		__blendMode = null; // the operator is set again by the next __setBlendMode
		__layerDepth--;
		#end
	}

	#if lime
	@:noCompletion private var __blendGroupDepth:Int = 0;
	@:noCompletion private var __layerDepth:Int = 0;

	/** Renders a LAYER container into a group and composites it with OVER. **/
	@:noCompletion private function __renderLayerGroup(object:IBitmapDrawable):Void
	{
		__layerDepth++;
		cairo.save();
		cairo.identityMatrix();
		cairo.pushGroupWithContent(CairoContent.COLOR_ALPHA);
		__blendMode = null;
		__renderDrawableDirect(object);
		cairo.identityMatrix();
		cairo.popGroupToSource();
		cairo.setOperator(CairoOperator.OVER);
		cairo.paint();
		cairo.restore();
		__blendMode = null;
		__layerDepth--;
	}

	/**
		Renders `object` alone into a Cairo group and composites the group with
		the destination, see the __composite functions for each mode.
	**/
	@:noCompletion private function __renderBlendGroup(object:IBitmapDrawable, blendMode:BlendMode):Void
	{
		var previousOverride = __overrideBlendMode;
		__blendGroupDepth++;

		// the surface being drawn on right now: the window, the bitmap, or the
		// enclosing LAYER group
		var destination = cairo.groupTarget;

		cairo.save();
		cairo.identityMatrix();

		// clip to the object's bounds first: the group and the destination copies are then
		// allocated and painted at that size instead of the whole surface, and DEST_IN
		// (ALPHA), which is unbounded, cannot reach outside it
		var displayObject:DisplayObject = cast object;
		var bounds = Rectangle.__pool.get();
		displayObject.__getFilterBounds(bounds, displayObject.__renderTransform);
		if (__worldTransform != null) bounds.__transform(bounds, __worldTransform);
		// whole pixels, exactly covering the bounds: DEST_IN cuts everything inside the clip
		var x0 = Math.floor(bounds.x), y0 = Math.floor(bounds.y);
		cairo.rectangle(x0, y0, Math.ceil(bounds.right) - x0, Math.ceil(bounds.bottom) - y0);
		cairo.clip();
		Rectangle.__pool.release(bounds);

		cairo.pushGroupWithContent(CairoContent.COLOR_ALPHA);
		if (blendMode == SUBTRACT) __prepareSubtract();

		// the object and its children draw normally inside the group
		__overrideBlendMode = NORMAL;
		__blendMode = null;
		__renderDrawableDirect(object);
		__overrideBlendMode = previousOverride;

		cairo.identityMatrix();
		var objectPattern = cairo.popGroup();

		switch (blendMode)
		{
			case ALPHA, ERASE:
				__compositeAlphaErase(objectPattern, blendMode);
			case INVERT:
				__compositeInvert(destination, objectPattern);
			case SUBTRACT:
				__compositeSubtract(destination, objectPattern);
			default:
		}

		cairo.restore();
		__blendMode = null; // the operator is set again by the next __setBlendMode
		__blendGroupDepth--;
	}

	@:noCompletion private function __compositeAlphaErase(objectPattern:CairoPattern, blendMode:BlendMode):Void
	{
		cairo.source = objectPattern;
		cairo.setOperator(blendMode == ERASE ? CairoOperator.DEST_OUT : CairoOperator.DEST_IN);
		cairo.paint();

		if (__backdropIsOpaque())
		{
			// Flash keeps the stage opaque: black behind the cut out pixels
			cairo.setSourceRGB(0, 0, 0);
			cairo.setOperator(CairoOperator.DEST_OVER);
			cairo.paint();
		}
	}

	@:noCompletion private function __compositeInvert(destination:CairoSurface, objectPattern:CairoPattern):Void
	{
		if (__backdropIsOpaque())
		{
			// in place: nothing to preserve, no copy
			cairo.setSourceRGB(1, 1, 1);
			cairo.setOperator(CairoOperator.DIFFERENCE);
			cairo.mask(objectPattern);
			return;
		}

		cairo.pushGroupWithContent(CairoContent.COLOR_ALPHA);
		cairo.setSourceSurface(destination, 0, 0);
		cairo.setOperator(CairoOperator.SOURCE);
		cairo.paint();

		cairo.setSourceRGB(1, 1, 1);
		cairo.setOperator(CairoOperator.DIFFERENCE);
		cairo.mask(objectPattern);

		cairo.popGroupToSource();
		cairo.setOperator(CairoOperator.ATOP);
		cairo.paint();
	}

	@:noCompletion private function __prepareSubtract():Void
	{
		cairo.setSourceRGB(0, 0, 0);
		cairo.setOperator(CairoOperator.SOURCE);
		cairo.paint();
	}

	@:noCompletion private function __compositeSubtract(destination:CairoSurface, objectPattern:CairoPattern):Void
	{
		if (__backdropIsOpaque())
		{
			// in place: nothing to preserve, no copy
			cairo.source = objectPattern;
			cairo.setOperator(CairoOperator.LIGHTEN);
			cairo.paint();
			cairo.setOperator(CairoOperator.DIFFERENCE);
			cairo.paint();
			return;
		}

		cairo.pushGroupWithContent(CairoContent.COLOR_ALPHA);
		cairo.setSourceSurface(destination, 0, 0);
		cairo.setOperator(CairoOperator.SOURCE);
		cairo.paint();

		cairo.source = objectPattern;
		cairo.setOperator(CairoOperator.LIGHTEN);
		cairo.paint();
		cairo.setOperator(CairoOperator.DIFFERENCE);
		cairo.paint();

		cairo.popGroupToSource();
		cairo.setOperator(CairoOperator.ATOP);
		cairo.paint();
	}

	/**
		True when the current target is the opaque stage surface itself: not a LAYER
		group, a transparent stage or a bitmap. The composites can then work in place,
		since there is no destination alpha to preserve.
	**/
	@:noCompletion private inline function __backdropIsOpaque():Bool
	{
		return __layerDepth == 0 && __stage != null && !__stage.__transparent;
	}
	#end

	@:noCompletion private function __renderDrawableDirect(object:IBitmapDrawable):Void
	{
		switch (object.__drawableType)
		{
			case BITMAP_DATA:
				CairoBitmapData.renderDrawable(cast object, this);
			case STAGE, SPRITE:
				CairoDisplayObjectContainer.renderDrawable(cast object, this);
			case BITMAP:
				CairoBitmap.renderDrawable(cast object, this);
			case SHAPE:
				CairoDisplayObject.renderDrawable(cast object, this);
			case SIMPLE_BUTTON:
				CairoSimpleButton.renderDrawable(cast object, this);
			case TEXT_FIELD:
				CairoTextField.renderDrawable(cast object, this);
			case VIDEO:
				// TODO
			case TILEMAP:
				CairoTilemap.renderDrawable(cast object, this);
			default:
		}
	}

	@:noCompletion private function __renderDrawableMask(object:IBitmapDrawable):Void
	{
		if (object == null) return;

		switch (object.__drawableType)
		{
			case BITMAP_DATA:
				CairoBitmapData.renderDrawableMask(cast object, this);
			case STAGE, SPRITE:
				CairoDisplayObjectContainer.renderDrawableMask(cast object, this);
			case BITMAP:
				CairoBitmap.renderDrawableMask(cast object, this);
			case SHAPE:
				CairoShape.renderDrawableMask(cast object, this);
			case SIMPLE_BUTTON:
				CairoSimpleButton.renderDrawableMask(cast object, this);
			case TEXT_FIELD:
				CairoTextField.renderDrawableMask(cast object, this);
			case VIDEO:
				// TODO
			case TILEMAP:
				CairoTilemap.renderDrawableMask(cast object, this);
			default:
		}
	}

	@:noCompletion private override function __setBlendMode(value:BlendMode):Void
	{
		if (__overrideBlendMode != null) value = __overrideBlendMode;
		if (value == __groupBlendMode) value = NORMAL;
		if (__blendMode == value) return;

		__blendMode = value;
		__setBlendModeCairo(cairo, value);
	}

	@SuppressWarnings("checkstyle:Dynamic")
	@:noCompletion private function __setBlendModeCairo(cairo:#if lime Cairo #else Dynamic #end, value:BlendMode):Void
	{
		#if lime
		switch (value)
		{
			// ALPHA, ERASE, INVERT and SUBTRACT are rendered into a Cairo group and
			// composited with the destination in __renderBlendGroup. Cairo has no operator
			// for the last two, and the first two need the object as one clipped piece.

			case ADD:
				cairo.setOperator(CairoOperator.ADD);

			case DARKEN:
				cairo.setOperator(CairoOperator.DARKEN);

			case DIFFERENCE:
				cairo.setOperator(CairoOperator.DIFFERENCE);

			case HARDLIGHT:
				cairo.setOperator(CairoOperator.HARD_LIGHT);

			case LAYER:
				cairo.setOperator(CairoOperator.OVER);

			case LIGHTEN:
				cairo.setOperator(CairoOperator.LIGHTEN);

			case MULTIPLY:
				cairo.setOperator(CairoOperator.MULTIPLY);

			case OVERLAY:
				cairo.setOperator(CairoOperator.OVERLAY);

			case SCREEN:
				cairo.setOperator(CairoOperator.SCREEN);

			// case SHADER:

			// TODO

			default:
				cairo.setOperator(CairoOperator.OVER);
		}
		#end
	}
}
#else
typedef CairoRenderer = Dynamic;
#end
