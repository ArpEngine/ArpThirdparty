package arpx.external;

import arp.data.DataGroup;
import arp.ds.IMap;
import arp.io.BytesInputWrapper;
import arp.io.IInput;
import arp.seed.ArpSeed;
import arpx.anchor.Anchor;
import arpx.chip.Chip;
import arpx.field.Field;
import arpx.file.File;
import arpx.hitFrame.CuboidHitFrame;
import arpx.mortal.Mortal;
import arpx.mortal.TileMapMortal;
import arpx.tileInfo.TileInfo;
import arpx.tileMap.ArrayTileMap;
import format.tools.Inflate;
import haxe.crypto.Base64;
import haxe.io.Bytes;

@:arpType("external", "tiled")
class TiledExternal extends External {

	@:arpBarrier(true, true) @:arpField private var file:File;
	@:arpBarrier @:arpField private var chip:Chip;
	@:arpBarrier @:arpField private var tileInfo:TileInfo;
	@:arpField("hitTypes", "hitType") private var hitTypes:IMap<String, String>;
	@:arpField private var defaultHitType:String;
	@:arpField private var outerTileIndex:Int;

	public function new() super();

	override private function doLoad(data:DataGroup):Bool {
		if (!this.file.exists) return false;
		var xml:Xml = Xml.parse(this.file.bytes().toString()).firstElement();
		if (xml == null) return false;
		this.loadTiled(xml);
		return true;
	}

	private function loadTiled(xml:Xml):Void {
		switch (xml.nodeName) {
			case "map":
				this.loadTiledMap(xml);
		}
	}

	private function loadTiledMap(xml:Xml):Field {
		var uniqueId:Int = 0;
		//tiled map => arp field
		var field:Field = this.data.allocObject(Field, null, this.arpSlot.primaryDir);

		for (layer in xml.elementsNamed("layer")) {
			var name:String = layer.get("name");
			if (name == null) name = Std.string(uniqueId++);
			field.mortals.addPair('_layer_$name', loadTiledLayer(layer));
		}

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

	private function loadTiledLayer(layer:Xml):TileMapMortal {
		var layerData:Array<Array<Int>> = this.readTiledLayer(layer);
		var name:String = layer.get("name");
		var tileMap:ArrayTileMap = this.data.addOrphanObject(ArrayTileMap.fromArray(layerData));
		tileMap.width = Std.parseInt(layer.get("width"));
		tileMap.height = Std.parseInt(layer.get("height"));
		tileMap.outerTileIndex = (this.outerTileIndex != 0) ? this.outerTileIndex : layerData[0][0];
		tileMap.tileInfo = this.tileInfo;

		var tmMortal:TileMapMortal = this.data.allocObject(TileMapMortal);
		tmMortal.chip = this.chip;
		tmMortal.tileMap = tileMap;

		var hitType:String = if (this.hitTypes.hasKey(name)) this.hitTypes.get(name) else this.defaultHitType;
		if (hitType != null) {
			var tmHitFrame:CuboidHitFrame = this.data.allocObject(CuboidHitFrame);
			tmHitFrame.hitType = hitType;
			tmHitFrame.hitCuboid.sizeX = Math.POSITIVE_INFINITY;
			tmHitFrame.hitCuboid.sizeY = Math.POSITIVE_INFINITY;
			tmHitFrame.hitCuboid.sizeZ = Math.POSITIVE_INFINITY;
			tmMortal.hitFrames.add(tmHitFrame);
		}

		return tmMortal;
	}

	private function loadTiledObject(xml:Xml, gridSize:Int):TiledObject {
		if (xml.get("gid") != null) {
			//tiled object with gid => arp mortal
			var mortal:Mortal = this.arpDomain.loadSeed(prepareSeedFromTiledObject(xml), Mortal).value;
			if (mortal == null) return null;

			mortal.position.x = Std.parseFloat(xml.get("x"));
			mortal.position.y = Std.parseFloat(xml.get("y"));

			return TiledObject.TiledMortal(mortal);
		} else {
			//tiled object without gid => arp anchor
			var anchor:Anchor = this.arpDomain.loadSeed(prepareSeedFromTiledObject(xml), Anchor).value;
			if (anchor == null) return null;

			anchor.position.x = Std.parseInt(xml.get("x"));
			anchor.position.y = Std.parseInt(xml.get("y"));

			var hitFrame:CuboidHitFrame = this.data.allocObject(CuboidHitFrame);
			var width:Float = Std.parseFloat(xml.get("width")) / 2;
			var height:Float = Std.parseFloat(xml.get("height")) / 2;
			hitFrame.hitCuboid.dX = width;
			hitFrame.hitCuboid.dY = height;
			hitFrame.hitCuboid.sizeX = width;
			hitFrame.hitCuboid.sizeY = height;
			anchor.hitFrame = hitFrame;

			return TiledObject.TiledAnchor(anchor);
		}
	}

	private function prepareSeedFromTiledObject(xml:Xml):ArpSeed {
		var x:Xml = Xml.createElement("root");
		var type:String = xml.get("type");
		if (type != null) x.set("class", type);
		for (properties in xml.elementsNamed("properties")) {
			for (property in properties.elementsNamed("property")) {
				x.set(property.get("name"), property.get("value"));
			}
		}
		return ArpSeed.fromXml(x);
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
				var bytes:Bytes = Base64.decode(StringTools.trim(data.firstChild().nodeValue));
				bytes = Inflate.run(bytes);
				var input:IInput = new BytesInputWrapper(bytes);
				for (y in 0...height) {
					row = [];
					for (x in 0...width) {
						row.push(input.readInt32() - 1);
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
