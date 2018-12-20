package arpx;

#if flash
import arpx.external.TiledExternal;

import picotest.PicoAssert.*;

class ArpThirdpartyFlashComponentsCase {

	public function testFields() {
		assertNotNull(new TiledExternal());
	}

}
#end
