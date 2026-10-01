package render.scenes;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.display.DisplayObject;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
import render.Scene;

/**
	Common ground for the kit scenes (`Filters`, `Combined`): a 4 x 5 grid of 120 px cells on a grey
	stage at quality HIGH, each cell with a four-colour backdrop bitmap, and the shapes placed in them.
	Soft edges everywhere, so the tolerance is 32 and each cell may have a share of its pixels off.
**/
class Cells extends Scene
{
	public static inline var CELL = 120;

	var root:Sprite;

	public function new()
	{
		super();
		width = 480;
		height = 600;
		color = 0x808080;
		quality = HIGH;
		tolerance = 32;
		maxOff = 1.5;
		maxInterior = 0.3;
	}

	/** Lists `names` as the cells of the grid, in reading order. **/
	function grid(names:Array<String>):Void
	{
		for (i in 0...names.length)
			cell(names[i], (i % 4) * CELL, Std.int(i / 4) * CELL, CELL, CELL);
	}

	/** A cell with its backdrop, as a LAYER or on the stage, its origin at the cell's centre for subjects. **/
	function cellSprite(column:Int, row:Int, layer:Bool):Sprite
	{
		var c = new Sprite();
		c.x = column * CELL;
		c.y = row * CELL;
		if (layer) c.blendMode = LAYER;
		c.addChild(backdrop());
		root.addChild(c);
		return c;
	}

	/** A cell showing a transparent bitmap that received the backdrop, then `subject` drawn with `mode` (null: as it is). **/
	function drawCell(column:Int, row:Int, subject:DisplayObject, mode:BlendMode):Void
	{
		var c = cellSprite(column, row, false);
		c.removeChildAt(0);
		var drawn = new BitmapData(CELL, CELL, true, 0);
		drawn.draw(backdrop(), new Matrix(1, 0, 0, 1, 10, 10));
		drawn.draw(subject, new Matrix(1, 0, 0, 1, CELL / 2, CELL / 2), null, mode);
		c.addChild(new Bitmap(drawn));
	}

	/** Four colour quadrants, a bitmap so its edges do not depend on the stage quality. **/
	function backdrop():Bitmap
	{
		var bmd = new BitmapData(100, 100, false, 0);
		bmd.fillRect(new Rectangle(0, 0, 50, 50), 0x3050C0);
		bmd.fillRect(new Rectangle(50, 0, 50, 50), 0xE0C040);
		bmd.fillRect(new Rectangle(0, 50, 50, 50), 0x40A060);
		bmd.fillRect(new Rectangle(50, 50, 50, 50), 0xD0D0D0);
		var b = new Bitmap(bmd);
		b.x = 10;
		b.y = 10;
		return b;
	}

	/** Puts `o` at the cell's centre unless it was placed already. **/
	function centre(o:DisplayObject):DisplayObject
	{
		if (o.x == 0 && o.y == 0)
		{
			o.x = CELL / 2;
			o.y = CELL / 2;
		}
		return o;
	}

	function at(o:DisplayObject, dx:Float, dy:Float):DisplayObject
	{
		o.x = CELL / 2 + dx;
		o.y = CELL / 2 + dy;
		return o;
	}

	function disc(color:Int, radius:Float):Shape
	{
		var s = new Shape();
		s.graphics.beginFill(color);
		s.graphics.drawCircle(0, 0, radius);
		s.graphics.endFill();
		return s;
	}

	function square(color:Int, size:Float):Shape
	{
		var s = new Shape();
		s.graphics.beginFill(color);
		s.graphics.drawRect(-size / 2, -size / 2, size, size);
		s.graphics.endFill();
		return s;
	}

	function roundRect(color:Int):Shape
	{
		var s = new Shape();
		s.graphics.beginFill(color);
		s.graphics.drawRoundRect(-32, -22, 64, 44, 18, 18);
		s.graphics.endFill();
		return s;
	}

	function bar(color:Int):Shape
	{
		var s = new Shape();
		s.graphics.beginFill(color);
		s.graphics.drawRoundRect(-44, -6, 88, 12, 8, 8);
		s.graphics.endFill();
		return s;
	}

	/** A blue ring with a hole, centred in the cell. **/
	function ring():Shape
	{
		var s = new Shape();
		s.graphics.beginFill(0x2060FF);
		s.graphics.drawCircle(0, 0, 34);
		s.graphics.drawCircle(0, 0, 16);
		s.graphics.endFill();
		s.x = CELL / 2;
		s.y = CELL / 2;
		return s;
	}

	/** A fan of 1 px lines at many angles, the strokes the stage quality affects most. **/
	function fan():Shape
	{
		var s = new Shape();
		s.graphics.lineStyle(1, 0xFF8040);
		for (i in 0...12)
		{
			var angle = i * Math.PI / 12;
			s.graphics.moveTo(0, 0);
			s.graphics.lineTo(Math.cos(angle) * 40, Math.sin(angle) * 40);
		}
		return s;
	}
}
