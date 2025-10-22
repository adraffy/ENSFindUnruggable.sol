// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IUniversalResolver} from "@ens/universalResolver/IUniversalResolver.sol";
import {IMulticallable} from "@ens/resolvers/IMulticallable.sol";
import {IAddressResolver} from "@ens/resolvers/profiles/IAddressResolver.sol";
import {ITextResolver} from "@ens/resolvers/profiles/ITextResolver.sol";
import {INameResolver} from "@ens/resolvers/profiles/INameResolver.sol";
import {IExtendedResolver} from "@ens/resolvers/profiles/IExtendedResolver.sol";
import {EIP3668, OffchainLookup} from "@ens/ccipRead/EIP3668.sol";
import {BytesUtils} from "@ens/utils/BytesUtils.sol";
import {NameCoder} from "@ens/utils/NameCoder.sol";
import {ERC165Checker} from "@oz/utils/introspection/ERC165Checker.sol";
import {IGatewayVerifier} from "@urg/IGatewayVerifier.sol";

contract ENSFindUnruggable {
    IUniversalResolver public immutable UR;

    constructor(IUniversalResolver ur) {
        UR = ur;
    }

    function findUnruggable(
        bytes calldata name
    ) external view returns (IGatewayVerifier, string[] memory) {
        bytes[] memory calls = new bytes[](5);
        bytes32 node = NameCoder.namehash(name, 0);
        calls[0] = abi.encodeCall(IAddressResolver.addr, (node, 60));
        calls[1] = abi.encodeCall(IAddressResolver.addr, (node, 1 << 255));
        calls[2] = abi.encodeCall(ITextResolver.text, (node, "avatar"));
        calls[3] = abi.encodeCall(ITextResolver.text, (node, "\uFE0F"));
        calls[4] = abi.encodeCall(INameResolver.name, (node));
        return _findUnruggable(name, calls);
    }

    function findUnruggable(
        bytes calldata name,
        bytes calldata data
    ) external view returns (IGatewayVerifier, string[] memory) {
        bytes[] memory calls;
        if (bytes4(data) == IMulticallable.multicall.selector) {
            calls = abi.decode(data[4:], (bytes[]));
        } else {
            calls = new bytes[](1);
            calls[0] = data;
        }
        return _findUnruggable(name, calls);
    }

    function _findUnruggable(
        bytes memory name,
        bytes[] memory calls
    )
        internal
        view
        returns (IGatewayVerifier verifier, string[] memory gateways)
    {
        (address resolver, , ) = UR.findResolver(name);
        if (resolver == address(0)) {
            revert IUniversalResolver.ResolverNotFound(name);
        }
        if (resolver.code.length == 0) {
            revert IUniversalResolver.ResolverNotContract(name, resolver);
        }
        bool extended = ERC165Checker.supportsERC165InterfaceUnchecked(
            resolver,
            type(IExtendedResolver).interfaceId
        );
        uint256 found;
        bytes32 contextHash;
        bytes32 gatewaysHash;
        for (uint256 i; i < calls.length; ++i) {
            bytes memory call = calls[i];
            if (extended) {
                call = abi.encodeCall(IExtendedResolver.resolve, (name, call));
            }
            (bool ok, bytes memory v) = resolver.staticcall{gas: 250_000}(call);
            if (ok || bytes4(v) != OffchainLookup.selector) continue;
            // TODO: add min length check?
            EIP3668.Params memory p = EIP3668.decode(
                BytesUtils.substring(v, 4, v.length - 4)
            );
            if (p.sender != resolver) continue;
            PartialSession memory s = _tryDecodeSession(p.extraData);
            if (s.verifier == address(0)) continue;
            if (
                found != 0 &&
                (address(s.verifier) != address(verifier) ||
                    _gatewayHash(p.urls) != gatewaysHash ||
                    keccak256(s.context) != contextHash)
            ) {
                verifier = IGatewayVerifier(address(0));
                gateways = new string[](0);
                break;
            }
            if (found == 0) {
                verifier = IGatewayVerifier(s.verifier);
                gateways = p.urls;
                gatewaysHash = _gatewayHash(gateways);
                contextHash = keccak256(s.context);
            }
            ++found;
        }
    }

    function _gatewayHash(
        string[] memory gateways
    ) internal pure returns (bytes32 hash) {
        for (uint256 i; i < gateways.length; i++) {
            hash ^= keccak256(bytes(gateways[i]));
        }
    }

    struct PartialSession {
        address verifier;
        bytes context;
    }

    function _tryDecodeSession(
        bytes memory v
    ) internal view returns (PartialSession memory s) {
        // https://github.com/unruggable-labs/unruggable-gateways/blob/main/contracts/GatewayFetchTarget.sol#L20C1-L26C6
        uint256 length = 32;
        if (length > v.length) return s;
        uint256 offset = uint256(BytesUtils.readBytes32(v, 0));
        length = offset + 160;
        if (length > v.length) return s;
        address verifier = address(
            uint160(uint256(BytesUtils.readBytes32(v, offset)))
        );
        if (verifier.code.length == 0) return s;
        offset += uint256(BytesUtils.readBytes32(v, offset + 32));
        length = offset + 32;
        if (length > v.length) return s;
        uint256 size = uint256(BytesUtils.readBytes32(v, offset));
        length += size;
        if (length > v.length) return s;
        bytes memory context = BytesUtils.substring(v, offset + 32, size);
        try IGatewayVerifier(verifier).getLatestContext() returns (
            bytes memory context_
        ) {
            if (keccak256(context) != keccak256(context_)) {
                return s;
            }
        } catch {
            return s;
        }
        return PartialSession(verifier, context);
    }
}
