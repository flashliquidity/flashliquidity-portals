// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Client, Portal, ChainPortal} from "../../contracts/ChainPortal.sol";

abstract contract PortalHelpers is Test {
    function setActionOrigin(
        ChainPortal portal,
        address governor,
        address origin,
        uint64 srcChainSelector,
        bool isAuthorized
    ) public {
        address[] memory origins = new address[](1);
        uint64[] memory srcChainSelectors = new uint64[](1);
        bool[] memory authorizeds = new bool[](1);
        origins[0] = origin;
        srcChainSelectors[0] = srcChainSelector;
        authorizeds[0] = isAuthorized;
        vm.prank(governor);
        portal.setActionsOrigins(origins, srcChainSelectors, authorizeds);
    }

    function setRoute(
        ChainPortal portal,
        address governor,
        uint64 chainSelector,
        uint64 routeChainSelector,
        address routePortal
    ) public {
        uint64[] memory chainSelectors = new uint64[](1);
        uint64[] memory routeChainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = chainSelector;
        routeChainSelectors[0] = routeChainSelector;
        portals[0] = routePortal;
        vm.prank(governor);
        portal.setRoutes(chainSelectors, routeChainSelectors, portals);
    }

    function buildSingleActionSet(address target, uint256 value, string memory signature, bytes memory callData)
        public
        pure
        returns (Portal.ActionSet memory)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = target;
        values[0] = value;
        signatures[0] = signature;
        calldatas[0] = callData;
        return Portal.ActionSet(targets, values, signatures, calldatas);
    }

    function buildMessageWithActionSet(
        address fromPortal,
        address sender,
        uint64 srcChainSelector,
        uint64 destChainSelector,
        Portal.ActionSet memory actionSet
    ) public pure returns (Client.Any2EVMMessage memory) {
        Portal.ActionSetHeader memory actionSetHeader = Portal.ActionSetHeader({
            sender: sender,
            srcChainSelector: srcChainSelector,
            destChainSelector: destChainSelector,
            ccipExtraArgs: new bytes(0)
        });
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);
        return Client.Any2EVMMessage(
            bytes32(uint256(1)),
            srcChainSelector,
            abi.encode(fromPortal),
            abi.encode(actionSetHeader, actionSet),
            tokenAmounts
        );
    }

    function test() public {}
}
