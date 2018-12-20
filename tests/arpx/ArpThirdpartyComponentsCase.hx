package arpx;

import arpx.tileMap.FmfFileTileMap;

import picotest.PicoAssert.*;

class ArpThirdpartyComponentsCase {

	public function testFields() {
		assertNotNull(new FmfFileTileMap());
	}

}
