package render.scenes;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.display.Graphics;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.geom.Rectangle;
import render.Scene;

/**
	The blend-mode grid of the blend-mode test suite, drawRect variant (projects/blend with
	-D blend_vector_rect, static): thirteen modes, each in 80 px cells on a grey ground.

	Cell layout: mode i sits in block i / 5 (x = 8 + block * 240) and row i % 5 (y = 8 + row * 80),
	three cells side by side: live (a LAYER holding an opaque background tile and the foreground shape in
	the mode), drawn (BitmapData.draw of the same layer) and stage (the same without the LAYER, so the
	mode works on the opaque stage). A fourth band at y = 608 (ten cells per row, x = (i % 10) * 80) holds
	the mode on a container of two overlapping children. Everything is axis-aligned integer rectangles,
	so every cell must match the AIR reference exactly.
**/
class BlendGrid extends Scene
{
	public static inline var CELL = 80;
	public static inline var TILE = 64;
	public static inline var GROUND = 0xB0B0B0;

	static var MODES:Array<BlendMode> = [
		NORMAL, ADD, SUBTRACT, DIFFERENCE, INVERT, ERASE, ALPHA, MULTIPLY, SCREEN, LIGHTEN, DARKEN, HARDLIGHT, OVERLAY
	];
	static var NAMES = [
		"normal", "add", "subtract", "difference", "invert", "erase", "alpha", "multiply", "screen", "lighten", "darken", "hardlight", "overlay"
	];

	public function new()
	{
		super();
		name = "blend_rect";
		reference = "reference/blend_rect.png";
		width = 800;
		height = 768;
		color = GROUND;
		tolerance = 8;
		for (i in 0...MODES.length)
		{
			var ax = 8 + Std.int(i / 5) * 240, ay = 8 + (i % 5) * CELL;
			cell(NAMES[i] + " live", ax, ay, CELL, CELL);
			cell(NAMES[i] + " drawn", ax + CELL, ay, CELL, CELL);
			cell(NAMES[i] + " stage", ax + CELL * 2, ay, CELL, CELL);
			cell(NAMES[i] + " container", (i % 10) * CELL, 608 + Std.int(i / 10) * CELL, CELL, CELL);
		}
	}

	override public function build(root:Sprite):Void
	{
		var ground = new Shape();
		ground.graphics.beginFill(GROUND);
		ground.graphics.drawRect(0, 0, width, height);
		ground.graphics.endFill();
		root.addChild(ground);

		for (i in 0...MODES.length)
		{
			var ax = 8 + Std.int(i / 5) * 240, ay = 8 + (i % 5) * CELL;

			var live = layer(MODES[i]);
			live.x = ax;
			live.y = ay;
			root.addChild(live);

			// drawn through BitmapData.draw onto a transparent bitmap with the ground colour
			var drawn = new BitmapData(CELL, CELL, true, 0xFF000000 | GROUND);
			drawn.draw(layer(MODES[i]));
			var bitmap = new Bitmap(drawn);
			bitmap.x = ax + CELL;
			bitmap.y = ay;
			root.addChild(bitmap);

			// the third cell: on the stage, without a LAYER
			var direct = layer(MODES[i]);
			direct.blendMode = NORMAL;
			direct.x = ax + CELL * 2;
			direct.y = ay;
			root.addChild(direct);

			// the fourth band: the mode on a container
			var nested = container(MODES[i]);
			nested.x = (i % 10) * CELL;
			nested.y = 608 + Std.int(i / 10) * CELL;
			root.addChild(nested);
		}
	}

	/** Opaque: grey ramp on top, four coloured squares below. **/
	static function background():BitmapData
	{
		var bd = new BitmapData(TILE, TILE, false, 0xFFFFFF);
		for (x in 0...TILE)
			for (y in 0...20)
				bd.setPixel32(x, y, 0xFF000000 | (Std.int(x * 255 / (TILE - 1)) * 0x010101));
		bd.fillRect(new Rectangle(0, 20, 32, 22), 0xFF2040E0);
		bd.fillRect(new Rectangle(32, 20, 32, 22), 0xFFE0C020);
		bd.fillRect(new Rectangle(0, 42, 32, 22), 0xFF20A040);
		bd.fillRect(new Rectangle(32, 42, 32, 22), 0xFFA02060);
		return bd;
	}

	/** Transparent margin, red square with a green diagonal, 50% blue square over the red and the margin. **/
	static function foreground():BitmapData
	{
		var bd = new BitmapData(TILE, TILE, true, 0);
		bd.fillRect(new Rectangle(8, 8, 40, 40), 0xFFFF0000);
		for (i in 0...36)
		{
			bd.setPixel32(10 + i, 10 + i, 0xFF00FF00);
			bd.setPixel32(11 + i, 10 + i, 0xFF00FF00);
		}
		bd.fillRect(new Rectangle(32, 32, 24, 24), 0x800000FF);
		// a mid-tone patch, so HARDLIGHT / OVERLAY / MULTIPLY / SCREEN do not degenerate to NORMAL
		bd.fillRect(new Rectangle(8, 32, 16, 16), 0xFF6090C0);
		return bd;
	}

	/** The foreground as vector fills with the same pixels: drawRect calls, which the OpenGL renderer draws as triangles. **/
	static function drawForeground(g:Graphics):Void
	{
		g.beginFill(0xFF0000);
		g.drawRect(8, 8, 40, 40);
		g.endFill();
		g.beginFill(0x00FF00);
		for (i in 0...36)
			g.drawRect(10 + i, 10 + i, 2, 1);
		g.endFill();
		g.beginFill(0x0000FF, 0.5);
		g.drawRect(32, 32, 24, 24);
		g.endFill();
		g.beginFill(0x6090C0);
		g.drawRect(8, 32, 16, 16);
		g.endFill();
	}

	/** A LAYER with the background tile and the foreground shape in `mode`. **/
	static function layer(mode:BlendMode):Sprite
	{
		var s = new Sprite();
		s.blendMode = LAYER;
		var back = new Bitmap(background());
		back.x = 4;
		back.y = 4;
		s.addChild(back);
		var front = new Shape();
		drawForeground(front.graphics);
		front.x = 12;
		front.y = 12;
		front.blendMode = mode;
		s.addChild(front);
		return s;
	}

	/** The mode on a container of two overlapping children: the foreground bitmap and, over its red square, a green / 50% white tile. **/
	static function container(mode:BlendMode):Sprite
	{
		var s = new Sprite();
		s.blendMode = LAYER;
		var back = new Bitmap(background());
		back.x = 4;
		back.y = 4;
		s.addChild(back);
		var group = new Sprite();
		group.blendMode = mode;
		group.x = 12;
		group.y = 12;
		group.addChild(new Bitmap(foreground()));
		var tile = new BitmapData(24, 24, true, 0xFF00FF00);
		tile.fillRect(new Rectangle(12, 0, 12, 24), 0x80FFFFFF);
		var top = new Bitmap(tile);
		top.x = 20;
		top.y = 20;
		group.addChild(top);
		s.addChild(group);
		return s;
	}
}
