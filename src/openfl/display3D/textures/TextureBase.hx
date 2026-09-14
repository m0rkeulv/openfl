package openfl.display3D.textures;

#if !flash
import openfl.display3D._internal.GLFramebuffer;
import openfl.display3D._internal.GLRenderbuffer;
import openfl.display3D._internal.GLTexture;
import openfl.display3D._internal.ATFGPUFormat;
import openfl.display._internal.SamplerState;
import openfl.display.BitmapData;
import openfl.events.EventDispatcher;
import openfl.errors.Error;
import openfl.utils._internal.Log;
#if lime
import lime._internal.graphics.ImageCanvasUtil;
import lime.graphics.Image;
import lime.graphics.RenderContext;
import lime.graphics.WebGL2RenderContext;
import lime.graphics.opengl.GL;
#end

/**
	The TextureBase class is the base class for Context3D texture objects.

	**Note:** You cannot create your own texture classes using TextureBase. To add
	functionality to a texture class, extend either Texture or CubeTexture instead.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.display._internal.SamplerState)
@:access(openfl.display3D.Context3D)
@:access(openfl.display3D._internal.Context3DState)
@:access(openfl.display.BitmapData)
@:access(openfl.display.Stage)
class TextureBase extends EventDispatcher
{
	@:noCompletion private static var __compressedFormats:Map<Int, Int>;
	@:noCompletion private static var __compressedFormatsAlpha:Map<Int, Int>;
	@:noCompletion private static var __supportsBGRA:Null<Bool> = null;
	@:noCompletion private static var __textureFormat:Int;
	@:noCompletion private static var __textureInternalFormat:Int;

	@:noCompletion private var __alphaTexture:TextureBase;
	// private var __compressedMemoryUsage:Int;
	@:noCompletion private var __context:Context3D;
	@:noCompletion private var __format:Int;
	@:noCompletion private var __glDepthRenderbuffer:GLRenderbuffer;
	@:noCompletion private var __glFramebuffer:GLFramebuffer;
	@:noCompletion private var __glStencilRenderbuffer:GLRenderbuffer;
	// Multisampled render target, used when setRenderToTexture asks for
	// antiAlias > 0: rendering goes into a multisampled colour (+ depth/stencil)
	// renderbuffer and is resolved (blit) into the texture when the context
	// switches to another target. Needs OpenGL 3.0 / ES 3.0 / WebGL 2.
	@:noCompletion private var __glMSFramebuffer:GLFramebuffer;
	@:noCompletion private var __glMSColorRenderbuffer:GLRenderbuffer;
	@:noCompletion private var __glMSDepthStencilRenderbuffer:GLRenderbuffer;
	@:noCompletion private var __glMSSamples:Int = 0;
	@:noCompletion private var __glMSPending:Bool = false;
	@:noCompletion private static var __glMSSupported:Bool = true;
	// Shared multisampled scratch target (bounded): textures up to
	// SHARED_MULTISAMPLE_MAX on either side render into one multisampled
	// framebuffer per context that grows to the largest size seen, instead of
	// each texture allocating (and later freeing) renderbuffers of its own.
	// Larger textures keep a multisampled target of their own, allocated and
	// freed with the texture. Worst case at 4 samples: 1024^2 * 4 B * 4 * 2 = 32 MB.
	// A small ring of shared targets is used round robin: with a single one
	// every shape has to wait for the previous shape's resolve to finish reading
	// it before it can clear (write-after-read), which serialises the GPU.
	@:noCompletion private static inline var SHARED_MULTISAMPLE_MAX:Int = 1024;
	@:noCompletion private static inline var SHARED_MULTISAMPLE_TARGETS:Int = 3;
	@:noCompletion private static var __sharedMSContext:Context3D;
	@:noCompletion private static var __sharedMSFramebuffers:Array<GLFramebuffer> = [];
	@:noCompletion private static var __sharedMSColorRenderbuffers:Array<GLRenderbuffer> = [];
	@:noCompletion private static var __sharedMSDepthStencilRenderbuffers:Array<GLRenderbuffer> = [];
	@:noCompletion private static var __sharedMSNext:Int = 0;
	@:noCompletion private static var __sharedMSWidth:Int = 0;
	@:noCompletion private static var __sharedMSHeight:Int = 0;
	@:noCompletion private static var __sharedMSSamples:Int = 0;
	@:noCompletion private var __glMSShared:Bool = false;
	@:noCompletion private var __glMSSharedFramebuffer:GLFramebuffer;
	@:noCompletion private var __height:Int;
	@:noCompletion private var __internalFormat:Int;
	// private var __memoryUsage:Int;
	@:noCompletion private var __optimizeForRenderToTexture:Bool;
	// private var __outputTextureMemoryUsage:Bool = false;
	@:noCompletion private var __samplerState:SamplerState;
	@:noCompletion private var __streamingLevels:Int;
	@SuppressWarnings("checkstyle:Dynamic") @:noCompletion private var __textureContext:#if lime RenderContext #else Dynamic #end;
	@:noCompletion private var __textureID:GLTexture;
	@:noCompletion private var __textureTarget:Int;
	@:noCompletion private var __width:Int;

	@:noCompletion private function new(context:Context3D)
	{
		super();

		__context = context;
		var gl = __context.gl;
		// __textureTarget = target;

		__textureID = gl.createTexture();
		__textureContext = __context.__context;

		if (__supportsBGRA == null)
		{
			__textureInternalFormat = gl.RGBA;

			var bgraExtension:Dynamic = null;
			#if (!js || !html5)
			bgraExtension = gl.getExtension("EXT_bgra");
			if (bgraExtension == null) bgraExtension = gl.getExtension("EXT_texture_format_BGRA8888");
			if (bgraExtension == null) bgraExtension = gl.getExtension("APPLE_texture_format_BGRA8888");
			#end

			if (bgraExtension != null)
			{
				__supportsBGRA = true;
				__textureFormat = bgraExtension.BGRA_EXT;

				#if (lime && !ios && !tvos)
				if (context.__context.type == OPENGLES)
				{
					__textureInternalFormat = bgraExtension.BGRA_EXT;
				}
				#end
			}
			else
			{
				__supportsBGRA = false;
				__textureFormat = gl.RGBA;
			}

			__compressedFormats = new Map();
			__compressedFormatsAlpha = new Map();

			#if (js && html5)
			var dxtExtension = gl.getExtension("WEBGL_compressed_texture_s3tc");
			var etc1Extension = gl.getExtension("WEBGL_compressed_texture_etc1");
			// WEBGL_compressed_texture_pvrtc is not available on iOS Safari
			var pvrtcExtension = gl.getExtension("WEBKIT_WEBGL_compressed_texture_pvrtc");
			#else
			var dxtExtension = gl.getExtension("EXT_texture_compression_s3tc");
			var etc1Extension = gl.getExtension("OES_compressed_ETC1_RGB8_texture");
			var pvrtcExtension = gl.getExtension("IMG_texture_compression_pvrtc");
			#end

			if (dxtExtension != null)
			{
				__compressedFormats[ATFGPUFormat.DXT] = dxtExtension.COMPRESSED_RGBA_S3TC_DXT1_EXT;
				__compressedFormatsAlpha[ATFGPUFormat.DXT] = dxtExtension.COMPRESSED_RGBA_S3TC_DXT5_EXT;
			}

			if (etc1Extension != null)
			{
				#if (js && html5)
				__compressedFormats[ATFGPUFormat.ETC1] = etc1Extension.COMPRESSED_RGB_ETC1_WEBGL;
				__compressedFormatsAlpha[ATFGPUFormat.ETC1] = etc1Extension.COMPRESSED_RGB_ETC1_WEBGL;
				#else
				__compressedFormats[ATFGPUFormat.ETC1] = etc1Extension.ETC1_RGB8_OES;
				__compressedFormatsAlpha[ATFGPUFormat.ETC1] = etc1Extension.ETC1_RGB8_OES;
				#end
			}

			if (pvrtcExtension != null)
			{
				__compressedFormats[ATFGPUFormat.PVRTC] = pvrtcExtension.COMPRESSED_RGB_PVRTC_4BPPV1_IMG;
				__compressedFormatsAlpha[ATFGPUFormat.PVRTC] = pvrtcExtension.COMPRESSED_RGBA_PVRTC_4BPPV1_IMG;
			}
		}

		__internalFormat = __textureInternalFormat;
		__format = __textureFormat;

		// __memoryUsage = 0;
		// __compressedMemoryUsage = 0;
	}

	/**
		Frees all GPU resources associated with this texture. After disposal, calling
		`upload()` or rendering with this object fails.
	**/
	public function dispose():Void
	{
		var gl = __context.gl;

		if (__alphaTexture != null)
		{
			__alphaTexture.dispose();
			__alphaTexture = null;
		}

		if (__textureID != null)
		{
			gl.deleteTexture(__textureID);
			__textureID = null;
		}

		if (__glFramebuffer != null)
		{
			gl.deleteFramebuffer(__glFramebuffer);
			__glFramebuffer = null;
		}

		if (__glDepthRenderbuffer != null)
		{
			gl.deleteRenderbuffer(__glDepthRenderbuffer);
			__glDepthRenderbuffer = null;
		}

		if (__glStencilRenderbuffer != null)
		{
			gl.deleteRenderbuffer(__glStencilRenderbuffer);
			__glStencilRenderbuffer = null;
		}

		__deleteGLMultisample();
	}

	@SuppressWarnings("checkstyle:Dynamic")
	@:noCompletion private function __getGLFramebuffer(enableDepthAndStencil:Bool, antiAlias:Int, surfaceSelector:Int):GLFramebuffer
	{
		var gl = __context.gl;

		if (__glFramebuffer == null)
		{
			__glFramebuffer = gl.createFramebuffer();
			__context.__bindGLFramebuffer(__glFramebuffer);
			gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, __textureID, 0);

			if (__context.__enableErrorChecking)
			{
				var code = gl.checkFramebufferStatus(gl.FRAMEBUFFER);

				if (code != gl.FRAMEBUFFER_COMPLETE)
				{
					Log.warn('Error: Context3D.setRenderToTexture status:${code} width:${__width} height:${__height}');
				}
			}
		}

		if (antiAlias > 0 #if gpu_msaa_off && false #end)
		{
			var multisampled = __getGLMultisampleFramebuffer(enableDepthAndStencil, antiAlias);
			if (multisampled != null)
			{
				__glMSPending = true;
				return multisampled;
			}
		}

		if (enableDepthAndStencil && __glDepthRenderbuffer == null)
		{
			__context.__bindGLFramebuffer(__glFramebuffer);

			if (Context3D.__glDepthStencil != 0)
			{
				__glDepthRenderbuffer = gl.createRenderbuffer();
				__glStencilRenderbuffer = __glDepthRenderbuffer;

				gl.bindRenderbuffer(gl.RENDERBUFFER, __glDepthRenderbuffer);
				gl.renderbufferStorage(gl.RENDERBUFFER, Context3D.__glDepthStencil, __width, __height);
				gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, __glDepthRenderbuffer);
			}
			else
			{
				__glDepthRenderbuffer = gl.createRenderbuffer();
				__glStencilRenderbuffer = gl.createRenderbuffer();

				gl.bindRenderbuffer(gl.RENDERBUFFER, __glDepthRenderbuffer);
				gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT16, __width, __height);
				gl.bindRenderbuffer(gl.RENDERBUFFER, __glStencilRenderbuffer);
				gl.renderbufferStorage(gl.RENDERBUFFER, gl.STENCIL_INDEX8, __width, __height);

				gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, __glDepthRenderbuffer);
				gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.STENCIL_ATTACHMENT, gl.RENDERBUFFER, __glStencilRenderbuffer);
			}

			if (__context.__enableErrorChecking)
			{
				var code = gl.checkFramebufferStatus(gl.FRAMEBUFFER);

				if (code != gl.FRAMEBUFFER_COMPLETE)
				{
					Log.warn('Error: Context3D.setRenderToTexture status:${code} width:${__width} height:${__height}');
				}
			}

			gl.bindRenderbuffer(gl.RENDERBUFFER, null);
		}

		return __glFramebuffer;
	}

	@:noCompletion private function __getGLMultisampleFramebuffer(enableDepthAndStencil:Bool, antiAlias:Int):GLFramebuffer
	{
		#if lime
		if (!__glMSSupported) return null;
		var gl2:WebGL2RenderContext = #if (js && html5) __context.__context.webgl2 #else GL #end;
		if (gl2 == null)
		{
			__glMSSupported = false;
			return null;
		}

		var samples = antiAlias;
		var maxSamples:Int = gl2.getParameter(gl2.MAX_SAMPLES);
		if (maxSamples < 2)
		{
			__glMSSupported = false;
			return null;
		}
		if (samples > maxSamples) samples = maxSamples;

		if (__width <= SHARED_MULTISAMPLE_MAX && __height <= SHARED_MULTISAMPLE_MAX)
		{
			var shared = __getSharedGLMultisampleFramebuffer(gl2, samples);
			if (shared != null)
			{
				__glMSShared = true;
				return shared;
			}
		}
		__glMSShared = false;

		if (__glMSFramebuffer != null && __glMSSamples == samples) return __glMSFramebuffer;

		__deleteGLMultisample();
		__glMSFramebuffer = gl2.createFramebuffer();
		__context.__bindGLFramebuffer(__glMSFramebuffer);

		__glMSColorRenderbuffer = gl2.createRenderbuffer();
		gl2.bindRenderbuffer(gl2.RENDERBUFFER, __glMSColorRenderbuffer);
		gl2.renderbufferStorageMultisample(gl2.RENDERBUFFER, samples, gl2.RGBA8, __width, __height);
		gl2.framebufferRenderbuffer(gl2.FRAMEBUFFER, gl2.COLOR_ATTACHMENT0, gl2.RENDERBUFFER, __glMSColorRenderbuffer);

		if (enableDepthAndStencil)
		{
			__glMSDepthStencilRenderbuffer = gl2.createRenderbuffer();
			gl2.bindRenderbuffer(gl2.RENDERBUFFER, __glMSDepthStencilRenderbuffer);
			gl2.renderbufferStorageMultisample(gl2.RENDERBUFFER, samples, gl2.DEPTH24_STENCIL8, __width, __height);
			gl2.framebufferRenderbuffer(gl2.FRAMEBUFFER, gl2.DEPTH_STENCIL_ATTACHMENT, gl2.RENDERBUFFER, __glMSDepthStencilRenderbuffer);
		}

		gl2.bindRenderbuffer(gl2.RENDERBUFFER, null);

		var code = gl2.checkFramebufferStatus(gl2.FRAMEBUFFER);
		if (code != gl2.FRAMEBUFFER_COMPLETE)
		{
			Log.warn('Error: multisampled Context3D.setRenderToTexture status:${code} samples:${samples} width:${__width} height:${__height}');
			__deleteGLMultisample();
			__glMSSupported = false;
			return null;
		}

		__glMSSamples = samples;
		#if gpu_msaa_debug Sys.println('MSAA fbo created samples=' + samples + ' max=' + maxSamples + ' size=' + __width + 'x' + __height + ' status=' + code + ' err=' + gl2.getError()); #end
		return __glMSFramebuffer;
		#else
		return null;
		#end
	}

	@:noCompletion private function __getSharedGLMultisampleFramebuffer(gl2:WebGL2RenderContext, samples:Int):GLFramebuffer
	{
		var w = __width > __sharedMSWidth ? __width : __sharedMSWidth;
		var h = __height > __sharedMSHeight ? __height : __sharedMSHeight;
		if (__sharedMSFramebuffers.length == 0 || __sharedMSContext != __context || __sharedMSSamples != samples || w != __sharedMSWidth || h != __sharedMSHeight)
		{
			// (re)create the ring at the grown size; the previous target was resolved
			// before Context3D switched to this texture, so nothing pending is lost
			__deleteSharedGLMultisample();
			for (i in 0...SHARED_MULTISAMPLE_TARGETS)
			{
				var fbo = gl2.createFramebuffer();
				__context.__bindGLFramebuffer(fbo);
				var color = gl2.createRenderbuffer();
				gl2.bindRenderbuffer(gl2.RENDERBUFFER, color);
				gl2.renderbufferStorageMultisample(gl2.RENDERBUFFER, samples, gl2.RGBA8, w, h);
				gl2.framebufferRenderbuffer(gl2.FRAMEBUFFER, gl2.COLOR_ATTACHMENT0, gl2.RENDERBUFFER, color);
				var depthStencil = gl2.createRenderbuffer();
				gl2.bindRenderbuffer(gl2.RENDERBUFFER, depthStencil);
				gl2.renderbufferStorageMultisample(gl2.RENDERBUFFER, samples, gl2.DEPTH24_STENCIL8, w, h);
				gl2.framebufferRenderbuffer(gl2.FRAMEBUFFER, gl2.DEPTH_STENCIL_ATTACHMENT, gl2.RENDERBUFFER, depthStencil);
				gl2.bindRenderbuffer(gl2.RENDERBUFFER, null);
				__sharedMSFramebuffers.push(fbo);
				__sharedMSColorRenderbuffers.push(color);
				__sharedMSDepthStencilRenderbuffers.push(depthStencil);

				var code = gl2.checkFramebufferStatus(gl2.FRAMEBUFFER);
				if (code != gl2.FRAMEBUFFER_COMPLETE)
				{
					Log.warn('Error: shared multisampled render target status:' + code + ' samples:' + samples + ' size:' + w + 'x' + h);
					__deleteSharedGLMultisample();
					return null;
				}
			}
			__sharedMSContext = __context;
			__sharedMSWidth = w;
			__sharedMSHeight = h;
			__sharedMSSamples = samples;
			__sharedMSNext = 0;
		}

		__glMSSharedFramebuffer = __sharedMSFramebuffers[__sharedMSNext];
		__sharedMSNext = (__sharedMSNext + 1) % SHARED_MULTISAMPLE_TARGETS;
		return __glMSSharedFramebuffer;
	}

	@:noCompletion private function __deleteSharedGLMultisample():Void
	{
		if (__sharedMSContext != null && __sharedMSContext != __context) return;
		var gl = __context.gl;
		for (fbo in __sharedMSFramebuffers) gl.deleteFramebuffer(fbo);
		for (rb in __sharedMSColorRenderbuffers) gl.deleteRenderbuffer(rb);
		for (rb in __sharedMSDepthStencilRenderbuffers) gl.deleteRenderbuffer(rb);
		__sharedMSFramebuffers = [];
		__sharedMSColorRenderbuffers = [];
		__sharedMSDepthStencilRenderbuffers = [];
		__sharedMSWidth = 0;
		__sharedMSHeight = 0;
	}

	// Resolve (blit) the multisampled target into the texture. Context3D calls
	// this when it switches away from this render target; a no-op unless the
	// multisampled target was bound since the last resolve.
	@:noCompletion private function __resolveGLMultisample():Void
	{
		#if lime
		if (!__glMSPending) return;
		var source = __glMSShared ? __glMSSharedFramebuffer : __glMSFramebuffer;
		if (source == null) return;
		var gl2:WebGL2RenderContext = #if (js && html5) __context.__context.webgl2 #else GL #end;
		gl2.bindFramebuffer(gl2.READ_FRAMEBUFFER, source);
		gl2.bindFramebuffer(gl2.DRAW_FRAMEBUFFER, __glFramebuffer);
		gl2.blitFramebuffer(0, 0, __width, __height, 0, 0, __width, __height, gl2.COLOR_BUFFER_BIT, gl2.NEAREST);
#if gpu_msaa_debug Sys.println('MSAA resolve ' + __width + 'x' + __height + ' readStatus=' + gl2.checkFramebufferStatus(gl2.READ_FRAMEBUFFER) + ' drawStatus=' + gl2.checkFramebufferStatus(gl2.DRAW_FRAMEBUFFER) + ' err=' + gl2.getError()); #end
		// the read/draw bindings replaced the FRAMEBUFFER binding: put back the one
		// the context believes is bound (clearing the cache would not work: the
		// stage's primary framebuffer is null too, so the next bind would be skipped)
		gl2.bindFramebuffer(gl2.FRAMEBUFFER, __context.__contextState.__currentGLFramebuffer);
		__glMSPending = false;
		#end
	}

	@:noCompletion private function __deleteGLMultisample():Void
	{
		var gl = __context.gl;
		if (__glMSFramebuffer != null)
		{
			gl.deleteFramebuffer(__glMSFramebuffer);
			__glMSFramebuffer = null;
		}
		if (__glMSColorRenderbuffer != null)
		{
			gl.deleteRenderbuffer(__glMSColorRenderbuffer);
			__glMSColorRenderbuffer = null;
		}
		if (__glMSDepthStencilRenderbuffer != null)
		{
			gl.deleteRenderbuffer(__glMSDepthStencilRenderbuffer);
			__glMSDepthStencilRenderbuffer = null;
		}
		__glMSSamples = 0;
		__glMSPending = false;
		__glMSShared = false;
	}

	#if lime
	@:noCompletion private function __getImage(bitmapData:BitmapData):Image
	{
		var image = bitmapData.image;

		if (!bitmapData.__isValid || image == null)
		{
			return null;
		}

		#if (js && html5)
		ImageCanvasUtil.sync(image, false);
		#end

		#if (js && html5)
		var gl = __context.gl;

		if (image.type != DATA && !image.premultiplied)
		{
			gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, 1);
		}
		else if (!image.premultiplied && image.transparent)
		{
			gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, 0);
			image = image.clone();
			image.premultiplied = true;
		}

		// TODO: Some way to support BGRA on WebGL?

		if (image.format != RGBA32)
		{
			image = image.clone();
			image.format = RGBA32;
			image.buffer.premultiplied = true;
			#if openfl_power_of_two
			image.powerOfTwo = true;
			#end
		}
		#else
		if (#if openfl_power_of_two !image.powerOfTwo || #end (!image.premultiplied && image.transparent))
		{
			image = image.clone();
			image.premultiplied = true;
			#if openfl_power_of_two
			image.powerOfTwo = true;
			#end
		}
		#end

		return image;
	}
	#end

	@:noCompletion private function __getTexture():GLTexture
	{
		return __textureID;
	}

	@:noCompletion private function __setSamplerState(state:SamplerState):Bool
	{
		if (!state.equals(__samplerState))
		{
			var gl = __context.gl;

			if (__textureTarget == __context.gl.TEXTURE_CUBE_MAP) __context.__bindGLTextureCubeMap(__textureID);
			else
				__context.__bindGLTexture2D(__textureID);

			var wrapModeS = 0, wrapModeT = 0;

			switch (state.wrap)
			{
				case CLAMP:
					wrapModeS = gl.CLAMP_TO_EDGE;
					wrapModeT = gl.CLAMP_TO_EDGE;
				case CLAMP_U_REPEAT_V:
					wrapModeS = gl.CLAMP_TO_EDGE;
					wrapModeT = gl.REPEAT;
				case REPEAT:
					wrapModeS = gl.REPEAT;
					wrapModeT = gl.REPEAT;
				case REPEAT_U_CLAMP_V:
					wrapModeS = gl.REPEAT;
					wrapModeT = gl.CLAMP_TO_EDGE;
				default:
					throw new Error("wrap bad enum");
			}

			var magFilter = 0, minFilter = 0;

			switch (state.filter)
			{
				case NEAREST:
					magFilter = gl.NEAREST;
				default:
					magFilter = gl.LINEAR;
			}

			switch (state.mipfilter)
			{
				case MIPLINEAR:
					minFilter = state.filter == NEAREST ? gl.NEAREST_MIPMAP_LINEAR : gl.LINEAR_MIPMAP_LINEAR;
				case MIPNEAREST:
					minFilter = state.filter == NEAREST ? gl.NEAREST_MIPMAP_NEAREST : gl.LINEAR_MIPMAP_NEAREST;
				case Context3DMipFilter.MIPNONE:
					minFilter = state.filter == NEAREST ? gl.NEAREST : gl.LINEAR;
				default:
					throw new Error("mipfiter bad enum");
			}

			gl.texParameteri(__textureTarget, gl.TEXTURE_MIN_FILTER, minFilter);
			gl.texParameteri(__textureTarget, gl.TEXTURE_MAG_FILTER, magFilter);
			gl.texParameteri(__textureTarget, gl.TEXTURE_WRAP_S, wrapModeS);
			gl.texParameteri(__textureTarget, gl.TEXTURE_WRAP_T, wrapModeT);

			if (state.lodBias != 0.0)
			{
				// TODO
				// throw new IllegalOperationError("Lod bias setting not supported yet");
			}

			if (__samplerState == null) __samplerState = state.clone();
			__samplerState.copyFrom(state);

			return true;
		}

		return false;
	}

	#if lime
	@:noCompletion private function __uploadFromImage(image:Image):Void
	{
		var gl = __context.gl;
		var internalFormat:Int;
		var format:Int;

		if (__textureTarget != gl.TEXTURE_2D) return;

		if (image.buffer.bitsPerPixel == 1)
		{
			internalFormat = gl.ALPHA;
			format = gl.ALPHA;
		}
		else
		{
			internalFormat = TextureBase.__textureInternalFormat;
			format = TextureBase.__textureFormat;
		}

		__context.__bindGLTexture2D(__textureID);

		#if (js && html5)
		if (image.type != DATA && !image.premultiplied)
		{
			gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, 1);
		}
		else if (!image.premultiplied && image.transparent)
		{
			gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, 1);
			// gl.pixelStorei (gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, 0);
			// textureImage = textureImage.clone ();
			// textureImage.premultiplied = true;
		}

		if (image.type == DATA)
		{
			gl.texImage2D(gl.TEXTURE_2D, 0, internalFormat, image.buffer.width, image.buffer.height, 0, format, gl.UNSIGNED_BYTE, image.data);
		}
		else
		{
			gl.texImage2D(gl.TEXTURE_2D, 0, internalFormat, format, gl.UNSIGNED_BYTE, image.src);
		}
		#else
		gl.texImage2D(gl.TEXTURE_2D, 0, internalFormat, image.buffer.width, image.buffer.height, 0, format, gl.UNSIGNED_BYTE, image.data);
		#end

		__context.__bindGLTexture2D(null);
	}
	#end
}
#else
typedef TextureBase = flash.display3D.textures.TextureBase;
#end
