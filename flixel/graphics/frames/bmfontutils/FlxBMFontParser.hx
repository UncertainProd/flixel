package flixel.graphics.frames.bmfontutils;

import flixel.FlxG;
import flixel.graphics.frames.bmfontutils.BMFont.BMFont_Char;
import flixel.graphics.frames.bmfontutils.BMFont.BMFont_Common;
import flixel.graphics.frames.bmfontutils.BMFont.BMFont_Info;
import flixel.graphics.frames.bmfontutils.BMFont.BMFont_KerningPair;
import flixel.graphics.frames.bmfontutils.BMFont.BMFont_PageInfo;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;
import haxe.xml.Access;

using StringTools;

class FlxBMFontParser
{
	public static function fromText(text:String)
	{
		return new FlxBMFontTextParser(text).parse();
	}
	
	public static function fromXml(xml:Xml)
	{
		return new FlxBMFontXMLParser(xml).parse();
	}
	
	public static function fromBinary(bytes:Bytes)
	{
		return new FlxBMFontBinaryParser(new BytesInput(bytes)).parse();
	}
}

@:access(flixel.graphics.frames.bmfontutils.BMFont)
class FlxBMFontBinaryParser
{
	var bytesInput:BytesInput;
	
	public static inline final BT_INFO:Int = 1;
	public static inline final BT_COMMON:Int = 2;
	public static inline final BT_PAGES:Int = 3;
	public static inline final BT_CHARS:Int = 4;
	public static inline final BT_KERNING_PAIRS:Int = 5;
	
	public function new(input:BytesInput)
	{
		bytesInput = input;
	}
	
	// @see https://www.angelcode.com/products/bmfont/doc/file_format.html#bin
	public function parse()
	{
		final fontInfo = new BMFont();
		final expectedBytes = [66, 77, 70]; // 'B', 'M', 'F'
		for (b in expectedBytes)
		{
			var testByte = bytesInput.readByte();
			if (testByte != b)
				throw 'Invalid binary .fnt file. Found $testByte, expected $b';
		}
		var version = bytesInput.readByte();
		if (version < 3)
		{
			FlxG.log.warn('The BMFont parser is made to work on files with version 3. Using earlier versions can cause issues!');
		}
		
		// parsing blocks
		while (bytesInput.position < bytesInput.length)
		{
			var blockId = bytesInput.readByte();
			switch blockId
			{
				case BT_INFO:
					fontInfo.info = parseInfoBlock();
				case BT_COMMON:
					fontInfo.common = parseCommonBlock();
				case BT_PAGES:
					fontInfo.pages = parsePagesBlock();
				case BT_CHARS:
					fontInfo.chars = parseCharsBlock();
				case BT_KERNING_PAIRS:
					fontInfo.kerningPairs = parseKerningPairs();
			}
		}
		return fontInfo;
	}
	
	function parseInfoBlock()
	{
		var blockSize:Int = bytesInput.readInt32();
		var fontSize = bytesInput.readInt16();
		var bitField = bytesInput.readByte();
		var fontInfo:BMFont_Info = {
			fontSize: fontSize,
			smooth: (bitField & 0x80) != 0,
			unicode: (bitField & (0x80 >> 1)) != 0,
			italic: (bitField & (0x80 >> 2)) != 0,
			bold: (bitField & (0x80 >> 3)) != 0,
			fixedHeight: (bitField & (0x80 >> 4)) != 0,
			charSet: String.fromCharCode(bytesInput.readByte()),
			stretchH: bytesInput.readInt16(),
			aa: bytesInput.readByte(),
			paddingUp: bytesInput.readByte(),
			paddingRight: bytesInput.readByte(),
			paddingDown: bytesInput.readByte(),
			paddingLeft: bytesInput.readByte(),
			spacingHoriz: bytesInput.readByte(),
			spacingVert: bytesInput.readByte(),
			outline: bytesInput.readByte(),
			fontName: bytesInput.readString(blockSize - 14 - 1)
		};
		bytesInput.readByte(); // skip the null terminator of the string
		return fontInfo;
	}
	
	function parseCommonBlock()
	{
		var blockSize = bytesInput.readInt32();
		
		var lineHeight = bytesInput.readInt16();
		var base = bytesInput.readInt16();
		var scaleW = bytesInput.readInt16();
		var scaleH = bytesInput.readInt16();
		var pages = bytesInput.readInt16();
		var bitField = bytesInput.readByte();
		var isPacked = (bitField & 0x2) != 0;
		var commonBlock:BMFont_Common = {
			lineHeight: lineHeight,
			base: base,
			scaleW: scaleW,
			scaleH: scaleH,
			pages: pages,
			isPacked: isPacked,
			alphaChnl: bytesInput.readByte(),
			redChnl: bytesInput.readByte(),
			greenChnl: bytesInput.readByte(),
			blueChnl: bytesInput.readByte(),
		};
		if (blockSize != 15)
			throw 'Invalid block size for common block. Expected 15 got $blockSize';
		return commonBlock;
	}
	
	function parsePagesBlock()
	{
		var blockSize = bytesInput.readInt32();
		var pagesBlock:Array<BMFont_PageInfo> = [];
		
		var bytesRead = 0;
		var i = 0;
		while (bytesRead < blockSize)
		{
			var bytesBuf = new BytesBuffer();
			var curByte = bytesInput.readByte();
			while (curByte != 0)
			{
				bytesBuf.addByte(curByte);
				curByte = bytesInput.readByte();
			}
			var pageName = bytesBuf.getBytes().toString();
			pagesBlock.push({id: i, file: pageName});
			bytesRead += pageName.length + 1;
			i++;
		}
		
		return pagesBlock;
	}
	
	function parseCharsBlock()
	{
		var blockSize = bytesInput.readInt32();
		var bytesRead = 0;
		var chars = [];
		while (bytesRead < blockSize)
		{
			var charInfo:BMFont_Char = {
				id: bytesInput.readInt32(),
				x: bytesInput.readInt16(),
				y: bytesInput.readInt16(),
				width: bytesInput.readInt16(),
				height: bytesInput.readInt16(),
				xoffset: bytesInput.readInt16(),
				yoffset: bytesInput.readInt16(),
				xadvance: bytesInput.readInt16(),
				page: bytesInput.readByte(),
				chnl: bytesInput.readByte(),
			};
			chars.push(charInfo);
			bytesRead += 20;
		}
		return chars;
	}
	
	function parseKerningPairs()
	{
		var blockSize = bytesInput.readInt32();
		var bytesRead = 0;
		var kerningPairs = [];
		while (bytesRead < blockSize)
		{
			var kerningPair:BMFont_KerningPair = {
				first: bytesInput.readInt32(),
				second: bytesInput.readInt32(),
				amount: bytesInput.readInt16(),
			};
			kerningPairs.push(kerningPair);
			bytesRead += 10;
		}
		return kerningPairs;
	}
}

@:access(flixel.graphics.frames.bmfontutils.BMFont)
class FlxBMFontTextParser
{
	var text:String;
	
	public function new(text:String)
	{
		this.text = text;
	}
	
	public function parse()
	{
		var fontInfo = new BMFont();
		var lines = text.replace('\r\n', '\n').split('\n').filter((line) -> line.length > 0);
		for (line in lines)
		{
			var blockType = line.substring(0, line.indexOf(' '));
			var blockAttrs = line.substring(line.indexOf(' ') + 1);
			switch blockType
			{
				case 'info':
					fontInfo.info = parseInfoBlock(blockAttrs);
				case 'common':
					fontInfo.common = parseCommonBlock(blockAttrs);
				case 'page':
					fontInfo.pages.push(parsePageBlock(blockAttrs));
				// case 'chars': // we dont need this but this field exists in the file
				case 'char':
					fontInfo.chars.push(parseCharBlock(blockAttrs));
				// case 'kernings': // we dont need this but this field exists in the file
				case 'kerning':
					fontInfo.kerningPairs.push(parseKerningPair(blockAttrs));
			}
		}
		return fontInfo;
	}
	
	function parseInfoBlock(attrs:String)
	{
		var info:BMFont_Info = {
			fontName: null,
			fontSize: null,
			bold: false,
			italic: false,
			charSet: null,
			unicode: false,
			stretchH: null,
			smooth: false,
			aa: null,
			paddingLeft: null,
			paddingDown: null,
			paddingRight: null,
			paddingUp: null,
			spacingVert: null,
			spacingHoriz: null,
			outline: null,
			fixedHeight: false
		};
		
		// the parsing here is a bit more involved since strings can have spaces within them
		// so we can't just split by space like we usually do (same for parsePageBlock and parseCharBlock)
		var i = 0;
		var word = '';
		var readNumberLike = () ->
		{
			i += 2; // skip '='
			word = '';
			while (attrs.charAt(i) != ' ')
			{
				word += attrs.charAt(i);
				i++;
			}
			i++; // skip space
			return word;
		};
		var readString = () ->
		{
			i += 3; // skip '=' and start quote
			word = '';
			while (attrs.charAt(i) != '\"')
			{
				word += attrs.charAt(i);
				i++;
			}
			i++; // skip end quote
			return word;
		};
		while (true)
		{
			if (i >= attrs.length)
				break;
			var curChar = attrs.charAt(i);
			if (curChar == '')
				break;
			if (curChar == ' ')
			{
				i++;
				continue;
			}
			word += curChar;
			switch word
			{
				case 'face':
					info.fontName = readString();
					word = '';
				case 'size':
					info.fontSize = Std.parseInt(readNumberLike());
					word = '';
				case 'bold':
					info.bold = readNumberLike() != '0';
					word = '';
				case 'italic':
					info.italic = readNumberLike() != '0';
					word = '';
				case 'charset':
					info.charSet = readString();
					word = '';
				case 'unicode':
					info.unicode = readNumberLike() != '0';
					word = '';
				case 'stretchH':
					info.stretchH = Std.parseInt(readNumberLike());
					word = '';
				case 'smooth':
					info.smooth = readNumberLike() != '0';
					word = '';
				case 'aa':
					info.aa = Std.parseInt(readNumberLike());
					word = '';
				case 'padding':
					var paddings = readNumberLike().split(',').map(Std.parseInt);
					info.paddingUp = paddings[0];
					info.paddingRight = paddings[1];
					info.paddingDown = paddings[2];
					info.paddingLeft = paddings[3];
					word = '';
				case 'spacing':
					var spacings = readNumberLike().split(',').map(Std.parseInt);
					info.spacingHoriz = spacings[0];
					info.spacingVert = spacings[1];
					word = '';
				case 'outline':
					info.outline = Std.parseInt(readNumberLike());
					word = '';
				case 'fixedHeight':
					info.fixedHeight = readNumberLike() != '0';
					word = '';
			}
			i++;
		}
		return info;
	}
	
	function parseCommonBlock(attrs:String)
	{
		var common:BMFont_Common = {
			lineHeight: null,
			base: null,
			scaleW: null,
			scaleH: null,
			pages: 0,
			isPacked: false,
			alphaChnl: null,
			redChnl: null,
			greenChnl: null,
			blueChnl: null,
		};
		var keyValuePairs = attrs.split(' ').map((s) -> s.split('='));
		for (kvPair in keyValuePairs)
		{
			var key = kvPair[0];
			var value = kvPair[1];
			switch key
			{
				case 'lineHeight':
					common.lineHeight = Std.parseInt(value);
				case 'base':
					common.base = Std.parseInt(value);
				case 'scaleW':
					common.scaleW = Std.parseInt(value);
				case 'scaleH':
					common.scaleH = Std.parseInt(value);
				case 'pages':
					common.pages = Std.parseInt(value);
				case 'packed':
					common.isPacked = value != '0';
				case 'alphaChnl':
					common.alphaChnl = Std.parseInt(value);
				case 'redChnl':
					common.redChnl = Std.parseInt(value);
				case 'greenChnl':
					common.greenChnl = Std.parseInt(value);
				case 'blueChnl':
					common.blueChnl = Std.parseInt(value);
			}
		}
		
		return common;
	}
	
	function parsePageBlock(attrs:String)
	{
		var page:BMFont_PageInfo = {
			id: null,
			file: null
		};
		var i = 0;
		var word = '';
		var readNumberLike = () ->
		{
			i += 2; // skip '='
			word = '';
			while (attrs.charAt(i) != ' ')
			{
				word += attrs.charAt(i);
				i++;
			}
			i++; // skip space
			return word;
		};
		var readString = () ->
		{
			i += 3; // skip '=' and start quote
			word = '';
			while (attrs.charAt(i) != '\"')
			{
				word += attrs.charAt(i);
				i++;
			}
			i++; // skip end quote
			return word;
		};
		while (true)
		{
			if (i >= attrs.length)
				break;
			var curChar = attrs.charAt(i);
			if (curChar == '')
			{
				break;
			}
			else if (curChar == ' ')
			{
				i++;
				continue;
			}
			
			word += curChar;
			switch word
			{
				case 'id':
					page.id = Std.parseInt(readNumberLike());
					word = '';
				case 'file':
					page.file = readString();
					word = '';
			}
			i++;
		}
		return page;
	}
	
	function parseCharBlock(attrs:String)
	{
		var char:BMFont_Char = {
			id: null,
			x: null,
			y: null,
			width: null,
			height: null,
			xoffset: 0,
			yoffset: 0,
			xadvance: 0,
			page: null,
			chnl: null,
		};
		var i = 0;
		var word = '';
		var readNumberLike = () ->
		{
			i += 2; // skip '='
			word = '';
			while (attrs.charAt(i) != ' ')
			{
				word += attrs.charAt(i);
				i++;
			}
			i++; // skip space
			return word;
		};
		var readString = () ->
		{
			i += 3; // skip '=' and start quote
			// hack needed here specifically because bmfont does not escape double-quotes :(
			if (attrs.charAt(i) == '"' && attrs.charAt(i + 1) == '"')
			{
				return '"';
			}
			word = '';
			while (attrs.charAt(i) != '\"' && i < attrs.length)
			{
				word += attrs.charAt(i);
				i++;
			}
			i++; // skip end quote
			return word;
		};
		
		while (true)
		{
			if (i >= attrs.length)
				break;
			var curChar = attrs.charAt(i);
			if (curChar == '')
				break;
			if (curChar == ' ')
			{
				i++;
				continue;
			}
			word += curChar;
			var nextChar = attrs.charAt(i + 1);
			switch word
			{
				case 'letter':
					char.id = Util.getCorrectLetter(readString()).charCodeAt(0);
					word = '';
				case 'id':
					char.id = Std.parseInt(readNumberLike());
					word = '';
				case 'x':
					if (nextChar == '=')
					{
						char.x = Std.parseInt(readNumberLike());
						word = '';
					}
				case 'y':
					if (nextChar == '=')
					{
						char.y = Std.parseInt(readNumberLike());
						word = '';
					}
				case 'width':
					char.width = Std.parseInt(readNumberLike());
					word = '';
				case 'height':
					char.height = Std.parseInt(readNumberLike());
					word = '';
				case 'xoffset':
					var xoffset = Std.parseInt(readNumberLike());
					char.xoffset = (xoffset == null) ? 0 : xoffset;
					word = '';
				case 'yoffset':
					var yoffset = Std.parseInt(readNumberLike());
					char.yoffset = (yoffset == null) ? 0 : yoffset;
					word = '';
				case 'xadvance':
					var xadvance = Std.parseInt(readNumberLike());
					char.xadvance = (xadvance == null) ? 0 : xadvance;
					word = '';
				case 'page':
					char.page = Std.parseInt(readNumberLike());
					word = '';
				case 'chnl':
					char.chnl = Std.parseInt(readNumberLike());
					word = '';
			}
			i++;
		}
		return char;
	}
	
	function parseKerningPair(attrs:String)
	{
		var kerningPair:BMFont_KerningPair = {
			first: null,
			second: null,
			amount: null
		};
		var keyValuePairs = attrs.split(' ').map((s) -> s.split('='));
		for (kvPair in keyValuePairs)
		{
			var key = kvPair[0];
			var value = kvPair[1];
			
			switch key
			{
				case 'first':
					kerningPair.first = Std.parseInt(value);
				case 'second':
					kerningPair.second = Std.parseInt(value);
				case 'amount':
					kerningPair.amount = Std.parseInt(value);
			}
		}
		return kerningPair;
	}
}

@:access(flixel.graphics.frames.bmfontutils.BMFont)
class FlxBMFontXMLParser
{
	var fast:Access;
	
	public function new(xml:Xml)
	{
		fast = new Access(xml);
	}
	
	public function parse()
	{
		var fontInfo = new BMFont();
		fontInfo.info = parseInfoBlock();
		fontInfo.common = parseCommonBlock();
		fontInfo.pages = parsePagesBlock();
		fontInfo.chars = parseCharsBlock();
		
		if (fast.hasNode.kernings)
		{
			fontInfo.kerningPairs = parseKerningPairs();
		}
		
		return fontInfo;
	}
	
	function parseInfoBlock()
	{
		var infoNode = fast.node.info;
		var padding:String = infoNode.att.padding;
		var paddingArr = padding.split(',').map(Std.parseInt);
		
		var spacing:String = infoNode.att.spacing;
		var spacingArr = spacing.split(',').map(Std.parseInt);
		
		var outline = infoNode.has.outline ? Std.parseInt(infoNode.att.outline) : 0;
		var info:BMFont_Info = {
			fontSize: Std.parseInt(infoNode.att.size),
			smooth: infoNode.att.smooth != '0',
			unicode: infoNode.att.unicode != '0',
			italic: infoNode.att.italic != '0',
			bold: infoNode.att.bold != '0',
			fixedHeight: (infoNode.has.fixedHeight) ? infoNode.att.fixedHeight != '0' : false,
			charSet: infoNode.att.charset,
			stretchH: Std.parseInt(infoNode.att.stretchH),
			aa: Std.parseInt(infoNode.att.aa),
			paddingUp: paddingArr[0],
			paddingRight: paddingArr[1],
			paddingDown: paddingArr[2],
			paddingLeft: paddingArr[3],
			spacingHoriz: spacingArr[0],
			spacingVert: spacingArr[1],
			outline: outline,
			fontName: infoNode.att.face,
		}
		
		return info;
	}
	
	function parseCommonBlock()
	{
		var commonNode = fast.node.common;
		var alphaChnl = (commonNode.has.alphaChnl) ? Std.parseInt(commonNode.att.alphaChnl) : 0;
		var redChnl = (commonNode.has.redChnl) ? Std.parseInt(commonNode.att.redChnl) : 0;
		var greenChnl = (commonNode.has.greenChnl) ? Std.parseInt(commonNode.att.greenChnl) : 0;
		var blueChnl = (commonNode.has.blueChnl) ? Std.parseInt(commonNode.att.blueChnl) : 0;
		var common:BMFont_Common = {
			lineHeight: Std.parseInt(commonNode.att.lineHeight),
			base: Std.parseInt(commonNode.att.base),
			scaleW: Std.parseInt(commonNode.att.scaleW),
			scaleH: Std.parseInt(commonNode.att.scaleH),
			pages: Std.parseInt(commonNode.att.pages),
			isPacked: commonNode.att.packed != '0',
			alphaChnl: alphaChnl,
			redChnl: redChnl,
			greenChnl: greenChnl,
			blueChnl: blueChnl,
		};
		
		return common;
	}
	
	function parsePagesBlock()
	{
		var pages:Array<BMFont_PageInfo> = [];
		var pagesNode = fast.node.pages;
		for (page in pagesNode.nodes.page)
		{
			pages.push({
				id: Std.parseInt(page.att.id),
				file: page.att.file
			});
		}
		return pages;
	}
	
	function parseCharsBlock()
	{
		var charsNode = fast.node.chars;
		var chars:Array<BMFont_Char> = [];
		for (char in charsNode.nodes.char)
		{
			var id = (char.has.letter) ? Util.getCorrectLetter(char.att.letter).charCodeAt(0) : Std.parseInt(char.att.id);
			var xoffset = (char.has.xoffset) ? Std.parseInt(char.att.xoffset) : 0;
			var yoffset = (char.has.yoffset) ? Std.parseInt(char.att.yoffset) : 0;
			var xadvance = (char.has.xadvance) ? Std.parseInt(char.att.xadvance) : 0;
			chars.push({
				id: id,
				x: Std.parseInt(char.att.x),
				y: Std.parseInt(char.att.y),
				width: Std.parseInt(char.att.width),
				height: Std.parseInt(char.att.height),
				xoffset: xoffset,
				yoffset: yoffset,
				xadvance: xadvance,
				page: Std.parseInt(char.att.page),
				chnl: Std.parseInt(char.att.chnl),
			});
		}
		
		return chars;
	}
	
	function parseKerningPairs()
	{
		var kerningPairsNode = fast.node.kernings;
		var kerningPairs:Array<BMFont_KerningPair> = [];
		for (kerningPair in kerningPairsNode.nodes.kerning)
		{
			kerningPairs.push({
				first: Std.parseInt(kerningPair.att.first),
				second: Std.parseInt(kerningPair.att.second),
				amount: Std.parseInt(kerningPair.att.amount)
			});
		}
		
		return kerningPairs;
	}
}

@:noCompletion
private final class Util
{
	public static function getCorrectLetter(letter:String)
	{
		// handle some special cases of letters in the xml files
		var charStr = switch (letter)
		{
			case "space": ' ';
			case "&quot;": '"';
			case "&amp;": '&';
			case "&gt;": '>';
			case "&lt;": '<';
			default: letter;
		}
		return charStr;
	}
}