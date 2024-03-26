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
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {PortalHelpers} from "../../helpers/PortalHelpers.sol";

contract CrossChainGovernorPortalTest is Test, PortalHelpers {
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
    uint64 public crossChainSelector2 = 7777;
    uint32 public executionDelay = 4 hours;

    function setUp() public {
        vm.prank(governor);
        linkToken = new ERC20Mock("LINK", "LINK", 1000000);
        uint64[] memory supportedChains = new uint64[](3);
        supportedChains[0] = governorChainSelector;
        supportedChains[1] = crossChainSelector;
        supportedChains[2] = crossChainSelector2;
        ccipRouter = new CcipRouterMock(address(linkToken), crossChainSelector, supportedChains);
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
            crossChainSelector,
            address(crossChainPortal),
            executionDelay
        );
        uint64[] memory destChainSelectors = new uint64[](1);
        uint64[] memory routeChainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        destChainSelectors[0] = crossChainSelector;
        routeChainSelectors[0] = crossChainSelector;
        portals[0] = address(crossChainPortal);
        vm.prank(governor);
        governorPortal.setRoutes(destChainSelectors, routeChainSelectors, portals);
    }

    function test__CCGP_SetExecutionDelay_RevertIfNotSelfCall() public {
        (,,, uint32 currentExecutionDelay) = crossChainPortal.getPortalState();
        uint32 newExecutionDelay = 30;
        assertTrue(newExecutionDelay != currentExecutionDelay);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.setExecutionDelay(newExecutionDelay);
        vm.prank(governor);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.setExecutionDelay(newExecutionDelay);
        vm.prank(address(crossChainPortal));
        crossChainPortal.setExecutionDelay(newExecutionDelay);
        (,,, currentExecutionDelay) = crossChainPortal.getPortalState();
        assertEq(currentExecutionDelay, newExecutionDelay);
    }

    function test__CCGP_SetIntervalCommunicationLost_RevertIfNotSelfCall() public {
        uint32 currentInterval = crossChainPortal.getIntervalCommunicationLost();
        uint32 newInterval = 10 days;
        assertTrue(currentInterval != newInterval);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.setIntervalCommunicationLost(newInterval);
        vm.prank(governor);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.setIntervalCommunicationLost(newInterval);
        vm.prank(address(crossChainPortal));
        crossChainPortal.setIntervalCommunicationLost(newInterval);
        currentInterval = crossChainPortal.getIntervalCommunicationLost();
        assertEq(currentInterval, newInterval);
    }

    function test__CCGP_SetGuardians_RevertIfNotSelfCall() public {
        address[] memory targets = new address[](1);
        bool[] memory enableds = new bool[](1);
        targets[0] = bob;
        enableds[0] = true;
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.setGuardians(targets, enableds);
        vm.prank(governor);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.setGuardians(targets, enableds);
        vm.prank(address(crossChainPortal));
        crossChainPortal.setGuardians(targets, enableds);
        assertTrue(crossChainPortal.isGuardian(bob));
    }

    function test__CCGP_SetRoutes_RevertIfNotSelfCall() public {
        uint64[] memory chainSelectors = new uint64[](1);
        uint64[] memory routeChainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        routeChainSelectors[0] = crossChainSelector;
        portals[0] = address(crossChainPortal);
        (uint64 routeChainSelector, address routePortal) = crossChainPortal.getRoute(chainSelectors[0]);
        assertTrue(routePortal == address(0) && routeChainSelector == 0);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.setRoutes(chainSelectors, routeChainSelectors, portals);
        vm.prank(governor);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.setRoutes(chainSelectors, routeChainSelectors, portals);
        vm.prank(address(crossChainPortal));
        crossChainPortal.setRoutes(chainSelectors, routeChainSelectors, portals);
        (routeChainSelector, routePortal) = crossChainPortal.getRoute(chainSelectors[0]);
        assertTrue(routePortal == address(crossChainPortal) && routeChainSelector == crossChainSelector);
    }

    function test__CCGP_SetActionsOrigins_RevertIfNotSelfCall() public {
        address[] memory senders = new address[](1);
        uint64[] memory chainSelectors = new uint64[](1);
        bool[] memory enableds = new bool[](1);
        senders[0] = address(crossChainPortal);
        chainSelectors[0] = crossChainSelector;
        enableds[0] = true;
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.setActionsOrigins(senders, chainSelectors, enableds);
        vm.prank(governor);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.setActionsOrigins(senders, chainSelectors, enableds);
        vm.prank(address(crossChainPortal));
        crossChainPortal.setActionsOrigins(senders, chainSelectors, enableds);
    }

    function test__CCGP_SetPendingGovernor_RevertIfNotSelfCall() public {
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.setPendingGovernor(bob, crossChainSelector2);
        vm.prank(governor);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.setPendingGovernor(bob, crossChainSelector2);
        vm.prank(address(crossChainPortal));
        crossChainPortal.setPendingGovernor(bob, crossChainSelector2);
    }

    function test__CCGP_TransferGovernance() public {
        vm.prank(address(crossChainPortal));
        crossChainPortal.setPendingGovernor(bob, crossChainSelector2);
        vm.prank(bob);
        vm.expectRevert(Guardable.Guardable__NotGuardian.selector);
        crossChainPortal.transferGovernance();
        vm.warp(block.timestamp + 3 days);
        address[] memory guardians = new address[](2);
        bool[] memory enableds = new bool[](2);
        guardians[0] = bob;
        guardians[1] = alice;
        enableds[0] = true;
        enableds[1] = true;
        vm.prank(address(crossChainPortal));
        crossChainPortal.setGuardians(guardians, enableds);
        vm.prank(bob);
        crossChainPortal.curse(guardian);
        vm.prank(alice);
        crossChainPortal.curse(guardian);
        vm.prank(guardian);
        vm.expectRevert(Guardable.Guardable__CursedGuardian.selector);
        crossChainPortal.transferGovernance();
        vm.prank(bob);
        crossChainPortal.transferGovernance();
    }

    function test__CCGP_Teleport_RevertIfNotSelfCall() public {
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.teleport(
            governorChainSelector,
            new address[](0),
            new uint256[](0),
            new string[](0),
            new bytes[](0),
            new address[](0),
            new uint256[](0),
            new bytes(0)
        );
        vm.prank(governor);
        vm.expectRevert(ChainPortal.ChainPortal__NotPortalController.selector);
        crossChainPortal.teleport(
            governorChainSelector,
            new address[](0),
            new uint256[](0),
            new string[](0),
            new bytes[](0),
            new address[](0),
            new uint256[](0),
            new bytes(0)
        );
        vm.prank(address(crossChainPortal));
        vm.expectRevert(abi.encodeWithSelector(ChainPortal.ChainPortal__InvalidChain.selector, crossChainSelector2));
        crossChainPortal.teleport(
            crossChainSelector2,
            new address[](0),
            new uint256[](0),
            new string[](0),
            new bytes[](0),
            new address[](0),
            new uint256[](0),
            new bytes(0)
        );
        vm.prank(address(crossChainPortal));
        crossChainPortal.teleport(
            governorChainSelector,
            new address[](0),
            new uint256[](0),
            new string[](0),
            new bytes[](0),
            new address[](0),
            new uint256[](0),
            new bytes(0)
        );
    }

    function test__CCGP_AbortAction() public {
        Client.Any2EVMMessage memory message = buildMessageWithActionSet(
            address(governorPortal),
            address(governor),
            governorChainSelector,
            crossChainSelector,
            buildSingleActionSet(address(linkToken), 0, "approve(address,uint256)", abi.encode(bob, 1000))
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.prank(guardian);
        crossChainPortal.abortAction(0);
    }

    function test__CCGP_CcipReceive_ForwardActionSet() public {
        Client.Any2EVMMessage memory message = buildMessageWithActionSet(
            address(governorPortal),
            address(governor),
            governorChainSelector,
            crossChainSelector2,
            buildSingleActionSet(address(linkToken), 0, "approve(address,uint256)", abi.encode(bob, 1000))
        );
        setRoute(
            crossChainPortal,
            address(crossChainPortal),
            crossChainSelector2,
            crossChainSelector2,
            address(crossChainPortal2)
        );
        setRoute(
            crossChainPortal2,
            address(crossChainPortal2),
            crossChainSelector,
            crossChainSelector,
            address(crossChainPortal)
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
    }

    function test__CCGP_EmergencyCommunicationLost() public {
        Portal.ActionSet memory actionSet =
            buildSingleActionSet(address(linkToken), 0, "approve(address,uint256)", abi.encode(bob, 1000));
        Client.Any2EVMMessage memory message = buildMessageWithActionSet(
            address(governorPortal), address(governor), governorChainSelector, crossChainSelector, actionSet
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.prank(bob);
        vm.expectRevert(Guardable.Guardable__NotGuardian.selector);
        crossChainPortal.emergencyCommunicationLost(actionSet);
        vm.prank(guardian);
        vm.expectRevert(CrossChainGovernorPortal.CrossChainGovernorPortal__CommunicationNotLost.selector);
        crossChainPortal.emergencyCommunicationLost(actionSet);
        address[] memory guardians = new address[](2);
        bool[] memory enableds = new bool[](2);
        guardians[0] = bob;
        guardians[1] = alice;
        enableds[0] = true;
        enableds[1] = true;
        vm.prank(address(crossChainPortal));
        crossChainPortal.setGuardians(guardians, enableds);
        vm.prank(bob);
        crossChainPortal.curse(guardian);
        vm.prank(alice);
        crossChainPortal.curse(guardian);
        vm.prank(guardian);
        vm.expectRevert(Guardable.Guardable__CursedGuardian.selector);
        crossChainPortal.emergencyCommunicationLost(actionSet);
        vm.warp(block.timestamp + crossChainPortal.getIntervalCommunicationLost() + 1);
        vm.prank(bob);
        crossChainPortal.emergencyCommunicationLost(actionSet);
    }
}
