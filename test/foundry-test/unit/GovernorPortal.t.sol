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
import {ERC20, ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {PortalHelpers} from "../../helpers/PortalHelpers.sol";
import "forge-std/console.sol";

contract GovernorPortalTest is Test, PortalHelpers {
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

    uint256 public linkSupply = 1e9 ether;
    uint64 public governorChainSelector = uint64(block.chainid);
    uint64 public crossChainSelector = 4444;
    uint64 public crossChainSelector2 = 7777;
    uint32 public executionDelay = 4 hours;

    function setUp() public {
        vm.prank(governor);
        linkToken = new ERC20Mock("LINK", "LINK", linkSupply);
        uint64[] memory supportedChains = new uint64[](3);
        supportedChains[0] = governorChainSelector;
        supportedChains[1] = crossChainSelector;
        supportedChains[2] = crossChainSelector2;
        ccipRouter = new CcipRouterMock(address(linkToken), uint64(block.chainid), supportedChains);
        governorPortal = new GovernorPortal(
            governor, guardian, address(ccipRouter), address(linkToken), governorChainSelector, executionDelay
        );

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

        crossChainPortal2 = new CrossChainGovernorPortal(
            governor,
            guardian,
            address(ccipRouter),
            address(linkToken),
            crossChainSelector2,
            governorChainSelector,
            0,
            address(governorPortal),
            executionDelay
        );
    }

    function test__GP_SetExecutionDelay() public {
        (,,, uint32 currentExecutionDelay) = governorPortal.getPortalState();
        uint32 newExecutionDelay = 30;
        assertTrue(newExecutionDelay != currentExecutionDelay);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        governorPortal.setExecutionDelay(newExecutionDelay);
        vm.prank(governor);
        governorPortal.setExecutionDelay(newExecutionDelay);
        (,,, currentExecutionDelay) = governorPortal.getPortalState();
        assertEq(currentExecutionDelay, newExecutionDelay);
    }

    function test__GP_SetGuardians() public {
        address[] memory targets = new address[](1);
        bool[] memory enableds = new bool[](1);
        targets[0] = guardian;
        enableds[0] = false;
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        governorPortal.setGuardians(targets, enableds);
        vm.prank(guardian);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        governorPortal.setGuardians(targets, enableds);
        assertTrue(governorPortal.isGuardian(guardian));
        vm.prank(governor);
        governorPortal.setGuardians(targets, enableds);
        assertFalse(governorPortal.isGuardian(guardian));
    }

    function test__GP_SetRoutes() public {
        uint64[] memory chainSelectors = new uint64[](2);
        uint64[] memory routeChainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        routeChainSelectors[0] = 1234;
        portals[0] = address(crossChainPortal);
        (uint64 routeChainSelector, address routePortal) = governorPortal.getRoute(chainSelectors[0]);
        assertTrue(routePortal == address(0) && routeChainSelector == 0);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        governorPortal.setRoutes(chainSelectors, routeChainSelectors, portals);
        vm.prank(guardian);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        governorPortal.setRoutes(chainSelectors, routeChainSelectors, portals);
        vm.startPrank(governor);
        vm.expectRevert(ChainPortal.ChainPortal__InconsistentParamsLength.selector);
        governorPortal.setRoutes(chainSelectors, routeChainSelectors, portals);
        chainSelectors = new uint64[](1);
        chainSelectors[0] = crossChainSelector;
        vm.expectRevert(abi.encodeWithSelector(ChainPortal.ChainPortal__UnsupportedRoute.selector, 1234));
        governorPortal.setRoutes(chainSelectors, routeChainSelectors, portals);
        routeChainSelectors[0] = crossChainSelector;
        governorPortal.setRoutes(chainSelectors, routeChainSelectors, portals);
        (routeChainSelector, routePortal) = governorPortal.getRoute(chainSelectors[0]);
        assertTrue(routePortal == address(crossChainPortal) && routeChainSelector == crossChainSelector);
    }

    function test__GP_SetActionsOrigins() public {
        address[] memory senders = new address[](2);
        uint64[] memory chainSelectors = new uint64[](1);
        bool[] memory enableds = new bool[](1);
        senders[0] = address(crossChainPortal);
        chainSelectors[0] = crossChainSelector;
        enableds[0] = true;
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        governorPortal.setActionsOrigins(senders, chainSelectors, enableds);
        vm.prank(governor);
        vm.expectRevert(ChainPortal.ChainPortal__InconsistentParamsLength.selector);
        governorPortal.setActionsOrigins(senders, chainSelectors, enableds);
        senders = new address[](1);
        senders[0] = address(crossChainPortal);
        vm.prank(governor);
        governorPortal.setActionsOrigins(senders, chainSelectors, enableds);
    }

    function test__GP_SetExtraArgs() public {
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        governorPortal.setRoutingCcipExtraArgs(new bytes(1));
        vm.prank(governor);
        governorPortal.setRoutingCcipExtraArgs(new bytes(1));
    }

    function test__GP_Teleport() public {
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        address[] memory bridgedTokens = new address[](1);
        uint256[] memory tokenAmounts = new uint256[](1);
        bridgedTokens[0] = address(linkToken);
        tokenAmounts[0] = 1000;
        governorPortal.teleport(
            crossChainSelector,
            new address[](0),
            new uint256[](0),
            new string[](0),
            new bytes[](0),
            bridgedTokens,
            tokenAmounts,
            new bytes(0)
        );
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(ChainPortal.ChainPortal__InvalidChain.selector, crossChainSelector));
        governorPortal.teleport(
            crossChainSelector,
            new address[](0),
            new uint256[](0),
            new string[](0),
            new bytes[](0),
            bridgedTokens,
            tokenAmounts,
            new bytes(0)
        );
        setRoute(governorPortal, governor, crossChainSelector, crossChainSelector, address(crossChainPortal));
        vm.startPrank(governor);
        linkToken.approve(address(governorPortal), 1000);
        assertTrue(linkToken.balanceOf(governor) == linkSupply);
        governorPortal.teleport(
            crossChainSelector,
            new address[](0),
            new uint256[](0),
            new string[](0),
            new bytes[](0),
            bridgedTokens,
            tokenAmounts,
            new bytes(0)
        );
        assertTrue(linkToken.balanceOf(governor) == linkSupply - 1000);
        vm.stopPrank();
    }

    function test__GP_CcipReceive_QueueActionSet() public {
        Client.Any2EVMMessage memory message = buildMessageWithActionSet(
            address(crossChainPortal),
            address(crossChainPortal),
            crossChainSelector,
            governorChainSelector,
            buildSingleActionSet(address(linkToken), 0, "approve(address,uint256)", abi.encode(bob, 1000))
        );
        vm.prank(rob);
        vm.expectRevert(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, rob));
        governorPortal.ccipReceive(message);
        vm.prank(address(ccipRouter));
        vm.expectRevert(abi.encodeWithSelector(ChainPortal.ChainPortal__InvalidChain.selector, crossChainSelector));
        governorPortal.ccipReceive(message);
        setRoute(governorPortal, governor, crossChainSelector, crossChainSelector, address(crossChainPortal));
        vm.prank(address(ccipRouter));
        governorPortal.ccipReceive(message);
        setActionOrigin(governorPortal, governor, address(crossChainPortal), crossChainSelector, true);
        vm.prank(address(ccipRouter));
        governorPortal.ccipReceive(message);
        message.sender = abi.encode(bob);
        vm.prank(address(ccipRouter));
        vm.expectRevert(ChainPortal.ChainPortal__InvalidPortal.selector);
        governorPortal.ccipReceive(message);
    }

    function test__GP_CcipReceive_ForwardActionSet() public {
        Client.Any2EVMMessage memory message = buildMessageWithActionSet(
            address(crossChainPortal),
            address(crossChainPortal),
            crossChainSelector,
            crossChainSelector2,
            buildSingleActionSet(address(linkToken), 0, "approve(address,uint256)", abi.encode(bob, 1000))
        );
        Client.EVMTokenAmount[] memory tokensData = new Client.EVMTokenAmount[](1);
        tokensData[0].token = address(linkToken);
        tokensData[0].amount = 1000;
        message.destTokenAmounts = tokensData;
        vm.prank(governor);
        linkToken.transfer(address(governorPortal), 1000);
        setRoute(governorPortal, governor, crossChainSelector, crossChainSelector, address(crossChainPortal));
        vm.prank(address(ccipRouter));
        governorPortal.ccipReceive(message);
        setRoute(governorPortal, governor, crossChainSelector2, crossChainSelector2, address(crossChainPortal2));
        vm.prank(address(ccipRouter));
        governorPortal.ccipReceive(message);
    }

    function test__GP_AbortAction() public {
        Client.Any2EVMMessage memory message = buildMessageWithActionSet(
            address(crossChainPortal),
            address(crossChainPortal),
            crossChainSelector,
            governorChainSelector,
            buildSingleActionSet(address(linkToken), 0, "approve(address,uint256)", abi.encode(bob, 1000))
        );
        setRoute(governorPortal, governor, crossChainSelector, crossChainSelector, address(crossChainPortal));
        setActionOrigin(governorPortal, governor, address(crossChainPortal), crossChainSelector, true);
        vm.prank(address(ccipRouter));
        governorPortal.ccipReceive(message);
        vm.expectRevert(ChainPortal.ChainPortal__UnauthorizedAbort.selector);
        governorPortal.abortAction(0);
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(ChainPortal.ChainPortal__InvalidActionSetId.selector, 1));
        governorPortal.abortAction(1);
        vm.prank(guardian);
        governorPortal.abortAction(0);
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(ChainPortal.ChainPortal__ActionSetNotPending.selector, 0));
        governorPortal.abortAction(0);
    }

    function test__GP_executeTeleportAction() public {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(linkToken);
        amounts[0] = 1000;
        bytes memory callData = abi.encode(
            governorChainSelector,
            new address[](0),
            new uint256[](0),
            new string[](0),
            new bytes[](0),
            tokens,
            amounts,
            new bytes(0)
        );
        Client.Any2EVMMessage memory message = buildMessageWithActionSet(
            address(governorPortal),
            governor,
            governorChainSelector,
            crossChainSelector,
            buildSingleActionSet(
                address(crossChainPortal),
                0,
                "teleport(uint64,address[],uint256[],string[],bytes[],address[],uint256[],bytes)",
                callData
            )
        );
        setRoute(governorPortal, governor, crossChainSelector, crossChainSelector, address(crossChainPortal));
        setActionOrigin(governorPortal, governor, address(crossChainPortal), crossChainSelector, true);
        vm.prank(governor);
        linkToken.transfer(address(crossChainPortal), 1000);
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        ccipRouter.setChainSelector(crossChainSelector);
        vm.warp(block.timestamp + executionDelay);
        vm.prank(alice);
        crossChainPortal.executePendingAction();
    }

    function test__GP_executeAction() public {
        Client.Any2EVMMessage memory message = buildMessageWithActionSet(
            address(crossChainPortal),
            address(crossChainPortal),
            crossChainSelector,
            governorChainSelector,
            buildSingleActionSet(address(linkToken), 0, "approve(address,uint256)", abi.encode(bob, 1000))
        );
        setRoute(governorPortal, governor, crossChainSelector, crossChainSelector, address(crossChainPortal));
        setActionOrigin(governorPortal, governor, address(crossChainPortal), crossChainSelector, true);
        vm.prank(address(ccipRouter));
        governorPortal.ccipReceive(message);
        uint256 allowanceBob = linkToken.allowance(address(governorPortal), bob);
        assertEq(allowanceBob, 0);
        vm.expectRevert(ChainPortal.ChainPortal__ActionSetNotExecutable.selector);
        governorPortal.executePendingAction();
        vm.warp(block.timestamp + executionDelay);
        governorPortal.performUpkeep(new bytes(0));
        allowanceBob = linkToken.allowance(address(governorPortal), bob);
        assertEq(allowanceBob, 1000);
    }

    function test__GP_skipAbortedAndExecuteAction() public {
        Client.Any2EVMMessage memory message = buildMessageWithActionSet(
            address(crossChainPortal),
            address(crossChainPortal),
            crossChainSelector,
            governorChainSelector,
            buildSingleActionSet(
                address(linkToken),
                0,
                "",
                abi.encodePacked(bytes4(keccak256(bytes("approve(address,uint256)"))), abi.encode(bob, 1000))
            )
        );
        setRoute(governorPortal, governor, crossChainSelector, crossChainSelector, address(crossChainPortal));
        setActionOrigin(governorPortal, governor, address(crossChainPortal), crossChainSelector, true);
        vm.prank(address(ccipRouter));
        governorPortal.ccipReceive(message);
        vm.prank(address(ccipRouter));
        governorPortal.ccipReceive(message);
        vm.prank(guardian);
        governorPortal.abortAction(0);
        uint256 allowanceBob = linkToken.allowance(address(governorPortal), bob);
        assertEq(allowanceBob, 0);
        vm.expectRevert(ChainPortal.ChainPortal__ActionSetNotExecutable.selector);
        governorPortal.executePendingAction();
        vm.warp(block.timestamp + executionDelay);
        governorPortal.performUpkeep(new bytes(0));
        allowanceBob = linkToken.allowance(address(governorPortal), bob);
        assertEq(allowanceBob, 1000);
    }

    function test__GP_RevertOnActionExecution() public {
        Client.Any2EVMMessage memory message = buildMessageWithActionSet(
            address(crossChainPortal),
            address(crossChainPortal),
            crossChainSelector,
            governorChainSelector,
            buildSingleActionSet(address(linkToken), 0, "based(address,uint256)", abi.encode(bob, 1000))
        );
        setRoute(governorPortal, governor, crossChainSelector, crossChainSelector, address(crossChainPortal));
        setActionOrigin(governorPortal, governor, address(crossChainPortal), crossChainSelector, true);
        vm.prank(address(ccipRouter));
        governorPortal.ccipReceive(message);
        vm.warp(block.timestamp + executionDelay);
        vm.expectRevert(ChainPortal.ChainPortal__ActionSetExecutionFailed.selector);
        governorPortal.executePendingAction();
    }
}
