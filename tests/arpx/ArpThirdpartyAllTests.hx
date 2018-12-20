package arpx;

import picotest.PicoTest;

class ArpThirdpartyAllTests {
	static function main() {
		var r = PicoTest.runner();
		ArpThirdpartyTestSuite.addTo(r);
		r.run();
	}
}
