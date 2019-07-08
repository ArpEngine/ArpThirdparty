package arpx.tileMap;

import arp.io.IInput;
import arpx.file.File;

@:arpType("tileMap", "fmfFile")
class FmfFileTileMap extends ArrayTileMap {

	@:arpBarrier(true, true) @:arpField public var file:File;

	public function new() {
		super();
	}

	override private function heatUp():Bool {
		if (this.map != null) return true;

		this.map = [];

		var input:IInput = this.file.read();
		input.bigEndian = false;
		var tag:Int = input.readInt32();
		if (tag != 0x5F464D46) return true;

		input.readInt32(); //map data size
		var width:Int = input.readInt32();
		var height:Int = input.readInt32();
		input.readUInt8(); //chipWidth
		input.readUInt8(); //chipHeight
		input.readUInt8(); //layerCount
		var bitCount:Int = input.readUInt8();

		this.width = width;
		this.height = height;
		var line:Array<Int> = [];
		switch (bitCount) {
			case 8:
				for (j in 0...height) {
					line = [];
					this.map.push(line);
					for (i in 0...width) line.push(input.readUInt8());
				}
			case 16:
				for (j in 0...height) {
					line = [];
					this.map.push(line);
					for (i in 0...width) line.push(input.readUInt16());
				}
		}
		return true;
	}
}


