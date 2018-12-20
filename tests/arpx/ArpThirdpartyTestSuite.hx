package arpx;

import picotest.PicoTestRunner;

class ArpThirdpartyTestSuite {
	public static function addTo(r:PicoTestRunner) {
		r.load(ArpThirdpartyComponentsCase);
		#if flash
		r.load(ArpThirdpartyFlashComponentsCase);
		#end
	}
}
