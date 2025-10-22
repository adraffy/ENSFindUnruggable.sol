// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {IUniversalResolver} from "@ens/universalResolver/IUniversalResolver.sol";
import {EIP3668} from "@ens/ccipRead/EIP3668.sol";
import {GatewayRequest} from "@urg/IGatewayVerifier.sol";

import {ENSFindUnruggable} from "~src/ENSFindUnruggable.sol";

struct Session {
    address verifier;
    bytes context;
    GatewayRequest req;
    bytes4 callback;
    bytes carry;
}

contract Thing is ENSFindUnruggable {
    constructor() ENSFindUnruggable(IUniversalResolver(address(0))) {}
    function tryDecodeSession(bytes memory v) external view returns (ENSFindUnruggable.PartialSession memory) {
        return _tryDecodeSession(v);
    }
}

contract ENSFindUnruggableTest is Test {
    Thing thing;

    function setUp() external {
        thing = new Thing();
    }
	
	// mock IGatewayVerifier
    function getLatestContext() external pure returns (bytes memory) {
        return hex"123456";
    }

	function _session() internal view returns (Session memory s) {
		s.verifier = address(this);
		s.context = this.getLatestContext();
	}

    function test_tryDecodeSession() external view {
		Session memory s = _session();
		ENSFindUnruggable.PartialSession memory r = thing.tryDecodeSession(abi.encode(s));
		assertEq(r.verifier, s.verifier, "verifier");
		assertEq(r.context, s.context, "context");
    }

	function testFuzz_tryDecodeSession_zeros() external view { 
		for (uint256 i; i < 512; ++i) {
			ENSFindUnruggable.PartialSession memory r = thing.tryDecodeSession(new bytes(i));
			assertEq(r.verifier, address(0));
		}
	}

	function testFuzz_tryDecodeSession_partial() external view {
		Session memory s = _session();
		bytes memory v = abi.encode(s);
		for (uint256 i; i < v.length; ++i) {
			assembly {
				mstore(v, i)
			}
			ENSFindUnruggable.PartialSession memory r = thing.tryDecodeSession(v);
			assertEq(r.verifier, address(0));
		}
	}

}
