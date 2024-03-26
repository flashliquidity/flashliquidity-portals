// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {GovernorPortal} from "../../../contracts/GovernorPortal.sol";
import {CrossChainGovernorPortal} from "../../../contracts/CrossChainGovernorPortal.sol";
import {Portal, ChainPortal} from "../../../contracts/ChainPortal.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {Guardable} from "flashliquidity-acs/contracts/Guardable.sol";
import {CcipRouterMock} from "../../mocks/CcipRouterMock.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract ChainPortalTest is Test {
    GovernorPortal public governorPortal;
    CrossChainGovernorPortal public crossChainPortal;
    CrossChainGovernorPortal public crossChainPortal2;
    CcipRouterMock public ccipRouter;
    ERC20Mock public linkToken;
    address public governor = makeAddr("governor");
    address public guardian = makeAddr("guardian");
    address public bob = makeAddr("bob");
    address public alice = makeAddr("alice");
    address public rob = makeAddr("rob");

    uint64 public governorChainSelector = uint64(block.chainid);
    uint64 public crossChainSelector = 4444;
    uint32 public executionDelay = 4 hours;

    function setUp() public {
        vm.prank(governor);
        linkToken = new ERC20Mock("LINK", "LINK", 1000000);
        uint64[] memory supportedChains = new uint64[](2);
        supportedChains[0] = governorChainSelector;
        supportedChains[1] = crossChainSelector;
        ccipRouter = new CcipRouterMock(address(linkToken), uint64(block.chainid), supportedChains);
        governorPortal = new GovernorPortal(
            governor, guardian, address(ccipRouter), address(linkToken), governorChainSelector, executionDelay
        );
        uint64[] memory destChainSelectors = new uint64[](1);
        uint64[] memory routeChainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        destChainSelectors[0] = governorChainSelector;
        routeChainSelectors[0] = governorChainSelector;
        portals[0] = address(governorPortal);
        crossChainPortal = new CrossChainGovernorPortal(
            governor,
            guardian,
            address(ccipRouter),
            address(linkToken),
            crossChainSelector,
            governorChainSelector,
            0,
            address(governorPortal),
            executionDelay
        );
    }

    function test_GP_FuzzTeleport(
        uint64 destChainSelector,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        address[] memory tokens,
        uint256[] memory amounts
    ) public {
        (uint64 routeChainSelector, address routePortal) = governorPortal.getRoute(destChainSelector);
        if (msg.sender != governor) {
            vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        } else if (
            targets.length != values.length || values.length != signatures.length
                || signatures.length != calldatas.length || tokens.length != amounts.length
        ) {
            vm.expectRevert(ChainPortal.ChainPortal__InconsistentParamsLength.selector);
        } else if (routeChainSelector == 0 || routePortal == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(ChainPortal.ChainPortal__InvalidChain.selector, destChainSelector));
        }
        governorPortal.teleport(
            destChainSelector, targets, values, signatures, calldatas, tokens, amounts, new bytes(0)
        );
    }

    function test_CCGP_FuzzTeleport(
        uint64 destChainSelector,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        address[] memory tokens,
        uint256[] memory amounts
    ) public {
        (uint64 routeChainSelector, address routePortal) = crossChainPortal.getRoute(destChainSelector);
        if (msg.sender != address(crossChainPortal)) {
            vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        } else if (
            targets.length != values.length || values.length != signatures.length
                || signatures.length != calldatas.length || tokens.length != amounts.length
        ) {
            vm.expectRevert(ChainPortal.ChainPortal__InconsistentParamsLength.selector);
        } else if (routeChainSelector == 0 || routePortal == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(ChainPortal.ChainPortal__InvalidChain.selector, destChainSelector));
        }
        crossChainPortal.teleport(
            destChainSelector, targets, values, signatures, calldatas, tokens, amounts, new bytes(0)
        );
    }

    function test_GP_FuzzCcipReceive(
        bytes32 messageId,
        uint64 senderChainSelector,
        address senderPortal,
        Portal.ActionSetHeader memory actionSetHeader,
        Portal.ActionSet memory actionSet
    ) public {
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage(
            messageId,
            senderChainSelector,
            abi.encode(senderPortal),
            abi.encode(actionSetHeader, actionSet),
            new Client.EVMTokenAmount[](0)
        );
        (uint64 routeChainSelector, address routePortal) = governorPortal.getRoute(senderChainSelector);
        if (routeChainSelector == 0 || routePortal == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(ChainPortal.ChainPortal__InvalidChain.selector, senderChainSelector));
        } else if (senderPortal != routePortal) {
            vm.expectRevert(ChainPortal.ChainPortal__InvalidPortal.selector);
        }
        vm.prank(address(ccipRouter));
        governorPortal.ccipReceive(message);
    }

    function test_CCGP_FuzzCcipReceive(
        bytes32 messageId,
        uint64 senderChainSelector,
        address senderPortal,
        Portal.ActionSetHeader memory actionSetHeader,
        Portal.ActionSet memory actionSet
    ) public {
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage(
            messageId,
            senderChainSelector,
            abi.encode(senderPortal),
            abi.encode(actionSetHeader, actionSet),
            new Client.EVMTokenAmount[](0)
        );
        (uint64 routeChainSelector, address routePortal) = crossChainPortal.getRoute(senderChainSelector);
        if (routeChainSelector == 0 || routePortal == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(ChainPortal.ChainPortal__InvalidChain.selector, senderChainSelector));
        } else if (senderPortal != routePortal) {
            vm.expectRevert(ChainPortal.ChainPortal__InvalidPortal.selector);
        }
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
    }

    function test_FuzzGettersCantRevert(uint64 actionId, uint64 chainSelector) public view {
        governorPortal.getActionSetById(actionId);
        governorPortal.getActionSetInfoById(actionId);
        governorPortal.getRoute(chainSelector);
        governorPortal.getPortalState();
        governorPortal.checkUpkeep(new bytes(0));
        crossChainPortal.getActionSetById(actionId);
        crossChainPortal.getActionSetInfoById(actionId);
        crossChainPortal.getRoute(chainSelector);
        crossChainPortal.getPortalState();
        crossChainPortal.checkUpkeep(new bytes(0));
        crossChainPortal.getIntervalCommunicationLost();
    }
}
