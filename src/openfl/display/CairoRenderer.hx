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
import lime.graphics.cairo.CairoExtend;
import lime.graphics.cairo.CairoFilter;
import lime.graphics.cairo.CairoFormat;
import lime.graphics.cairo.CairoImageSurface;
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
@:access(openfl.display.Bitmap)
@:access(openfl.display.BitmapData)
@:access(openfl.display.DisplayObject)
@:access(openfl.display.Graphics)
@:access(openfl.display.IBitmapDrawable)
@:access(openfl.display.Stage)
@:access(openfl.display.Stage3D)
@:allow(openfl.display._internal)
@:allow(openfl.display)
@:access(openfl.geom.Matrix)
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
	#if lime
	// the touched buffer of the LAYER group being drawn into (see __touch), once built: a context on
	// a bitmap the size of the layer, whose origin sits at (__touchedX, __touchedY) of the target.
	// One bitmap is kept per layer depth
	@:noCompletion private var __touched:Cairo;
	@:noCompletion private var __touchedBitmap:BitmapData;
	@:noCompletion private var __touchedX:Int;
	@:noCompletion private var __touchedY:Int;
	@:noCompletion private var __touchedWidth:Int;
	@:noCompletion private var __touchedHeight:Int;
	@:noCompletion private static var __touchedBitmaps:Array<BitmapData> = [];
	// the scratch bitmaps of a composite done on format views (see __compositeFormulaOnViews): the
	// result, the object, its covered and uncovered parts, a grey of the uncovered part's alpha, the
	// result's alpha, and the mask that lets only alpha bytes through
	@:noCompletion private static var __opResult:BitmapData;
	@:noCompletion private static var __opObject:BitmapData;
	@:noCompletion private static var __opCovered:BitmapData;
	@:noCompletion private static var __opUncovered:BitmapData;
	@:noCompletion private static var __opGrey:BitmapData;
	@:noCompletion private static var __opAlpha:CairoImageSurface;
	@:noCompletion private static var __opAlphaWidth:Int = 0;
	@:noCompletion private static var __opAlphaHeight:Int = 0;
	@:noCompletion private static var __opAlphaMask:CairoPattern;
	#end

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

		// the root is rendered as it is, its own blend mode being its parent's to apply, unless
		// BitmapData.draw gave a blend mode: then the root is composited with it, as one object
		if (__overrideBlendMode != null && __overrideBlendMode != NORMAL) __renderDrawable(object);
		else __renderDrawableDirect(object);
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
			if (displayObject.__blendMode == LAYER && __blendGroupDepth == 0 && (__overrideBlendMode == null || __overrideBlendMode == NORMAL))
			{
				__renderLayerGroup(object);
				__touch(displayObject, true);
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
					__renderFormulaGroup(object, blendMode);
					__touch(displayObject, true);
					return;
				}
				if (__needsWholeObjectGroup(displayObject, blendMode))
				{
					__renderOperatorGroup(object, blendMode);
					__touch(displayObject, true);
					return;
				}
			}
		}
		#end

		__renderDrawableDirect(object);
		#if lime
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
		// no group opens inside this one, so nothing there reads what has been touched
		var parentTouchedRoot = __touchedRoot;
		__touchedRoot = null;
		// the container's alpha applies once, to the composite: divided out of the children here
		var cacheWorldAlpha = __worldAlpha;
		__worldAlpha = 1 / displayObject.__worldAlpha;
		__renderDrawableDirect(object);
		__worldAlpha = cacheWorldAlpha;
		__touchedRoot = parentTouchedRoot;
		__groupBlendMode = previousGroupBlendMode;

		cairo.popGroupToSource();
		__setBlendModeCairo(cairo, blendMode);
		var alpha = __getAlpha(displayObject.__worldAlpha);
		if (alpha >= 1) cairo.paint();
		else cairo.paintWithAlpha(alpha);

		cairo.restore();
		__blendMode = null; // the operator is set again by the next __setBlendMode
		__layerDepth--;
		#end
	}

	#if lime
	@:noCompletion private var __blendGroupDepth:Int = 0;
	@:noCompletion private var __layerDepth:Int = 0;

	/**
		Renders a LAYER container into its own group, then draws that group onto the target as one image
		with the container's alpha. Children with ERASE or ALPHA inside the layer therefore only affect
		the layer's own content, not what lies behind it.
	**/
	@:noCompletion private function __renderLayerGroup(object:IBitmapDrawable):Void
	{
		__layerDepth++;
		cairo.save();
		cairo.identityMatrix();

		// clip to the container's bounds: the group is then allocated at that size, and so is
		// the touched buffer if a child needs one
		var displayObject:DisplayObject = cast object;
		var bounds = Rectangle.__pool.get();
		displayObject.__getFilterBounds(bounds, displayObject.__renderTransform);
		if (__worldTransform != null) bounds.__transform(bounds, __worldTransform);
		var x0 = Math.floor(bounds.x), y0 = Math.floor(bounds.y);
		var width = Math.ceil(bounds.right) - x0, height = Math.ceil(bounds.bottom) - y0;
		cairo.rectangle(x0, y0, width, height);
		cairo.clip();
		Rectangle.__pool.release(bounds);

		cairo.pushGroupWithContent(CairoContent.COLOR_ALPHA);
		__blendMode = null;
		// a LAYER tracks what its children touch, from the moment a child needs it (see __touch)
		var parentTouchedRoot = __touchedRoot, parentTouched = __touched, parentTouchedBitmap = __touchedBitmap;
		var parentTouchedActive = __touchedActive;
		var parentTouchedX = __touchedX, parentTouchedY = __touchedY, parentTouchedWidth = __touchedWidth, parentTouchedHeight = __touchedHeight;
		__touchedRoot = displayObject;
		__touched = null;
		__touchedBitmap = null;
		__touchedActive = false;
		__touchedX = x0;
		__touchedY = y0;
		__touchedWidth = width;
		__touchedHeight = height;
		// the layer's alpha applies once, to the composite: divided out of the children here
		var cacheWorldAlpha = __worldAlpha;
		__worldAlpha = 1 / displayObject.__worldAlpha;
		__renderDrawableDirect(object);
		__worldAlpha = cacheWorldAlpha;
		__touchedRoot = parentTouchedRoot;
		__touched = parentTouched;
		__touchedBitmap = parentTouchedBitmap;
		__touchedActive = parentTouchedActive;
		__touchedX = parentTouchedX;
		__touchedY = parentTouchedY;
		__touchedWidth = parentTouchedWidth;
		__touchedHeight = parentTouchedHeight;
		cairo.popGroupToSource();
		cairo.setOperator(CairoOperator.OVER);
		var alpha = __getAlpha(displayObject.__worldAlpha);
		if (alpha >= 1) cairo.paint();
		else cairo.paintWithAlpha(alpha);
		cairo.restore();
		__blendMode = null;
		__layerDepth--;
	}

	/**
		Composites `object` with one of the four modes Cairo has no single operator for: SUBTRACT,
		INVERT, ERASE and ALPHA.

		The object is rendered on its own into a Cairo group, and the matching `__composite` function
		then combines that group with what is already on the target. A single Bitmap or Shape at full
		alpha skips the group and is read straight from its own surface (see `__leafPattern`). Where
		nothing has been drawn into the target yet, the object is drawn as it is instead, as Flash does
		(see `__touch`).
	**/
	@:noCompletion private function __renderFormulaGroup(object:IBitmapDrawable, blendMode:BlendMode):Void
	{
		var displayObject:DisplayObject = cast object;
		if (displayObject.__worldAlpha <= 0) return;
		var previousOverride = __overrideBlendMode;
		// the mode this group is composited with, for the shapes rendered inside it (__isCompositedWithAlpha)
		var previousGroupBlendMode = __groupBlendMode;
		__groupBlendMode = blendMode;
		__blendGroupDepth++;

		// the surface being drawn on right now: the window, the bitmap, or the
		// enclosing LAYER group
		var destination = cairo.groupTarget;

		cairo.save();
		cairo.identityMatrix();

		// clip to the object's bounds first: the group and the destination copies are then
		// allocated and painted at that size instead of the whole surface, and DEST_IN
		// (ALPHA), which is unbounded, cannot reach outside it
		var bounds = Rectangle.__pool.get();
		displayObject.__getFilterBounds(bounds, displayObject.__renderTransform);
		if (__worldTransform != null) bounds.__transform(bounds, __worldTransform);
		// whole pixels, exactly covering the bounds: DEST_IN cuts everything inside the clip
		var x0 = Math.floor(bounds.x), y0 = Math.floor(bounds.y);
		var width = Math.ceil(bounds.right) - x0, height = Math.ceil(bounds.bottom) - y0;
		cairo.rectangle(x0, y0, width, height);
		cairo.clip();
		Rectangle.__pool.release(bounds);

		// a one-piece object at full alpha is composited straight from its own surface
		var alpha = __getAlpha(displayObject.__worldAlpha);
		var objectPattern = alpha >= 1 ? __leafPattern(displayObject) : null;

		if (objectPattern == null)
		{
			cairo.pushGroupWithContent(CairoContent.COLOR_ALPHA);

			// the object and its children draw normally inside the group, with the object's alpha
			// divided out: it applies once, to the whole object, below
			__overrideBlendMode = NORMAL;
			__blendMode = null;
			// no group opens inside this one, so nothing there reads what has been touched
			var parentTouchedRoot = __touchedRoot;
			__touchedRoot = null;
			var cacheWorldAlpha = __worldAlpha;
			__worldAlpha = 1 / displayObject.__worldAlpha;
			__renderDrawableDirect(object);
			__worldAlpha = cacheWorldAlpha;
			__touchedRoot = parentTouchedRoot;
			__overrideBlendMode = previousOverride;

			objectPattern = cairo.popGroup();
			if (alpha < 1)
			{
				cairo.pushGroupWithContent(CairoContent.COLOR_ALPHA);
				cairo.source = objectPattern;
				cairo.setOperator(CairoOperator.OVER);
				cairo.paintWithAlpha(alpha);
				objectPattern = cairo.popGroup();
			}
		}

		// Flash applies these four modes to the part of every pixel that earlier objects have
		// covered (see __touch), and draws the object as it is over the rest. Without a touched
		// buffer, everything counts as covered. On an opaque target ALPHA and ERASE work with
		// operators, and so do SUBTRACT and INVERT, whose formulas then have an opaque backdrop.
		// On a transparent target SUBTRACT and INVERT work on views of the pixels in other formats:
		// their formulas take the covered part's color, which no operator on ARGB pixels can give
		__ensureTouched(displayObject);
		if ((blendMode == SUBTRACT || blendMode == INVERT) && !__backdropIsOpaque())
		{
			__compositeFormulaOnViews(destination, objectPattern, blendMode, x0, y0, width, height);
		}
		else
		{
			// the object over what is not covered, added back after the composite
			var uncovered:CairoPattern = null;
			if (__touchedActive)
			{
				cairo.pushGroupWithContent(CairoContent.COLOR_ALPHA);
				cairo.source = objectPattern;
				cairo.setOperator(CairoOperator.OVER);
				cairo.paint();
				cairo.setSourceSurface(__touchedBitmap.getSurface(), __touchedX, __touchedY);
				cairo.setOperator(CairoOperator.DEST_OUT);
				cairo.paint();
				uncovered = cairo.popGroup();
			}

			switch (blendMode)
			{
				case ALPHA, ERASE:
					__compositeAlphaErase(objectPattern, blendMode, displayObject);
				case INVERT:
					__compositeInvert(destination, objectPattern);
				case SUBTRACT:
					__compositeSubtract(destination, __premultipliedPattern(objectPattern));
				default:
			}

			if (uncovered != null)
			{
				cairo.source = uncovered;
				cairo.setOperator(CairoOperator.ADD);
				cairo.paint();
			}
		}

		cairo.restore();
		__blendMode = null; // the operator is set again by the next __setBlendMode
		__groupBlendMode = previousGroupBlendMode;
		__blendGroupDepth--;
	}

	/**
		Returns a pattern of a single-piece object's own pixels, a Bitmap's bitmapData or a Shape's
		rendered graphics, positioned exactly where the object is drawn. The composite functions can
		read the object from it without rendering it into a group first. Returns null if the object is
		not a single piece (see `__isBlendLeaf`) or has nothing to draw.
	**/
	@:noCompletion private function __leafPattern(displayObject:DisplayObject):CairoPattern
	{
		if (!__isBlendLeaf(displayObject)) return null;

		var surface:CairoSurface = null;
		var transform = Matrix.__pool.get();
		var pattern:CairoPattern = null;
		var graphics = displayObject.__graphics;

		if (graphics == null)
		{
			var bitmap:Bitmap = cast displayObject;
			var bitmapData = bitmap.__bitmapData;
			if (bitmapData != null && bitmapData.__isValid)
			{
				if (bitmapData.image != null) bitmap.__imageVersion = bitmapData.image.version;
				surface = bitmapData.getSurface();
				transform.copyFrom(bitmap.__renderTransform);
				if (surface != null)
				{
					pattern = CairoPattern.createForSurface(surface);
					pattern.filter = (__allowSmoothing && bitmap.smoothing) ? CairoFilter.GOOD : CairoFilter.NEAREST;
				}
			}
		}
		else
		{
			#if lime_cairo
			CairoGraphics.render(graphics, this, __isCompositedWithAlpha(displayObject));
			if (graphics.__cairo != null && graphics.__visible && graphics.__width >= 1 && graphics.__height >= 1)
			{
				surface = graphics.__cairo.target;
				transform.scale(1 / graphics.__bitmapScaleX, 1 / graphics.__bitmapScaleY);
				transform.concat(graphics.__worldTransform);
				pattern = CairoPattern.createForSurface(surface);
			}
			#end
		}

		if (pattern != null)
		{
			// as applyMatrix places the surface, inverted: a pattern matrix maps device to pattern space
			if (__worldTransform != null) transform.concat(__worldTransform);
			if (__roundPixels)
			{
				transform.tx = Math.round(transform.tx);
				transform.ty = Math.round(transform.ty);
			}
			transform.invert();
			__matrix3.a = transform.a;
			__matrix3.b = transform.b;
			__matrix3.c = transform.c;
			__matrix3.d = transform.d;
			__matrix3.tx = transform.tx;
			__matrix3.ty = transform.ty;
			pattern.matrix = __matrix3;
		}

		Matrix.__pool.release(transform);
		__renderEvent(displayObject);
		return pattern;
	}

	@:noCompletion private function __compositeAlphaErase(objectPattern:CairoPattern, blendMode:BlendMode, displayObject:DisplayObject):Void
	{
		if (blendMode == ALPHA && __alphaNeedsMask(displayObject))
		{
			// Flash's ALPHA masks with what the object's leaves cover: a Bitmap its footprint,
			// transparent pixels included, a shape only its fills, and the part of the object's
			// box that no leaf covers keeps the backdrop. At an anti-aliased edge coverage and
			// fill alpha stay apart too. DEST_IN cuts wherever the source is transparent, so the
			// mask is 1 - coverage + alpha, built in a group over the clip with operators alone:
			// opaque, the coverage taken out (DEST_OUT), the object added (ADD, which clamps at 1)
			cairo.pushGroupWithContent(CairoContent.COLOR_ALPHA);
			cairo.setSourceRGB(0, 0, 0);
			cairo.setOperator(CairoOperator.SOURCE);
			cairo.paint();
			cairo.setOperator(CairoOperator.DEST_OUT);
			__drawCoverage(cairo, displayObject, 0, 0);
			cairo.identityMatrix();
			cairo.source = objectPattern;
			cairo.setOperator(CairoOperator.ADD);
			cairo.paint();
			cairo.popGroupToSource();
		}
		else
		{
			cairo.source = objectPattern;
		}

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

	/**
		Paints the area covered by `displayObject` and all its descendants into `coverage`, a context
		whose origin sits at (x0, y0) of the target, using the operator currently set on that context.

		For a shape, this is the area of its fills and strokes, taken from its coverage render, which
		is made now if the shape has none yet. For a text field, it is the alpha of its rendered text.
		For any other object without children, it is the object's bounding box. Every piece is placed
		with the same transform it is drawn with.
	**/
	@:noCompletion private function __drawCoverage(coverage:Cairo, displayObject:DisplayObject, x0:Int, y0:Int):Void
	{
		if (!displayObject.__renderable) return;
		var graphics = displayObject.__graphics;

		if (graphics != null) __drawGraphicsCoverage(coverage, displayObject, x0, y0);

		if (displayObject.__children != null)
		{
			for (child in displayObject.__children) __drawCoverage(coverage, child, x0, y0);
		}
		else if (graphics == null)
		{
			var bounds = Rectangle.__pool.get();
			var matrix = Matrix.__pool.get();
			displayObject.__getBounds(bounds, Matrix.__identity);
			matrix.copyFrom(displayObject.__renderTransform);
			__applyCoverageMatrix(coverage, matrix, x0, y0);
			coverage.setSourceRGB(0, 0, 0);
			coverage.rectangle(bounds.x, bounds.y, bounds.width, bounds.height);
			coverage.fill();
			Matrix.__pool.release(matrix);
			Rectangle.__pool.release(bounds);
		}
	}

	/**
		Paints the area covered by the fills and strokes of the graphics of `displayObject` into
		`coverage`, placed with the same transform they are drawn with (see `__drawCoverage`).
	**/
	@:noCompletion private function __drawGraphicsCoverage(coverage:Cairo, displayObject:DisplayObject, x0:Int, y0:Int):Void
	{
		var graphics = displayObject.__graphics;
		CairoGraphics.render(graphics, this, true);
		if (graphics.__bitmap == null) return;

		var matrix = Matrix.__pool.get();
		matrix.scale(1 / graphics.__bitmapScaleX, 1 / graphics.__bitmapScaleY);
		matrix.concat(graphics.__worldTransform);
		__applyCoverageMatrix(coverage, matrix, x0, y0);
		if (graphics.__coverage != null)
		{
			coverage.setSourceSurface(graphics.__coverage.getSurface(), 0, 0);
			coverage.rectangle(0, 0, graphics.__coverage.width, graphics.__coverage.height);
		}
		else if (graphics.__managed)
		{
			// a text field draws straight into its bitmap, in colors that are always opaque, so
			// the bitmap's own alpha is its coverage
			coverage.setSourceSurface(graphics.__bitmap.getSurface(), 0, 0);
			coverage.rectangle(0, 0, graphics.__bitmap.width, graphics.__bitmap.height);
		}
		else
		{
			coverage.setSourceRGB(0, 0, 0);
			coverage.rectangle(0, 0, graphics.__bitmap.width, graphics.__bitmap.height);
		}
		coverage.fill();
		Matrix.__pool.release(matrix);
	}

	/**
		Sets the transform of `coverage` so that it draws exactly where the object is drawn: the
		object's `matrix` combined with the renderer's world transform, snapped to whole pixels when
		pixel rounding is on, and moved by (-x0, -y0), the origin of the context on the target.
	**/
	@:noCompletion private function __applyCoverageMatrix(coverage:Cairo, matrix:Matrix, x0:Int, y0:Int):Void
	{
		if (__worldTransform != null) matrix.concat(__worldTransform);
		if (__roundPixels)
		{
			matrix.tx = Math.round(matrix.tx);
			matrix.ty = Math.round(matrix.ty);
		}
		matrix.translate(-x0, -y0);
		coverage.matrix = matrix.__toMatrix3();
	}

	/**
		Builds the current group's touched buffer if the group tracks one and it has not been built yet
		(see `__touch`): the coverage of everything drawn into the group before `displayObject`, which
		is about to be composited with a mode that reads it. From then on, every object drawn into the
		group adds itself as it is drawn. The buffer is an image surface the size of the layer, kept
		per layer depth.
	**/
	@:noCompletion private function __ensureTouched(displayObject:DisplayObject):Void
	{
		if (__touchedRoot == null || __touchedActive) return;

		var bitmap = __touchedBitmaps[__layerDepth];
		if (bitmap == null || bitmap.width < __touchedWidth || bitmap.height < __touchedHeight)
		{
			if (bitmap != null) bitmap.dispose();
			bitmap = new BitmapData(__touchedWidth, __touchedHeight, true, 0);
			__touchedBitmaps[__layerDepth] = bitmap;
		}
		__touchedBitmap = bitmap;
		__touched = new Cairo(bitmap.getSurface());
		__touched.setSourceRGBA(0, 0, 0, 0);
		__touched.setOperator(CairoOperator.SOURCE);
		__touched.paint();
		__touched.setOperator(CairoOperator.OVER);
		__touchedActive = true;
		__walkTouched(__touchedRoot, displayObject);
	}

	@:noCompletion private override function __drawTouched(displayObject:DisplayObject, graphicsOnly:Bool):Void
	{
		if (graphicsOnly) __drawGraphicsCoverage(__touched, displayObject, __touchedX, __touchedY);
		else __drawCoverage(__touched, displayObject, __touchedX, __touchedY);
	}

	/**
		Composites `objectPattern` onto a transparent target with SUBTRACT or INVERT, over the rectangle
		(x0, y0, width, height) of the target, with operators on views of scratch bitmaps in other
		formats.

		For every pixel, c is how much of it earlier objects have covered (the touched buffer, or all of
		it without one) and the backdrop D is c of the covered part's color. Flash applies the mode's
		formula to that color, opaque where the object S is opaque, mixes the result with the object
		as it is by c, and gives the whole the alpha of S over D. That comes to a color of
		max(0, D - cS) + (1 - c) S for SUBTRACT, and D (1 - 2s) + cs + (1 - c) S for INVERT, with an
		alpha of s + Da (1 - s): color and alpha from different expressions, which no operator on an
		ARGB surface can write at once.

		An RGB24 view of the same bytes treats the premultiplied color as opaque color, so the color is
		worked out there without alpha weighting: max(0, D - cS) is a LIGHTEN followed by a DIFFERENCE
		with the covered part of the object, also read through an RGB24 view. An A8 surface holds the
		alpha on its own, the object over the backdrop. And an A8 view of the result four times as
		wide, in which every fourth pixel is an alpha byte, lets that alpha be written back through a
		repeating mask without touching the color. The target is copied into the result bitmap first
		and painted back at the end, because a Cairo group target cannot be read by another context,
		nor viewed.
	**/
	@:noCompletion private function __compositeFormulaOnViews(destination:CairoSurface, objectPattern:CairoPattern, blendMode:BlendMode, x0:Int, y0:Int,
			width:Int, height:Int):Void
	{
		#if !js
		if (__opResult == null || __opResult.width < width || __opResult.height < height)
		{
			var w = __opResult != null && __opResult.width > width ? __opResult.width : width;
			var h = __opResult != null && __opResult.height > height ? __opResult.height : height;
			for (b in [__opResult, __opObject, __opCovered, __opUncovered, __opGrey]) if (b != null) b.dispose();
			__opResult = new BitmapData(w, h, true, 0);
			__opObject = new BitmapData(w, h, true, 0);
			__opCovered = new BitmapData(w, h, true, 0);
			__opUncovered = new BitmapData(w, h, true, 0);
			__opGrey = new BitmapData(w, h, true, 0);
		}
		if (__opAlpha == null || __opAlphaWidth < width || __opAlphaHeight < height)
		{
			__opAlphaWidth = __opResult.width;
			__opAlphaHeight = __opResult.height;
			__opAlpha = new CairoImageSurface(CairoFormat.A8, __opAlphaWidth, __opAlphaHeight);
		}
		if (__opAlphaMask == null)
		{
			// one opaque pixel in four, at the alpha byte of a BGRA pixel, repeated
			var maskSurface = new CairoImageSurface(CairoFormat.A8, 4, 1);
			var maskContext = new Cairo(maskSurface);
			maskContext.setSourceRGBA(0, 0, 0, 1);
			maskContext.rectangle(3, 0, 1, 1);
			maskContext.fill();
			__opAlphaMask = CairoPattern.createForSurface(maskSurface);
			__opAlphaMask.extend = CairoExtend.REPEAT;
			__opAlphaMask.filter = CairoFilter.NEAREST;
		}
		var result = __opResult, object = __opObject, covered = __opCovered, uncovered = __opUncovered, grey = __opGrey;
		for (b in [result, object, covered, uncovered, grey]) b.__surface = null;
		var stride = result.image.buffer.stride;
		var invert = blendMode == INVERT;

		// the target rectangle and the object, at the scratch bitmaps' origin; the target is read
		// through a group pattern, since a group target cannot be read by another context, and every
		// scratch gets a new surface over its memory, since a surface that has been drawn into and
		// read from no longer shows writes made to the bytes
		cairo.pushGroupWithContent(CairoContent.COLOR_ALPHA);
		cairo.setSourceSurface(destination, 0, 0);
		cairo.setOperator(CairoOperator.SOURCE);
		cairo.paint();
		var backdropPattern = cairo.popGroup();
		var ctx = new Cairo(result.getSurface());
		ctx.translate(-x0, -y0);
		ctx.source = backdropPattern;
		ctx.setOperator(CairoOperator.SOURCE);
		ctx.paint();
		ctx = new Cairo(object.getSurface());
		ctx.translate(-x0, -y0);
		ctx.source = objectPattern;
		ctx.setOperator(CairoOperator.SOURCE);
		ctx.paint();

		// the object split by the coverage: c S and (1 - c) S
		var objectSurface = object.getSurface();
		ctx = new Cairo(covered.getSurface());
		ctx.setSourceSurface(objectSurface, 0, 0);
		ctx.setOperator(CairoOperator.SOURCE);
		ctx.paint();
		if (__touchedActive)
		{
			ctx.setSourceSurface(__touchedBitmap.getSurface(), __touchedX - x0, __touchedY - y0);
			ctx.setOperator(CairoOperator.DEST_IN);
			ctx.paint();
			ctx = new Cairo(uncovered.getSurface());
			ctx.setSourceSurface(objectSurface, 0, 0);
			ctx.setOperator(CairoOperator.SOURCE);
			ctx.paint();
			ctx.setSourceSurface(__touchedBitmap.getSurface(), __touchedX - x0, __touchedY - y0);
			ctx.setOperator(CairoOperator.DEST_OUT);
			ctx.paint();
		}

		// the alpha, on its own: the object over the backdrop
		ctx = new Cairo(__opAlpha);
		ctx.setSourceSurface(result.getSurface(), 0, 0);
		ctx.setOperator(CairoOperator.SOURCE);
		ctx.paint();
		ctx.setSourceSurface(objectSurface, 0, 0);
		ctx.setOperator(CairoOperator.OVER);
		ctx.paint();

		// the color, on an RGB24 view of the result: its premultiplied bytes as opaque color, and the
		// covered part's likewise, so max(0, D - cS) is a LIGHTEN followed by a DIFFERENCE
		var rgb = new Cairo(CairoImageSurface.create(result.image.data.buffer, CairoFormat.RGB24, result.width, result.height, stride));
		var coveredOpaque = CairoImageSurface.create(covered.image.data.buffer, CairoFormat.RGB24, covered.width, covered.height, stride);
		if (invert)
		{
			// D (1 - 2s) + s, then the uncovered share of the white taken out again: D (1 - 2s) + c s
			rgb.setSourceRGB(1, 1, 1);
			rgb.setOperator(CairoOperator.DIFFERENCE);
			rgb.save();
			rgb.translate(-x0, -y0);
			rgb.mask(objectPattern);
			rgb.restore();
			if (__touchedActive)
			{
				ctx = new Cairo(grey.getSurface());
				ctx.setSourceRGB(1, 1, 1);
				ctx.setOperator(CairoOperator.SOURCE);
				ctx.paint();
				ctx.setSourceSurface(uncovered.getSurface(), 0, 0);
				ctx.setOperator(CairoOperator.DEST_IN);
				ctx.paint();
				rgb.setSourceSurface(CairoImageSurface.create(grey.image.data.buffer, CairoFormat.RGB24, grey.width, grey.height, stride), 0, 0);
				rgb.setOperator(CairoOperator.DIFFERENCE);
				rgb.paint();
			}
		}
		else
		{
			rgb.setSourceSurface(coveredOpaque, 0, 0);
			rgb.setOperator(CairoOperator.LIGHTEN);
			rgb.paint();
			rgb.setOperator(CairoOperator.DIFFERENCE);
			rgb.paint();
		}
		if (__touchedActive)
		{
			// plus the object as it is over what is not covered
			rgb.setSourceSurface(uncovered.getSurface(), 0, 0);
			rgb.setOperator(CairoOperator.ADD);
			rgb.paint();
		}

		// the alpha written into the result's alpha bytes: an A8 view four pixels wide per BGRA
		// pixel, the alpha stretched to match, and only every fourth pixel let through
		var bytes = new Cairo(CairoImageSurface.create(result.image.data.buffer, CairoFormat.A8, result.width * 4, result.height, stride));
		var alphaPattern = CairoPattern.createForSurface(__opAlpha);
		alphaPattern.filter = CairoFilter.NEAREST;
		alphaPattern.matrix = new Matrix3(0.25, 0, 0, 1, 0, 0);
		bytes.source = alphaPattern;
		bytes.setOperator(CairoOperator.SOURCE);
		bytes.mask(__opAlphaMask);

		result.__surface = null;
		cairo.setSourceSurface(result.getSurface(), x0, y0);
		cairo.setOperator(CairoOperator.SOURCE);
		cairo.rectangle(x0, y0, width, height);
		cairo.fill();
		#end
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

	/**
		Returns a copy of the object drawn over opaque black. In it every pixel holds the object's color
		already multiplied by its alpha, black where the object is transparent, with full alpha
		everywhere. `__compositeSubtract` needs its source in this form, because its two blend passes
		would otherwise apply the object's alpha twice at partly transparent pixels.
	**/
	@:noCompletion private function __premultipliedPattern(objectPattern:CairoPattern):CairoPattern
	{
		cairo.pushGroupWithContent(CairoContent.COLOR_ALPHA);
		cairo.setSourceRGB(0, 0, 0);
		cairo.setOperator(CairoOperator.SOURCE);
		cairo.paint();
		cairo.source = objectPattern;
		cairo.setOperator(CairoOperator.OVER);
		cairo.paint();
		return cairo.popGroup();
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

	@:noCompletion private override function __setBlendMode(value:BlendMode, force:Bool = false):Void
	{
		if (__overrideBlendMode != null) value = __overrideBlendMode;
		if (value == __groupBlendMode) value = NORMAL;
		if (!force && __blendMode == value) return;

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
			// composited with the destination in __renderFormulaGroup. Cairo has no operator
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
