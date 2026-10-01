package render;

import haxe.io.Bytes;
import lime.graphics.Image;
import lime.math.Rectangle;
import lime.math.Vector2;
import render.Scene;

typedef CellScore =
{
	name:String,
	/** Percent of the cell's pixels off by more than the tolerance. **/
	off:Float,
	/** Percent of the cell's pixels off by more than the tolerance and not within one pixel of an edge. **/
	interior:Float,
	/** Mean of the largest channel difference per pixel, 0 to 255. **/
	mean:Float,
	max:Int,
	maxOff:Float,
	maxInterior:Float,
	pass:Bool
}

/**
	Scores a capture against its reference cell by cell.

	A pixel is off when its largest channel difference exceeds the scene's tolerance. Two shares are
	measured per cell: all pixels off, and pixels off away from any edge. An edge pixel differs from one
	of its eight neighbours by more than the tolerance, in either image, and the pixels next to it count
	as edge too, so a shift or a different anti-aliasing of an outline lands in the first share only. A
	wrong colour, a missing shape or a mask the wrong size changes flat areas and lands in both.
**/
class Compare
{
	/** A copy in one layout, RGBA with straight alpha, whatever the source held. **/
	public static function normalize(image:Image):Image
	{
		var copy = image.clone();
		copy.format = RGBA32;
		copy.premultiplied = false;
		return copy;
	}

	public static function score(scene:Scene, actual:Image, expected:Image):Array<CellScore>
	{
		var width = scene.width, height = scene.height;
		var diff = differences(actual, expected, width, height);
		var edge = edges(actual, expected, width, height, scene.tolerance);
		var scores = [];
		for (c in scene.cells)
		{
			var off = 0, interior = 0, sum = 0, max = 0;
			for (y in c.y...c.y + c.height)
			{
				for (x in c.x...c.x + c.width)
				{
					var i = y * width + x;
					var d = diff.get(i);
					sum += d;
					if (d > max) max = d;
					if (d > scene.tolerance)
					{
						off++;
						if (edge.get(i) == 0) interior++;
					}
				}
			}
			var n = c.width * c.height;
			var maxOff = c.maxOff != null ? c.maxOff : scene.maxOff;
			var maxInterior = c.maxInterior != null ? c.maxInterior : scene.maxInterior;
			var offPercent = 100.0 * off / n, interiorPercent = 100.0 * interior / n;
			scores.push({
				name: c.name,
				off: offPercent,
				interior: interiorPercent,
				mean: sum / n,
				max: max,
				maxOff: maxOff,
				maxInterior: maxInterior,
				pass: offPercent <= maxOff && interiorPercent <= maxInterior
			});
		}
		return scores;
	}

	/** The largest channel difference per pixel over the scene's area, one byte each. **/
	static function differences(a:Image, e:Image, width:Int, height:Int):Bytes
	{
		var out = Bytes.alloc(width * height);
		var ad = a.data, ed = e.data, aw = a.width, ew = e.width;
		for (y in 0...height)
		{
			for (x in 0...width)
			{
				var i = (y * aw + x) * 4, j = (y * ew + x) * 4;
				var d = abs(ad[i] - ed[j]);
				var g = abs(ad[i + 1] - ed[j + 1]);
				var b = abs(ad[i + 2] - ed[j + 2]);
				if (g > d) d = g;
				if (b > d) d = b;
				out.set(y * width + x, d);
			}
		}
		return out;
	}

	/** 1 where a pixel is within one pixel of an edge in either image, 0 elsewhere. **/
	static function edges(a:Image, e:Image, width:Int, height:Int, tolerance:Int):Bytes
	{
		var steep = Bytes.alloc(width * height);
		mark(a, width, height, tolerance, steep);
		mark(e, width, height, tolerance, steep);
		var out = Bytes.alloc(width * height);
		for (y in 0...height)
		{
			for (x in 0...width)
			{
				var hit = 0;
				for (dy in -1...2)
				{
					var yy = y + dy;
					if (yy < 0 || yy >= height) continue;
					for (dx in -1...2)
					{
						var xx = x + dx;
						if (xx >= 0 && xx < width && steep.get(yy * width + xx) != 0) hit = 1;
					}
				}
				out.set(y * width + x, hit);
			}
		}
		return out;
	}

	/** Sets `steep` to 1 where a pixel of `image` differs from one of its eight neighbours by more than the tolerance. **/
	static function mark(image:Image, width:Int, height:Int, tolerance:Int, steep:Bytes):Void
	{
		var d = image.data, stride = image.width;
		for (y in 0...height)
		{
			for (x in 0...width)
			{
				var i = (y * stride + x) * 4;
				var found = false;
				for (dy in -1...2)
				{
					var yy = y + dy;
					if (yy < 0 || yy >= height) continue;
					for (dx in -1...2)
					{
						var xx = x + dx;
						if (found || xx < 0 || xx >= width || (dx == 0 && dy == 0)) continue;
						var j = (yy * stride + xx) * 4;
						if (abs(d[i] - d[j]) > tolerance || abs(d[i + 1] - d[j + 1]) > tolerance || abs(d[i + 2] - d[j + 2]) > tolerance) found = true;
					}
				}
				if (found) steep.set(y * width + x, 1);
			}
		}
	}

	/** The capture over the scene's area only. **/
	public static function crop(image:Image, width:Int, height:Int):Image
	{
		var out = new Image(null, 0, 0, width, height, 0x000000FF);
		out.copyPixels(image, new Rectangle(0, 0, width, height), new Vector2(0, 0));
		return out;
	}

	/** The differences four times brighter, as a grey image. **/
	public static function diffImage(actual:Image, expected:Image, width:Int, height:Int):Image
	{
		var diff = differences(actual, expected, width, height);
		var out = new Image(null, 0, 0, width, height, 0x000000FF);
		var d = out.data;
		for (i in 0...width * height)
		{
			var v = diff.get(i) * 4;
			if (v > 255) v = 255;
			d[i * 4] = d[i * 4 + 1] = d[i * 4 + 2] = v;
			d[i * 4 + 3] = 255;
		}
		return out;
	}

	/** Reference, capture and difference side by side (colours here are RGBA, the images' format). **/
	public static function sheet(expected:Image, actual:Image, diff:Image):Image
	{
		var gap = 8, w = expected.width, h = expected.height;
		var out = new Image(null, 0, 0, w * 3 + gap * 2, h, 0x202020FF);
		var rect = new Rectangle(0, 0, w, h);
		out.copyPixels(expected, rect, new Vector2(0, 0));
		out.copyPixels(actual, rect, new Vector2(w + gap, 0));
		out.copyPixels(diff, rect, new Vector2((w + gap) * 2, 0));
		return out;
	}

	static inline function abs(v:Int):Int
	{
		return v < 0 ? -v : v;
	}
}
