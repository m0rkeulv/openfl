package openfl._internal.formats.swf;
import haxe.Unserializer;
class FasterUnserializer extends Unserializer {

    //enum:openfl._internal.formats.swf.ShapeCommand
    private var  knownClass:Array<String> = [
        "openfl._internal.symbols.timeline.FrameObject",
        "openfl._internal.symbols.timeline.Frame",
        "openfl._internal.symbols.SpriteSymbol",
        "openfl._internal.symbols.DynamicTextSymbol",
        "openfl._internal.symbols.ButtonSymbol",
        "openfl._internal.symbols.StaticTextSymbol",
        "openfl._internal.symbols.ShapeSymbol",
        "openfl._internal.symbols.BitmapSymbol",
        //
        "openfl.geom.Matrix",
        "openfl.geom.ColorTransform"
    ];

    private var  knownEnums:Array<String> = [
        "openfl._internal.symbols.timeline.FrameObjectType",
        "openfl._internal.formats.swf.ShapeCommand",
        "openfl._internal.formats.swf.FilterType"
    ];

    public function new(buf:String) {
        super(buf);
    }

     function unserializeKnownClass(name:String):Any {
        switch(name) {
            case "openfl._internal.symbols.timeline.FrameObject": {
                return new openfl._internal.symbols.timeline.FrameObject();
            }
            case "openfl._internal.symbols.timeline.Frame": {
                return new openfl._internal.symbols.timeline.Frame();
            }
            case "openfl._internal.symbols.SpriteSymbol": {
                return new openfl._internal.symbols.SpriteSymbol();
            }
            case "openfl._internal.symbols.DynamicTextSymbol": {
                return new openfl._internal.symbols.DynamicTextSymbol();
            }
            case "openfl._internal.symbols.ButtonSymbol": {
                return new openfl._internal.symbols.ButtonSymbol();
            }
            case "openfl._internal.symbols.StaticTextSymbol": {
                return new openfl._internal.symbols.StaticTextSymbol();
            }
            case "openfl._internal.symbols.ShapeSymbol": {
                return new openfl._internal.symbols.ShapeSymbol();
            }
            case "openfl._internal.symbols.BitmapSymbol": {
                return new openfl._internal.symbols.BitmapSymbol();
            }
            case "openfl.geom.Matrix": {
                return new openfl.geom.Matrix();
            }
            case "openfl.geom.ColorTransform": {
                return new openfl.geom.ColorTransform();
            }
            default: throw "Unknown class type";
        }
    }
     function unserializeKnownEnum(name:String, tag:String) {
         if (get(pos++) != ":".code)
             throw "Invalid enum format";
        var nargs = readDigits();
        if (nargs == 0)
            return createEnum(name, tag);
        var args = new Array();
        while (nargs-- > 0)
            args.push(unserialize());
        return createEnum(name, tag, args);
    }
    function createEnum(name:String, tag:String, ?params:Array<Dynamic>):Any {
        switch(name) {
        case  "openfl._internal.symbols.timeline.FrameObjectType" :
            switch(tag) {
                case "CREATE" : return openfl._internal.symbols.timeline.FrameObjectType.CREATE;
                case "UPDATE" : return openfl._internal.symbols.timeline.FrameObjectType.UPDATE;
                case "DESTROY" : return openfl._internal.symbols.timeline.FrameObjectType.DESTROY;
                default: throw "Unknown FrameObjectType type";
            }
            case "openfl._internal.formats.swf.ShapeCommand":
            switch(tag) {
                case "BeginBitmapFill" : return ShapeCommand.BeginBitmapFill(params[0], params[1], params[2],params[3]);
                case "BeginFill" : return ShapeCommand.BeginFill(params[0], params[1]);
                case "BeginGradientFill" : return ShapeCommand.BeginGradientFill(params[0], params[1], params[2], params[3], params[4], params[5] , params[6] , params[7]);
                case "CurveTo" : return ShapeCommand.CurveTo(params[0], params[1], params[2],params[3]);
                case "EndFill" : return ShapeCommand.EndFill;
                case "LineStyle" : return ShapeCommand.LineStyle(params[0], params[1], params[2], params[3], params[4], params[5] , params[6] , params[7]);
                case "LineTo" : return ShapeCommand.LineTo(params[0], params[1]);
                case "MoveTo" : return ShapeCommand.MoveTo(params[0], params[1]);
                default: throw "Unknown ShapeCommand type";
            }
            case "openfl._internal.formats.swf.FilterType" :
            switch(tag) {
                case "BlurFilter" : return FilterType.BlurFilter(params[0], params[1], params[2]);
                case "ColorMatrixFilter" : return FilterType.ColorMatrixFilter(params[0]);
                case "DropShadowFilter" : return FilterType.DropShadowFilter(params[0], params[1], params[2], params[3], params[4], params[5] , params[6] , params[7], params[8], params[9], params[10]);
                case "GlowFilter" : return FilterType.GlowFilter(params[0], params[1], params[2], params[3], params[4], params[5] , params[6] , params[7]);
                default: throw "Unknown FilterType type";
            }
        }

        throw "Unknown Enum type";
    }

    override public function unserialize():Dynamic {
        switch (get(pos++)) {
            case "n".code:
                return null;
            case "t".code:
                return true;
            case "f".code:
                return false;
            case "z".code:
                return 0;
            case "i".code:
                return readDigits();
            case "d".code:
                return readFloat();
            case "y".code:
                var len = readDigits();
                if (get(pos++) != ":".code || length - pos < len)
                    throw "Invalid string length";
                var s = buf.substr(pos, len);
                pos += len;
                s = StringTools.urlDecode(s);
                scache.push(s);
                return s;
            case "k".code:
                return Math.NaN;
            case "m".code:
                return Math.NEGATIVE_INFINITY;
            case "p".code:
                return Math.POSITIVE_INFINITY;
            case "a".code:
                var buf = buf;
                var a = new Array<Dynamic>();
                #if cpp
				var cachePos = cache.length;
				#end
                cache.push(a);
                while (true) {
                    var c = get(pos);
                    if (c == "h".code) {
                        pos++;
                        break;
                    }
                    if (c == "u".code) {
                        pos++;
                        var n = readDigits();
                        a[a.length + n - 1] = null;
                    } else
                        a.push(unserialize());
                }
                #if cpp
				return cache[cachePos] = cpp.NativeArray.resolveVirtualArray(a);
				#else
                return a;
            #end
            case "o".code:
                var o = {};
                cache.push(o);
                unserializeObject(o);
                return o;
            case "r".code:
                var n = readDigits();
                if (n < 0 || n >= cache.length)
                    throw "Invalid reference";
                return cache[n];
            case "R".code:
                var n = readDigits();
                if (n < 0 || n >= scache.length)
                    throw "Invalid string reference";
                return scache[n];
            case "x".code:
                throw unserialize();
            case "c".code:
                var name = unserialize();
                if(knownClass.contains(name)) {
                    var o = unserializeKnownClass(name);
                    cache.push(o);
                    unserializeObject(o);
                    return o;
                }else {
                    var cl = resolver.resolveClass(name);
                    if (cl == null)
                        throw "Class not found " + name;
                    var o = Type.createEmptyInstance(cl);
                    cache.push(o);
                    unserializeObject(o);
                    return o;
                }
            case "w".code:
                var name = unserialize();
                if(knownEnums.contains(name)) {
                    var e = unserializeKnownEnum(name, unserialize());
                    cache.push(e);
                    return e;
                }else {
                    var edecl = resolver.resolveEnum(name);
                    if (edecl == null)
                        throw "Enum not found " + name;
                    var e = unserializeEnum(edecl, unserialize());
                    cache.push(e);
                    return e;
                }
            case "j".code:
                var name = unserialize();
                var edecl = resolver.resolveEnum(name);
                if (edecl == null)
                    throw "Enum not found " + name;
                pos++; /* skip ':' */
                var index = readDigits();
                var tag = Type.getEnumConstructs(edecl)[index];
                if (tag == null)
                    throw "Unknown enum index " + name + "@" + index;
                if(knownEnums.contains(name)) {
                    var e = unserializeKnownEnum(name, tag);
                    cache.push(e);
                    return e;
                }else  {
                    var e = unserializeEnum(edecl, tag);
                    cache.push(e);
                    return e;
                }
            case "l".code:
                var l = new List();
                cache.push(l);
                var buf = buf;
                while (get(pos) != "h".code)
                    l.add(unserialize());
                pos++;
                return l;
            case "b".code:
                var h = new haxe.ds.StringMap();
                cache.push(h);
                var buf = buf;
                while (get(pos) != "h".code) {
                    var s = unserialize();
                    h.set(s, unserialize());
                }
                pos++;
                return h;
            case "q".code:
                var h = new haxe.ds.IntMap();
                cache.push(h);
                var buf = buf;
                var c = get(pos++);
                while (c == ":".code) {
                    var i = readDigits();
                    h.set(i, unserialize());
                    c = get(pos++);
                }
                if (c != "h".code)
                    throw "Invalid IntMap format";
                return h;
            case "M".code:
                var h = new haxe.ds.ObjectMap();
                cache.push(h);
                var buf = buf;
                while (get(pos) != "h".code) {
                    var s = unserialize();
                    h.set(s, unserialize());
                }
                pos++;
                return h;
            case "v".code:
                var d;
                if (get(pos) >= '0'.code && get(pos) <= '9'.code && get(pos + 1) >= '0'.code && get(pos + 1) <= '9'.code && get(pos + 2) >= '0'.code
                && get(pos + 2) <= '9'.code && get(pos + 3) >= '0'.code && get(pos + 3) <= '9'.code && get(pos + 4) == '-'.code) {
                    // Included for backwards compatibility
                    d = Date.fromString(buf.substr(pos, 19));
                    pos += 19;
                } else
                    d = Date.fromTime(readFloat());
                cache.push(d);
                return d;
            case "s".code:
                var len = readDigits();
                var buf = buf;
                if (get(pos++) != ":".code || length - pos < len)
                    throw "Invalid bytes length";
                #if neko
				var bytes = haxe.io.Bytes.ofData(Unserializer.base_decode(untyped buf.substr(pos, len).__s, untyped BASE64.__s));
				#elseif php
				var phpEncoded = php.Global.strtr(buf.substr(pos, len), '%:', '+/');
				var bytes = haxe.io.Bytes.ofData(php.Global.base64_decode(phpEncoded));
				#else
                var codes = Unserializer.CODES;
                if (codes == null) {
                    codes = Unserializer.initCodes();
                    Unserializer.CODES = codes;
                }
                var i = pos;
                var rest = len & 3;
                var size = (len >> 2) * 3 + ((rest >= 2) ? rest - 1 : 0);
                var max = i + (len - rest);
                var bytes = haxe.io.Bytes.alloc(size);
                var bpos = 0;
                while (i < max) {
                    var c1 = codes[StringTools.fastCodeAt(buf, i++)];
                    var c2 = codes[StringTools.fastCodeAt(buf, i++)];
                    bytes.set(bpos++, (c1 << 2) | (c2 >> 4));
                    var c3 = codes[StringTools.fastCodeAt(buf, i++)];
                    bytes.set(bpos++, (c2 << 4) | (c3 >> 2));
                    var c4 = codes[StringTools.fastCodeAt(buf, i++)];
                    bytes.set(bpos++, (c3 << 6) | c4);
                }
                if (rest >= 2) {
                    var c1 = codes[StringTools.fastCodeAt(buf, i++)];
                    var c2 = codes[StringTools.fastCodeAt(buf, i++)];
                    bytes.set(bpos++, (c1 << 2) | (c2 >> 4));
                    if (rest == 3) {
                        var c3 = codes[StringTools.fastCodeAt(buf, i++)];
                        bytes.set(bpos++, (c2 << 4) | (c3 >> 2));
                    }
                }
                #end
                pos += len;
                cache.push(bytes);
                return bytes;
            case "C".code:
                var name = unserialize();
                var cl = resolver.resolveClass(name);
                if (cl == null)
                    throw "Class not found " + name;
                var o:Dynamic;
                if(knownClass.contains(name)) {
                     o = unserializeKnownClass(name);
                }else {
                    o = Type.createEmptyInstance(cl);
                }
                cache.push(o);
                o.hxUnserialize(this);
                if (get(pos++) != "g".code)
                    throw "Invalid custom data";
                return o;
            case "A".code:
                var name = unserialize();
                var cl = resolver.resolveClass(name);
                if (cl == null)
                    throw "Class not found " + name;
                return cl;
            case "B".code:
                var name = unserialize();
                var e = resolver.resolveEnum(name);
                if (e == null)
                    throw "Enum not found " + name;
                return e;
            default:
        }
        pos--;
        throw("Invalid char " + buf.charAt(pos) + " at position " + pos);
    }
}
