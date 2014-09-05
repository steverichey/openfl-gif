package extension.gif;

import openfl.utils.ByteArray;
import openfl.display.BitmapData;
import openfl.display.Bitmap;

#if !flash
import sys.io.File;
#end

/**
 * This class lets you encode animated GIF files.
 * Based on https://code.google.com/p/as3gif/
 * Base class: http://www.java2s.com/Code/Java/2D-Graphics-GUI/AnimatedGifEncoder.htm
 * 
 * @author Steve Richey (Haxe/OpenFL version)
 * @author Thibault Imbert (AS3 version - bytearray.org)
 * @author Kevin Weiner (original Java version - kweiner@fmsware.com)
 * 
 * @version 0.1 Haxe implementation
 */
class GIFEncoder
{
	/**
	 * Width of the image. This can only be set before the first frame has been added. If not set, will default to width of the first frame.
	 */
	public var width(default, set):UInt = 0;
	/**
	 * Height of the image. This can only be set before the first frame has been added. If not set, will default to height of the first frame.
	 */
	public var height(default, set):UInt = 0;
	/**
	 * Whether or not we are ready to output frames.
	 */
	public var started(default, null):Bool = false;
	/**
	 * Frame delay in milliseconds.
	 */
	public var delay:UInt = 0;
	/**
	 * Another way of setting frame delay, this is the GIF framerate in frames per second.
	 */
	public var framerate(get, set):Float;
	/**
	 * Sets quality of color quantization (conversion of images to the maximum 256 colors allowed by the GIF specification). Lower values (minimum = 1)
	 * produce better colors, but slow processing significantly. 10 is the default, and produces good color mapping at reasonable speeds. Values
	 * greater than 20 do not yield significant improvements in speed.
	 */
	public var quality(default, set):UInt = 10;
	/**
	 * How many times the GIF will repeat. Set to -1 for no repeat, or 0 for infinite repeats.
	 */
	public var repeat(default, set):Int = 0;
	/**
	 * The transparent color, if given. Sets the transparent color for the last added frame and any subsequent frames. Since all colors are subject to modification in the quantization
	 * process, the color in the final palette for each frame closest to the given color becomes the transparent color for that frame. May be set to null to indicate no transparent color.
	 */
	public var transparent:Null<UInt> = 0;
	/**
	 * Sets the GIF frame disposal code for the last added frame and any subsequent frames. Default is 0 if no transparent color has been set, otherwise 2. (-1 = use default)
	 */
	public var dispose(default, set):Int = -1;
	/**
	 * The output ByteArray. Read-only. Can only be used to write a valid GIF file after finish() has been called.
	 */
	public var output(default, null):ByteArray;
	/**
	 * Transparent index in color table.
	 */
	private var transIndex:UInt = 0;
	/**
	 * BGR byte array from frame.
	 */
	private var pixels:ByteArray;
	/**
	 * Converted frame indexed to palette.
	 */
	private var indexedPixels:ByteArray;
	/**
	 * Number of bit planes.
	 */
	private var colorDepth:Int = 0;
	/**
	 * RGB palette.
	 */
	private var colorTab:ByteArray;
	/**
	 * Active palette entries.
	 */
	private var usedEntry:Array<Bool> = [];
	/**
	 * Color table size (bits - 1).
	 */
	private var palSize:Int = 7;
	/**
	 * True if the first frame is being set.
	 */
	private var firstFrame:Bool = true;
	
	/**
	 * Instantiate object and call start()
	 */
	public function new()
	{
		start();
	}
	
	/**
	* Initiates GIF file creation on the given stream, and resets some members so that a new stream can be started.
	* After calling start(), call addFrame() to add additional frames, and call finish() when done.
	* 
	* @return This GIFEncoder object.
	*/
	public function start():GIFEncoder
	{
		transIndex = 0;
		
		pixels = null;
		indexedPixels = null;
		colorTab = null;
		
		firstFrame = true;
		
		output = new ByteArray();
		output.writeUTFBytes("GIF89a"); // header
		
		started = true;
		
		return this;
	}

	/**
	 * The addFrame method takes an incoming BitmapData object to create the next frame in the GIF.
	 * If you haven't called start() yet, it will be called. Call finish() when done adding frames.
	 * 
	 * @param	NextFrame  The BitmapData object to treat as a frame.
	 * @return	This GIFEncoder object.
	 */
	public function addFrame(NextFrame:BitmapData):GIFEncoder
	{
		if (!started)
		{
			start();
		}
		
		if (NextFrame == null)
		{
			return this;
		}
		
		if (width <= 1 || height <= 1)
		{
			width = NextFrame.width;
			height = NextFrame.height;
		}
		
		getImagePixels(NextFrame); // convert to correct format if necessary
		analyzePixels(); // build color table & map pixels
		
		if (firstFrame) 
		{
			writeLSD(); // logical screen descriptior
			writePalette(); // global color table
			
			if (repeat >= 0) 
			{
				// use NS app extension to indicate reps
				writeNetscapeExt();
			}
		}
		
		writeGraphicCtrlExt(); // write graphic control extension
		writeImageDesc(); // image descriptor
		
		if (!firstFrame)
		{
			writePalette(); // local color table
		}
		
		writePixels(); // encode and write pixel data
		
		firstFrame = false;
		
		return this;
	}
	
	/**
	* Adds final trailer to the GIF stream, if you don't call the finish method the GIF stream will not be valid.
	* Before calling this, call start() to begin, and call addFrame() to add frames to the animation.
	*/
	public function finish():GIFEncoder
	{
		if (!started)
		{
			return this;
		}
		
		output.writeByte(0x3b); // gif trailer
		
		return this;
	}
	
	/**
	* Analyzes image colors and creates color map.
	*/
	private inline function analyzePixels():ByteArray
	{
		var len:Int = pixels.length;
		var nPix:Int = Std.int(len / 3);
		indexedPixels = new ByteArray();
		//var nq:NeuQuant = new NeuQuant(pixels, len, quality);
		var nq:NeuQuant = new NeuQuant();
		
		// initialize quantizer
		
		//colorTab = nq.process(); // create reduced palette
		
		nq.quantize(pixels, true, colorDepth, 1, quality, true);
		
		colorTab = nq.getColorMap();
		
		// map image pixels to new palette
		
		var k:Int = 0;
		
		for (j in 0...nPix)
		{
			//var index:Int = nq.map(pixels[k++] & 0xff, pixels[k++] & 0xff, pixels[k++] & 0xff);
			var index:Int = nq.getColor(pixels[k++] & 0xff << 16 | pixels[k++] & 0xff << 8 | pixels[k++] & 0xff);
			usedEntry[index] = true;
			indexedPixels[j] = index;
		}
		
		pixels = null;
		colorDepth = 8;
		palSize = 7;
		
		// get closest match to transparent color if specified
		
		if (transparent != null)
		{
			transIndex = findClosest(transparent);
		}
		
		return indexedPixels;
	}
	
	/**
	* Returns index of palette color closest to color.
	*/
	private inline function findClosest(Color:Int):Int
	{
		if (colorTab == null)
		{
			return -1;
		}
		
		var r:Int = (Color & 0xFF0000) >> 16;
		var g:Int = (Color & 0x00FF00) >> 8;
		var b:Int = (Color & 0x0000FF);
		var minpos:Int = 0;
		var dmin:Int = 256 * 256 * 256;
		var len:Int = colorTab.length;
		
		var i:Int = 0;
		
		while (i < len)
		{
			var dr:Int = r - (colorTab[i++] & 0xff);
			var dg:Int = g - (colorTab[i++] & 0xff);
			var db:Int = b - (colorTab[i] & 0xff);
			var d:Int = dr * dr + dg * dg + db * db;
			var index:Int = Std.int(i / 3);
		  
			if (usedEntry[index] && (d < dmin))
			{
				dmin = d;
				minpos = index;
			}
			
			i++;
		}
		
		return minpos;
	}
	
	/**
	* Extracts image pixels into byte array "pixels"
	*/
	private inline function getImagePixels(Data:BitmapData):ByteArray
	{
		pixels = new ByteArray();
		
		var count:Int = 0;
		
		for (i in 0...height)
		{
			for (j in 0...width)
			{
				var pixel:UInt = Data.getPixel(j, i);
				
				pixels[count] = (pixel & 0xFF0000) >> 16;
				count++;
				pixels[count] = (pixel & 0x00FF00) >> 8;
				count++;
				pixels[count] = (pixel & 0x0000FF);
				count++;
			}
		}
		
		return pixels;
	}
	
	/**
	* Writes Graphic Control Extension
	*/
	private inline function writeGraphicCtrlExt():ByteArray
	{
		output.writeByte(0x21); // extension introducer
		output.writeByte(0xf9); // GCE label
		output.writeByte(4); // data block size
		var transp:Int = 0;
		var disp:Int = 0; // dispose = no action
		
		if (transparent != null)
		{
			transp = 1;
			disp = 2; // force clear if using transparent color
		}
		
		if (dispose >= 0)
		{
			disp = dispose & 7; // user override
		}
		
		disp <<= 2;
		
		// packed fields
		output.writeByte(0 | // 1:3 reserved
			disp | // 4:6 disposal
			0 | // 7 user input - 0 = none
			transp); // 8 transparency flag
		
		output.writeShort(Math.round(delay / 10)); // delay x 1/100 sec
		output.writeByte(transIndex); // transparent color index
		output.writeByte(0); // block terminator
		
		return output;
	}
	
	/**
	* Writes Image Descriptor
	*/
	private inline function writeImageDesc():ByteArray
	{
		output.writeByte(0x2c); // image separator
		output.writeShort(0); // image position x,y = 0,0
		output.writeShort(0);
		output.writeShort(width); // image size
		output.writeShort(height);
		
		// packed fields
		if (firstFrame)
		{
			// no LCT - GCT is used for first (or only) frame
			output.writeByte(0);
		}
		else
		{
			// specify normal LCT
			output.writeByte(0x80 | // 1 local color table 1=yes
				0 | // 2 interlace - 0=no
				0 | // 3 sorted - 0=no
				0 | // 4-5 reserved
				palSize); // 6-8 size of color table
		}
		
		return output;
	}
	
	/**
	* Writes Logical Screen Descriptor
	*/
	private inline function writeLSD():ByteArray
	{
		// logical screen size
		output.writeShort(width);
		output.writeShort(height);
		
		// packed fields
		output.writeByte((0x80 | // 1 : global color table flag = 1 (gct used)
			0x70 | // 2-4 : color resolution = 7
			0x00 | // 5 : gct sort flag = 0
			palSize)); // 6-8 : gct size
		
		output.writeByte(0); // background color index
		output.writeByte(0); // pixel aspect ratio - assume 1:1
		
		return output;
	}
	
	/**
	* Writes Netscape application extension to define repeat count.
	*/
	private function writeNetscapeExt():ByteArray
	{
		output.writeByte(0x21); // extension introducer
		output.writeByte(0xff); // app extension label
		output.writeByte(11); // block size
		output.writeUTFBytes("NETSCAPE" + "2.0"); // app id + auth code
		output.writeByte(3); // sub-block size
		output.writeByte(1); // loop sub-block id
		output.writeShort(repeat); // loop count (extra iterations, 0=repeat forever)
		output.writeByte(0); // block terminator
		
		return output;
	}
	
	/**
	* Writes color table
	*/
	private inline function writePalette():ByteArray
	{
		output.writeBytes(colorTab, 0, colorTab.length);
		var n:Int = (3 * 256) - colorTab.length;
		
		for (i in 0...n)
		{
			output.writeByte(0);
		}
		
		return output;
	}
	
	/**
	* Encodes and writes pixel data to stream.
	*/
	private inline function writePixels():ByteArray
	{
		var myencoder:LZWEncoder = new LZWEncoder(width, height, indexedPixels, colorDepth);
		myencoder.encode(output);
		
		return output;
	}
	
	/**
	 * Limits minimum quality value to 1, maximum to 30.
	 */
	private inline function set_quality(Value:UInt):UInt
	{
		if (Value < 1)
		{
			Value = 1;
		}
		
		if (Value > 30)
		{
			Value = 30;
		}
		
		return quality = Value;
	}
	
	/**
	 * Limits repeat value to -1 (no repeat).
	 */
	private inline function set_repeat(Value:Int):Int
	{
		if (Value < - 1)
		{
			Value = -1;
		}
		
		return repeat = Value;
	}
	
	/**
	 * Returns delay in form of frames per second.
	 */
	private inline function get_framerate():Float
	{
		return 1000 / delay;
	}
	
	/**
	 * Allows setting delay in form of frames per second.
	 */
	private inline function set_framerate(Value:Float):Float
	{
		if (Value != 0)
		{
			delay = Math.round(1000 / Value);
		}
		
		return Value;
	}
	
	/**
	 * Prevents setting dispose to less than negative one.
	 */
	private inline function set_dispose(Value:Int):Int
	{
		if (Value < -1)
		{
			Value = -1;
		}
		
		return dispose = Value;
	}
	
	/**
	 * Prevents setting width after first frame.
	 */
	private inline function set_width(Value:UInt):UInt
	{
		if (started || Value < 1)
		{
			return width;
		}
		
		return width = Value;
	}
	
	/**
	 * Prevents setting height after first frame.
	 */
	private inline function set_height(Value:UInt):UInt
	{
		if (started || Value < 1)
		{
			return height;
		}
		
		return height = Value;
	}
	
	#if !flash
	/**
	 * Convenience function to output a GIF file from an array of BitmapData frames. Not supported in Flash.
	 * 
	 * @param	Path    Path to the output file. Will throw exception if cannot write.
	 * @param	Frames  An array of BitmapData, with each BitmapData object representing one frame of the animation.
	 */
	static public function exportFromArray(Path:String, Frames:Array<BitmapData>):Void
	{
		var encoder:GIFEncoder = new GIFEncoder();
		
		for (frame in Frames)
		{
			encoder.addFrame(frame);
		}
		
		encoder.finish();
		
		File.saveBytes(Path, encoder.output);
	}
	#end
}