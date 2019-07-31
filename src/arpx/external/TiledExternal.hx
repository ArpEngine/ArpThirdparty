package arpx.external;

#if flash

import arp.data.DataGroup;
import flash.utils.CompressionAlgorithm;
import arpx.chip.Chip;
import arpx.tileInfo.TileInfo;
import arpx.mortal.TileMapMortal;
import arpx.hitFrame.CuboidHitFrame;
import arpx.hitFrame.HitFrame;
import arp.seed.ArpSeed;
import haxe.crypto.Base64;
import arpx.mortal.Mortal;
import arpx.anchor.Anchor;
import arpx.tileMap.ArrayTileMap;
import arpx.field.Field;
import arpx.file.File;
import flash.utils.ByteArray;
import flash.utils.Endian;

@:arpType("external", "tiled")
class TiledExternal extends External {

	@:arpBarrier(true, true) @:arpField private var file:File;
	@:arpBarrier @:arpField private var chip:Chip;
	@:arpBarrier @:arpField private var tileInfo:TileInfo;
	@:arpField private var outerTileIndex:Int;

	private var data:DataGroup;

	public function new() {
		super();
	}

	@:arpHeatUp
	private function heatUp():Bool {
		this.load();
		return true;
	}

	@:arpHeatDown
	private function heatDown():Bool {
		this.unload();
		return true;
	}

	override public function load(force:Bool = false):Void {
		if (this.data != null && !force) {
			return;
		}
		if (this.file.exists) {
			var xml:Xml = Xml.parse(this.file.bytes().toString());
			if (xml != null) {
				this.data = this.arpDomain.allocObject(DataGroup);
				this.data.arpSlot.addReference();
				this.loadTiled(xml);
			}
		}
	}

	override public function unload():Void {
		if (this.data != null) {
			this.data.arpSlot.delReference();
			this.data = null;
		}
	}

	private function loadTiled(xml:Xml):Void {
		switch (xml.nodeName) {
			case "map":
				this.loadTiledMap(xml);
		}
	}

	private function loadTiledMap(xml:Xml):Field {
		//tiled map => arp field
		var field:Field = this.data.allocObject(Field);

		for (layer in xml.elementsNamed("layer")) {
			var layerData:Array<Array<Int>> = this.readTiledLayer(layer);
			var tileMap:ArrayTileMap = this.data.addOrphanObject(ArrayTileMap.fromArray(layerData));
			tileMap.width = Std.parseInt(xml.get("width"));
			tileMap.height = Std.parseInt(xml.get("height"));
			tileMap.outerTileIndex = (this.outerTileIndex != 0) ? this.outerTileIndex : layerData[0][0];
			// tileMap.tileInfo = this.tileInfo;

			var tmMortal:TileMapMortal = this.data.allocObject(TileMapMortal);
			tmMortal.chip = this.chip;
			tmMortal.tileMap = tileMap;
			field.mortals.addPair('_layer_${layer.get("name")}', tmMortal);
		}

		var uniqueId:Int = 0;
		var gridSize:Int = Std.parseInt(xml.get("tilewidth"));
		for (objectgroup in xml.elementsNamed("objectgroup")) {
			for (object in objectgroup.elementsNamed("object")) {
				var name:String = object.get("name");
				if (name == null) name = Std.string(uniqueId++);
				switch (this.loadTiledObject(object, gridSize)) {
					case TiledObject.TiledMortal(mortal):
						field.mortals.addPair(name, mortal);
					case TiledObject.TiledAnchor(anchor):
						field.anchors.addPair(name, anchor);
				}
			}
		}

		return field;
	}

	private function loadTiledObject(xml:Xml, gridSize:Int):TiledObject {
		if (xml.get("gid") != null) {
			//tiled object with gid => arp mortal
			var xml:Xml = Xml.parse('<mortal class="${xml.get("type")}">');
			for (property in xml.elementsNamed("properties").next().elementsNamed("property")) {
				xml.set(property.get("name"), property.get("value"));
			}
			var mortal:Mortal = this.arpDomain.loadSeed(ArpSeed.fromXml(xml), Mortal).value;
			if (mortal == null) return null;

			mortal.position.x = Std.parseFloat(xml.get("x"));
			mortal.position.y = Std.parseFloat(xml.get("y"));
			return TiledObject.TiledMortal(mortal);
		} else {
			//tiled object without gid => arp anchor
			var anchor:Anchor = this.data.allocObject(Anchor);
			anchor.position.x = Std.parseInt(xml.get("x"));
			anchor.position.y = Std.parseInt(xml.get("y"));

			var hitFrame:CuboidHitFrame = this.data.allocObject(CuboidHitFrame);
			var width:Float = Std.parseFloat(xml.get("width")) / 2;
			var height:Float = Std.parseFloat(xml.get("width")) / 2;
			hitFrame.hitCuboid.dX = width;
			hitFrame.hitCuboid.dY = height;
			hitFrame.hitCuboid.sizeX = width;
			hitFrame.hitCuboid.sizeY = height;
			anchor.hitFrame = hitFrame;
			return TiledObject.TiledAnchor(anchor);
		}
	}

	private function readTiledLayer(xml:Xml):Array<Array<Int>> {
		var data:Xml = xml.elementsNamed("data").next();
		var width:Int = Std.parseInt(xml.get("width"));
		var height:Int = Std.parseInt(xml.get("height"));
		var x:Int;
		var y:Int;
		var work:Array<Int> = [];
		var result:Array<Array<Int>>;
		var row:Array<Int>;
		var encoding:String = data.get("encoding");
		switch (encoding) {
			case null:
				//uncompressed
				result = [];
				for (tile in data.elementsNamed("tile")) {
					work.push(Std.parseInt(tile.get("gid")) - 1);
				}
				x = 0;
				for (y in 0...height) {
					result.push(work.slice(x, width));
					x += width;
				}
			case "csv":
				//compressed
				result = [];
				for (csvRow in data.firstChild().nodeValue.split("\n")) {
					var csvStr:String = StringTools.trim(csvRow);
					row = [];
					for (csvTile in csvRow.split(",")) {
						row.push(Std.parseInt(csvTile) - 1);
					}
					result.push(row);
				}
				x = 0;
				for (y in 0...height) {
					result.push(work.slice(x, width));
					x += width;
				}
			case "base64":
				//compressed
				result = [];
				if (data.get("compression") != "zlib") {
					//not supported
				}
				var bytes:ByteArray = Base64.decode(data.firstChild().nodeValue).getData();
				bytes.uncompress(CompressionAlgorithm.ZLIB);
				bytes.endian = Endian.LITTLE_ENDIAN;
				for (y in 0...height) {
					row = [];
					for (x in 0...width) {
						row.push(bytes.readUnsignedInt() - 1);
					}
					result.push(row);
				}
			default:
				result = [];
		}
		return result;
	}
}

private enum TiledObject {
	TiledMortal(mortal:Mortal);
	TiledAnchor(anchor:Anchor);
}

#end
