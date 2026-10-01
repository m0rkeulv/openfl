package;

import haxe.Json;
import lime.graphics.Image;
import openfl.Assets;
import openfl.display.Sprite;
import openfl.events.Event;
import render.Compare;
import render.Scene;
import render.scenes.BlendGrid;
import render.scenes.Combined;
import render.scenes.Filters;

/**
	Runs every scene in turn: builds it, captures the window on its fourth frame, scores the capture
	against the scene's AIR reference and writes the capture, a difference image and a sheet to the
	output folder, then results.json for the run. Exits 1 if any cell fails (see README.md).

	RENDER_SCENE picks scenes by name (comma separated); RENDER_OUT is the output folder (default: out).
**/
class Main extends Sprite
{
	var scenes:Array<Scene>;
	var index = -1;
	var frame = 0;
	var advance = false;
	var failed = 0;
	var renderer:String;
	var out:String;
	var results:Array<Dynamic> = [];

	public function new()
	{
		super();
		addEventListener(Event.ADDED_TO_STAGE, function(_)
		{
			renderer = rendererName();
			out = env("RENDER_OUT", "out");
			scenes = [new BlendGrid(), new Filters(), new Combined()];
			var only = env("RENDER_SCENE", null);
			if (only != null)
			{
				var names = only.split(",");
				scenes = scenes.filter(function(s) return names.indexOf(s.name) > -1);
			}
			println('render tests on $renderer: ${scenes.length} scene(s)');
			addEventListener(Event.ENTER_FRAME, onFrame);
			next();
		});
	}

	function next():Void
	{
		index++;
		if (index >= scenes.length)
		{
			finish();
			return;
		}
		while (numChildren > 0)
			removeChildAt(0);
		var scene = scenes[index];
		stage.color = scene.color;
		stage.quality = scene.quality;
		scene.build(this);
		frame = 0;
	}

	function onFrame(_):Void
	{
		if (index >= scenes.length) return;
		if (advance)
		{
			advance = false;
			next();
			return;
		}
		// captured on frame 4: the Cairo window surface read by readPixels holds the previous frame
		if (++frame != 4) return;
		stage.window.onRender.add(capture, true);
		stage.invalidate();
	}

	function capture(_):Void
	{
		var scene = scenes[index];
		var actual = Compare.crop(Compare.normalize(stage.window.readPixels()), scene.width, scene.height);
		var expected = Compare.normalize(Assets.getBitmapData(scene.reference).image);
		var scores = Compare.score(scene, actual, expected);
		report(scene, scores);
		write(scene, actual, expected);
		advance = true;
	}

	function report(scene:Scene, scores:Array<CellScore>):Void
	{
		var failures = 0;
		println('\n== ${scene.name} on $renderer: ${scene.cells.length} cells, tolerance ${scene.tolerance}, reference ${scene.reference}');
		println(pad("cell", 38) + pad("off%", 9) + pad("interior%", 11) + pad("mean", 7) + pad("max", 5) + "verdict");
		for (s in scores)
		{
			if (!s.pass) failures++;
			var verdict = s.pass ? "pass" : 'FAIL (max ${fmt(s.maxOff)} / ${fmt(s.maxInterior)})';
			println(pad(s.name, 38) + pad(fmt(s.off), 9) + pad(fmt(s.interior), 11) + pad(fmt(s.mean), 7) + pad(Std.string(s.max), 5) + verdict);
		}
		println(failures == 0 ? "all cells pass" : '$failures cell(s) FAIL');
		failed += failures;
		results.push({name: scene.name, reference: scene.reference, tolerance: scene.tolerance, pass: failures == 0, cells: scores});
	}

	function write(scene:Scene, actual:Image, expected:Image):Void
	{
		#if sys
		sys.FileSystem.createDirectory(out);
		var base = '$out/${scene.name}_$renderer';
		var diff = Compare.diffImage(actual, expected, scene.width, scene.height);
		sys.io.File.saveBytes('$base.png', actual.encode(PNG));
		sys.io.File.saveBytes('${base}_diff.png', diff.encode(PNG));
		sys.io.File.saveBytes('${base}_sheet.png', Compare.sheet(expected, actual, diff).encode(PNG));
		println('wrote $base.png, _diff.png, _sheet.png');
		#end
	}

	function finish():Void
	{
		removeEventListener(Event.ENTER_FRAME, onFrame);
		var summary = {renderer: renderer, scenes: results};
		#if sys
		sys.FileSystem.createDirectory(out);
		sys.io.File.saveContent('$out/results_$renderer.json', Json.stringify(summary, null, "  "));
		println('\nwrote $out/results_$renderer.json');
		#else
		trace(Json.stringify(summary));
		#end
		println(failed == 0 ? "RENDER TESTS PASSED" : 'RENDER TESTS FAILED: $failed cell(s)');
		#if sys
		Sys.exit(failed == 0 ? 0 : 1);
		#end
	}

	/** The target and the kind of window it draws into, such as hl_opengl or neko_cairo. **/
	function rendererName():String
	{
		var api = switch (stage.window.context.type)
		{
			case CAIRO: "cairo";
			case CANVAS: "canvas";
			case WEBGL: "webgl";
			case DOM: "dom";
			default: "opengl";
		}
		var target = #if hl "hl" #elseif neko "neko" #elseif cpp "cpp" #elseif js "html5" #else "sys" #end;
		return '${target}_$api';
	}

	static function env(name:String, fallback:String):String
	{
		#if sys
		var value = Sys.getEnv(name);
		return value != null ? value : fallback;
		#else
		return fallback;
		#end
	}

	static function println(text:String):Void
	{
		#if sys
		Sys.println(text);
		#else
		trace(text);
		#end
	}

	static function fmt(v:Float):String
	{
		var s = Std.string(Math.round(v * 100) / 100);
		if (s.indexOf(".") < 0) s += ".00";
		else if (s.length - s.indexOf(".") == 2) s += "0";
		return s;
	}

	static function pad(s:String, width:Int):String
	{
		while (s.length < width)
			s += " ";
		return s + " ";
	}
}
