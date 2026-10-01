import hxp.*;

/**
	The render test group for `hxp test`: builds the test app for the target and runs it, so the app's
	exit code is the group's result. -Dsoftware (or RENDER_SOFTWARE=1 in the environment) gives a Cairo
	window; so does SDL_VIDEODRIVER=dummy, which has no OpenGL and needs no display. With
	LIBGL_ALWAYS_SOFTWARE set (Mesa's llvmpipe) the OpenGL renderer waits for the framebuffer before
	copying it (-Dopenfl_gl_sync_backdrop). Outputs land in out/<target>[_software] (see README.md).
**/
class Build extends Script
{
	public function new()
	{
		super();

		var target = defines.exists("target") ? defines.get("target") : "neko";
		if (target != "hl" && target != "neko" && target != "cpp")
		{
			Log.println('render tests: nothing to run for target "$target"');
			return;
		}

		var software = defines.exists("software") || Sys.getEnv("RENDER_SOFTWARE") != null || Sys.getEnv("SDL_VIDEODRIVER") == "dummy";
		var args = ["run", "lime", "build", target];
		if (software) args.push("-Dsoftware");
		if (Sys.getEnv("LIBGL_ALWAYS_SOFTWARE") != null) args.push("-Dopenfl_gl_sync_backdrop");
		if (Log.verbose) args.push("-verbose");
		System.runCommand("", "haxelib", args);

		var bin = Path.combine(Sys.getCwd(), 'Export/$target/bin');
		var exe = System.hostPlatform == WINDOWS ? "RenderTests.exe" : "RenderTests";
		Sys.putEnv("RENDER_OUT", Path.combine(Sys.getCwd(), "out/" + target + (software ? "_software" : "")));
		System.runCommand(bin, Path.combine(bin, exe), []);
	}
}
