package render.scenes;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
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
	The filters on curved shapes, at stage quality HIGH, with no blend modes (the combined kit's
	`--variant filters`): the cells of `Combined` with every mode left NORMAL, so a branch with the
	filters work can check them before the blend-mode work is merged. Rows: a filtered shape on the
	stage; filtered shapes inside a LAYER; filters on groups, on a LAYER and on a cached group;
	BitmapData.draw of a filtered group, the gradient filters and hairlines; BitmapData.draw of a
	filtered object.
**/
class Filters extends Cells
{
	static var NAMES = [
		"Glow", "DropShadow", "Blur", "Bevel",
		"LAYER: DropShadow", "LAYER: Glow at alpha .5", "LAYER: blurred bar over a ring", "LAYER: Glow",
		"group + DropShadow", "blurred LAYER", "glowing LAYER", "cached group + Bevel",
		"draw() of glowing disc", "GradientGlow", "GradientBevel", "hairlines + DropShadow",
		"draw(root disc)", "draw(root DropShadow .8)", "draw(root Blur)", "draw(root DropShadow 1)"
	];

	public function new()
	{
		super();
		name = "filters_high";
		reference = "reference/filters_high.png";
		grid(NAMES);
	}

	override public function build(root:Sprite):Void
	{
		this.root = root;

		// row 0: a filtered shape on the stage
		var c = cellSprite(0, 0, false);
		c.addChild(filtered(disc(0xFF8040, 30), [new GlowFilter(0x2060FF, 1, 12, 12, 2, 2)]));
		c = cellSprite(1, 0, false);
		c.addChild(filtered(disc(0xFF8040, 30), [new DropShadowFilter(6, 45, 0x000000, 0.8, 8, 8, 1, 2)]));
		c = cellSprite(2, 0, false);
		c.addChild(filtered(disc(0xC0A060, 30), [new BlurFilter(6, 6, 2)]));
		c = cellSprite(3, 0, false);
		c.addChild(filtered(roundRect(0x40C080), [new BevelFilter(4, 45, 0xFFFFFF, 1, 0x000000, 1, 6, 6, 1, 2)]));

		// row 1: filtered shapes inside a LAYER
		c = cellSprite(0, 1, true);
		c.addChild(filtered(disc(0xFF8040, 30), [new DropShadowFilter(6, 45, 0x000000, 1, 8, 8, 1, 2)]));
		c = cellSprite(1, 1, true);
		var a = filtered(disc(0xFF8040, 30), [new GlowFilter(0xFFFFFF, 1, 10, 10, 2, 2)]);
		a.alpha = 0.5;
		c.addChild(a);
		c = cellSprite(2, 1, true);
		c.addChild(ring());
		c.addChild(filtered(bar(0xFF8040), [new BlurFilter(4, 4, 2)]));
		c = cellSprite(3, 1, true);
		c.addChild(filtered(disc(0xFF8040, 30), [new GlowFilter(0x20C040, 1, 10, 10, 2, 2)]));

		// row 2: filters on a group, a LAYER and a cached group
		c = cellSprite(0, 2, false);
		var group = new Sprite();
		group.addChild(at(disc(0xFF4040, 24), -12, 0));
		group.addChild(at(disc(0x4040FF, 24), 12, 0));
		group.filters = [new DropShadowFilter(6, 45, 0x000000, 0.8, 6, 6, 1, 2)];
		c.addChild(group);

		c = cellSprite(1, 2, true);
		c.addChild(at(disc(0x2060FF, 22), -10, -8));
		c.addChild(at(disc(0xFF8040, 26), 10, 8));
		c.filters = [new BlurFilter(3, 3, 2)];

		c = cellSprite(2, 2, true);
		c.addChild(centre(disc(0xFF8040, 26)));
		c.filters = [new GlowFilter(0xFFE020, 1, 8, 8, 2, 2)];

		c = cellSprite(3, 2, false);
		var cached = new Sprite();
		cached.addChild(at(square(0x2060FF, 56), 0, 0));
		cached.addChild(centre(disc(0xFF8040, 26)));
		cached.cacheAsBitmap = true;
		cached.filters = [new BevelFilter(4, 45, 0xFFFFFF, 1, 0x000000, 1, 6, 6, 1, 2)];
		c.addChild(cached);

		// row 3: BitmapData.draw of a filtered group, the gradient filters, hairlines
		c = cellSprite(0, 3, false);
		var source = new Sprite();
		source.addChild(backdrop());
		var glowing = filtered(disc(0xFF8040, 26), [new GlowFilter(0x2060FF, 1, 10, 10, 2, 2)]);
		glowing.x = 60;
		glowing.y = 60;
		source.addChild(glowing);
		var drawn = new BitmapData(Cells.CELL, Cells.CELL, true, 0);
		drawn.draw(source);
		c.removeChildAt(0);
		c.addChild(new Bitmap(drawn));

		c = cellSprite(1, 3, false);
		c.addChild(filtered(disc(0xFF8040, 28),
			[new GradientGlowFilter(0, 45, [0x0000FF, 0xFF00FF, 0xFFFF00], [0, 1, 1], [0, 128, 255], 12, 12, 2, 2, BitmapFilterType.OUTER)]));
		c = cellSprite(2, 3, false);
		c.addChild(filtered(roundRect(0x40C080),
			[new GradientBevelFilter(5, 45, [0xFFFFFF, 0x808080, 0x000000], [1, 0, 1], [0, 128, 255], 6, 6, 1, 2)]));
		c = cellSprite(3, 3, false);
		c.addChild(filtered(fan(), [new DropShadowFilter(3, 45, 0x000000, 0.8, 4, 4, 1, 2)]));

		// row 4: BitmapData.draw of a filtered object, over a backdrop drawn first
		drawCell(0, 4, centre(disc(0xFF8040, 30)), null);
		drawCell(1, 4, filtered(disc(0xFF8040, 30), [new DropShadowFilter(6, 45, 0x000000, 0.8, 8, 8, 1, 2)]), null);
		drawCell(2, 4, filtered(disc(0xC0A060, 30), [new BlurFilter(6, 6, 2)]), null);
		drawCell(3, 4, filtered(disc(0xFF8040, 30), [new DropShadowFilter(6, 45, 0x000000, 1, 8, 8, 1, 2)]), null);
	}

	/** Centres `o` and gives it `filters`. **/
	function filtered(o:DisplayObject, filters:Array<BitmapFilter>):DisplayObject
	{
		centre(o);
		o.filters = filters;
		return o;
	}
}
