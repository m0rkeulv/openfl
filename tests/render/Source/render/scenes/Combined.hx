package render.scenes;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.display.DisplayObject;
import openfl.display.Sprite;
import openfl.filters.BevelFilter;
import openfl.filters.BitmapFilter;
import openfl.filters.BitmapFilterType;
import openfl.filters.BlurFilter;
import openfl.filters.DropShadowFilter;
import openfl.filters.GlowFilter;
import openfl.filters.GradientBevelFilter;
import openfl.filters.GradientGlowFilter;

/**
	Filters and blend modes together on curved shapes, at stage quality HIGH (the combined kit,
	tools/filter-compare/combined): the cells of `Filters`, each subject also given a blend mode. Rows:
	a filtered shape blended straight onto the stage; filtered cutters and formula modes inside a LAYER;
	filters on blended, layered and cached groups; BitmapData.draw of a group, the gradient filters and
	hairlines; BitmapData.draw of an object that carries the mode itself.
**/
class Combined extends Cells
{
	static var NAMES = [
		"Glow + ADD", "DropShadow + MULTIPLY", "Blur + SUBTRACT", "Bevel + DIFFERENCE",
		"LAYER: DropShadow + ERASE", "LAYER: Glow + ALPHA .5", "LAYER: blurred SUBTRACT bar", "LAYER: Glow + INVERT",
		"ADD group + DropShadow", "blurred LAYER, SUBTRACT disc", "glowing LAYER, ERASE disc", "cached group, MULTIPLY + Bevel",
		"draw() of glowing SUBTRACT", "GradientGlow + SCREEN", "GradientBevel + OVERLAY", "hairlines + DropShadow + HARDLIGHT",
		"draw(root MULTIPLY disc)", "draw(root DropShadow + MULTIPLY)", "draw(root Blur + SUBTRACT)", "draw(root DropShadow + ERASE, ERASE)"
	];

	public function new()
	{
		super();
		name = "combined_high";
		reference = "reference/combined_high.png";
		grid(NAMES);
	}

	override public function build(root:Sprite):Void
	{
		this.root = root;

		// row 0: a filtered shape blended straight onto the stage
		var c = cellSprite(0, 0, false);
		c.addChild(with(disc(0xFF8040, 30), ADD, [new GlowFilter(0x2060FF, 1, 12, 12, 2, 2)]));
		c = cellSprite(1, 0, false);
		c.addChild(with(disc(0xFF8040, 30), MULTIPLY, [new DropShadowFilter(6, 45, 0x000000, 0.8, 8, 8, 1, 2)]));
		c = cellSprite(2, 0, false);
		c.addChild(with(disc(0xC0A060, 30), SUBTRACT, [new BlurFilter(6, 6, 2)]));
		c = cellSprite(3, 0, false);
		c.addChild(with(roundRect(0x40C080), DIFFERENCE, [new BevelFilter(4, 45, 0xFFFFFF, 1, 0x000000, 1, 6, 6, 1, 2)]));

		// row 1: filtered cutters and formula modes inside a LAYER
		c = cellSprite(0, 1, true);
		c.addChild(with(disc(0xFF8040, 30), ERASE, [new DropShadowFilter(6, 45, 0x000000, 1, 8, 8, 1, 2)]));
		c = cellSprite(1, 1, true);
		var a = with(disc(0xFF8040, 30), ALPHA, [new GlowFilter(0xFFFFFF, 1, 10, 10, 2, 2)]);
		a.alpha = 0.5;
		c.addChild(a);
		c = cellSprite(2, 1, true);
		c.addChild(ring());
		c.addChild(with(bar(0xFF8040), SUBTRACT, [new BlurFilter(4, 4, 2)]));
		c = cellSprite(3, 1, true);
		c.addChild(with(disc(0xFF8040, 30), INVERT, [new GlowFilter(0x20C040, 1, 10, 10, 2, 2)]));

		// row 2: filters on blended, layered and cached groups
		c = cellSprite(0, 2, false);
		var group = new Sprite();
		group.addChild(at(disc(0xFF4040, 24), -12, 0));
		group.addChild(at(disc(0x4040FF, 24), 12, 0));
		group.blendMode = ADD;
		group.filters = [new DropShadowFilter(6, 45, 0x000000, 0.8, 6, 6, 1, 2)];
		c.addChild(group);

		c = cellSprite(1, 2, true);
		c.addChild(at(disc(0x2060FF, 22), -10, -8));
		c.addChild(with(at(disc(0xFF8040, 26), 10, 8), SUBTRACT, null));
		c.filters = [new BlurFilter(3, 3, 2)];

		c = cellSprite(2, 2, true);
		c.addChild(with(disc(0xFF8040, 26), ERASE, null));
		c.filters = [new GlowFilter(0xFFE020, 1, 8, 8, 2, 2)];

		c = cellSprite(3, 2, false);
		var cached = new Sprite();
		cached.addChild(at(square(0x2060FF, 56), 0, 0));
		cached.addChild(with(disc(0xFF8040, 26), MULTIPLY, null));
		cached.cacheAsBitmap = true;
		cached.filters = [new BevelFilter(4, 45, 0xFFFFFF, 1, 0x000000, 1, 6, 6, 1, 2)];
		c.addChild(cached);

		// row 3: BitmapData.draw of a group, the gradient filters, hairlines
		c = cellSprite(0, 3, false);
		var source = new Sprite();
		source.addChild(backdrop());
		var glowing = with(disc(0xFF8040, 26), SUBTRACT, [new GlowFilter(0x2060FF, 1, 10, 10, 2, 2)]);
		glowing.x = 60;
		glowing.y = 60;
		source.addChild(glowing);
		var drawn = new BitmapData(Cells.CELL, Cells.CELL, true, 0);
		drawn.draw(source);
		c.removeChildAt(0);
		c.addChild(new Bitmap(drawn));

		c = cellSprite(1, 3, false);
		c.addChild(with(disc(0xFF8040, 28), SCREEN,
			[new GradientGlowFilter(0, 45, [0x0000FF, 0xFF00FF, 0xFFFF00], [0, 1, 1], [0, 128, 255], 12, 12, 2, 2, BitmapFilterType.OUTER)]));
		c = cellSprite(2, 3, false);
		c.addChild(with(roundRect(0x40C080), OVERLAY,
			[new GradientBevelFilter(5, 45, [0xFFFFFF, 0x808080, 0x000000], [1, 0, 1], [0, 128, 255], 6, 6, 1, 2)]));
		c = cellSprite(3, 3, false);
		c.addChild(with(fan(), HARDLIGHT, [new DropShadowFilter(3, 45, 0x000000, 0.8, 4, 4, 1, 2)]));

		// row 4: BitmapData.draw of an object that carries the mode itself, over a backdrop drawn first
		drawCell(0, 4, with(disc(0xFF8040, 30), MULTIPLY, null), null);
		drawCell(1, 4, with(disc(0xFF8040, 30), MULTIPLY, [new DropShadowFilter(6, 45, 0x000000, 0.8, 8, 8, 1, 2)]), null);
		drawCell(2, 4, with(disc(0xC0A060, 30), SUBTRACT, [new BlurFilter(6, 6, 2)]), null);
		drawCell(3, 4, with(disc(0xFF8040, 30), ERASE, [new DropShadowFilter(6, 45, 0x000000, 1, 8, 8, 1, 2)]), ERASE);
	}

	/** Centres `o` and gives it the mode and the filters. **/
	function with(o:DisplayObject, mode:BlendMode, filters:Array<BitmapFilter>):DisplayObject
	{
		centre(o);
		if (mode != null) o.blendMode = mode;
		if (filters != null) o.filters = filters;
		return o;
	}
}
