// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BaseChainPortal} from "../../../contracts/BaseChainPortal.sol";
import {ChainPortal, DataTypes} from "../../../contracts/ChainPortal.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {Guardable} from "flashliquidity-acs/contracts/Guardable.sol";
import {CcipRouterMock} from "../../mocks/CcipRouterMock.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

contract BaseChainPortalTest is Test {
    BaseChainPortal public portal;
    CcipRouterMock public ccipRouter;
    ERC20Mock public linkToken;
    address public governor = makeAddr("governor");
    address public guardian = makeAddr("guardian");
    address public bob = makeAddr("bob");
    address public alice = makeAddr("alice");
    address public rob = makeAddr("rob");
    address public cc_portal = makeAddr("cc_portal");

    uint64 public baseChainSelector = uint64(block.chainid);
    uint64 public crossChainSelector = uint64(4444);
    uint32 public executionDelay = 6 hours;
    uint64 public gasLimit = 1e6;

    bytes ChainPortal__InvalidChain =
        abi.encodeWithSelector(ChainPortal.ChainPortal__InvalidChain.selector, uint64(block.chainid));

    function buildMessageWithSingleAction(
        address sender,
        address senderPortal,
        uint64 sourceChainSelector,
        address target,
        uint256 value,
        string memory signature,
        bytes memory callData
    ) internal pure returns (Client.Any2EVMMessage memory) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = target;
        signatures[0] = signature;
        calldatas[0] = callData;
        values[0] = value;
        DataTypes.CrossChainAction memory action =
            DataTypes.CrossChainAction(sender, targets, values, signatures, calldatas);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage(
            bytes32(uint256(0x01)), sourceChainSelector, abi.encode(senderPortal), abi.encode(action), tokenAmounts
        );
        return message;
    }

    function setUp() public {
        vm.warp(1696969691);
        vm.prank(governor);
        linkToken = new ERC20Mock("LINK","LINK", 1000000);
        ccipRouter = new CcipRouterMock(
            address(linkToken),
            uint64(block.chainid)
        );
        portal = new BaseChainPortal(
            governor,
            guardian,
            address(ccipRouter),
            address(linkToken),
            executionDelay
        );
    }

    function test__SetExecutionDelay() public {
        (,, uint64 currentExecutionDelay) = portal.getActionQueueState();
        assertEq(currentExecutionDelay, executionDelay);
        uint64 newExecutionDelay = 30;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        portal.setExecutionDelay(newExecutionDelay);
        vm.prank(governor);
        portal.setExecutionDelay(newExecutionDelay);
        (,, currentExecutionDelay) = portal.getActionQueueState();
        assertEq(currentExecutionDelay, newExecutionDelay);
    }

    function test__SetGuardians() public {
        address[] memory targets = new address[](1);
        bool[] memory enableds = new bool[](1);
        targets[0] = guardian;
        enableds[0] = false;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        portal.setGuardians(targets, enableds);
        vm.prank(guardian);
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        portal.setGuardians(targets, enableds);
        assertTrue(portal.isGuardian(guardian));
        vm.prank(governor);
        portal.setGuardians(targets, enableds);
        assertFalse(portal.isGuardian(guardian));
    }

    function test__SetPortals() public {
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = baseChainSelector;
        portals[0] = address(cc_portal);
        assertEq(portal.getPortal(chainSelectors[0]), address(0));
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        portal.setChainPortals(chainSelectors, portals);
        vm.prank(guardian);
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        portal.setChainPortals(chainSelectors, portals);
        vm.startPrank(governor);
        portal.setChainPortals(chainSelectors, portals);
        assertEq(portal.getPortal(chainSelectors[0]), address(cc_portal));
        chainSelectors = new uint64[](2);
        vm.expectRevert(ChainPortal.ChainPortal__ArrayLengthMismatch.selector);
        portal.setChainPortals(chainSelectors, portals);
        vm.stopPrank();
    }

    function test__SetLanes() public {
        address[] memory senders = new address[](1);
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory targets = new address[](1);
        bool[] memory enableds = new bool[](1);
        senders[0] = bob;
        chainSelectors[0] = baseChainSelector;
        targets[0] = alice;
        enableds[0] = true;
        assertFalse(portal.isAuthorizedLane(senders[0], chainSelectors[0], targets[0]));
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        portal.setLanes(senders, chainSelectors, targets, enableds);
        vm.startPrank(governor);
        portal.setLanes(senders, chainSelectors, targets, enableds);
        assertTrue(portal.isAuthorizedLane(senders[0], chainSelectors[0], targets[0]));
        senders = new address[](2);
        vm.expectRevert(ChainPortal.ChainPortal__ArrayLengthMismatch.selector);
        portal.setLanes(senders, chainSelectors, targets, enableds);
        vm.stopPrank();
    }

    function test__Teleport() public {
        vm.expectRevert(ChainPortal.ChainPortal__ZeroTargets.selector);
        portal.teleport(
            baseChainSelector,
            gasLimit,
            new address[](0),
            new uint256[](0),
            new string[](0),
            new bytes[](0),
            new address[](0),
            new uint256[](0)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        address[] memory senders = new address[](1);
        address[] memory targets = new address[](1);
        bool[] memory enableds = new bool[](1);
        chainSelectors[0] = baseChainSelector;
        portals[0] = address(portal);
        senders[0] = governor;
        targets[0] = bob;
        enableds[0] = true;
        vm.expectRevert(ChainPortal.ChainPortal__LaneNotAvailable.selector);
        portal.teleport(
            baseChainSelector,
            gasLimit,
            targets,
            new uint256[](1),
            new string[](1),
            new bytes[](1),
            new address[](0),
            new uint256[](0)
        );
        vm.startPrank(governor);
        portal.setLanes(senders, chainSelectors, targets, enableds);
        vm.expectRevert(ChainPortal__InvalidChain);
        portal.teleport(
            baseChainSelector,
            gasLimit,
            targets,
            new uint256[](1),
            new string[](1),
            new bytes[](1),
            new address[](0),
            new uint256[](0)
        );
        portal.setChainPortals(chainSelectors, portals);
        portal.teleport(
            baseChainSelector,
            gasLimit,
            targets,
            new uint256[](1),
            new string[](1),
            new bytes[](1),
            new address[](0),
            new uint256[](0)
        );
        address[] memory targetsWrongLength = new address[](2);
        targetsWrongLength[0] = bob;
        targetsWrongLength[1] = bob;
        vm.expectRevert(ChainPortal.ChainPortal__ArrayLengthMismatch.selector);
        portal.teleport(
            baseChainSelector,
            gasLimit,
            targetsWrongLength,
            new uint256[](1),
            new string[](1),
            new bytes[](1),
            new address[](0),
            new uint256[](0)
        );
        vm.stopPrank();
    }

    function test__CcipReceive() public {
        DataTypes.CrossChainAction memory action =
            DataTypes.CrossChainAction(governor, new address[](0), new uint256[](0), new string[](0), new bytes[](0));
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage(
            bytes32(uint256(0x01)), baseChainSelector, abi.encode(address(cc_portal)), abi.encode(action), tokenAmounts
        );
        vm.prank(rob);
        vm.expectRevert(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, rob));
        portal.ccipReceive(message);
        vm.prank(address(ccipRouter));
        vm.expectRevert(ChainPortal__InvalidChain);
        portal.ccipReceive(message);
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = baseChainSelector;
        portals[0] = cc_portal;
        vm.prank(governor);
        portal.setChainPortals(chainSelectors, portals);
        vm.prank(address(ccipRouter));
        portal.ccipReceive(message);
    }

    function test__AbortAction() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            cc_portal,
            crossChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = cc_portal;
        vm.prank(governor);
        portal.setChainPortals(chainSelectors, portals);
        vm.prank(address(ccipRouter));
        portal.ccipReceive(message);
        vm.expectRevert(Guardable.Guardable__NotGuardian.selector);
        portal.abortAction(0);
        vm.prank(guardian);
        portal.abortAction(0);
        uint256 allowanceBob = linkToken.allowance(address(portal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(ChainPortal.ChainPortal__NoActionQueued.selector);
        portal.performUpkeep(new bytes(0));
    }

    function test__ExecuteActionSingleTarget() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            cc_portal,
            crossChainSelector,
            address(linkToken),
            0,
            "",
            abi.encodeWithSignature("approve(address,uint256)", bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = cc_portal;
        vm.prank(governor);
        portal.setChainPortals(chainSelectors, portals);
        vm.prank(address(ccipRouter));
        portal.ccipReceive(message);
        vm.expectRevert(ChainPortal.ChainPortal__ActionNotExecutable.selector);
        portal.performUpkeep(new bytes(0));
        uint256 allowanceBob = linkToken.allowance(address(portal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        portal.performUpkeep(new bytes(0));
        allowanceBob = linkToken.allowance(address(portal), bob);
        assertEq(allowanceBob, approveAmountBob);
    }

    function test__ExecuteActionMultipleTarget() public {
        (uint256 approveAmountBob, uint256 approveAmountRob) = (1000, 2000);
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        string[] memory signatures = new string[](2);
        bytes[] memory calldatas = new bytes[](2);
        (targets[0], targets[1]) = (address(linkToken), address(linkToken));
        (signatures[0], signatures[1]) = ("approve(address,uint256)", "approve(address,uint256)");
        (calldatas[0], calldatas[1]) = (abi.encode(bob, approveAmountBob), abi.encode(rob, approveAmountRob));
        (values[0], values[1]) = (0, 0);
        DataTypes.CrossChainAction memory action =
            DataTypes.CrossChainAction(governor, targets, values, signatures, calldatas);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage(
            bytes32(uint256(0x01)), crossChainSelector, abi.encode(cc_portal), abi.encode(action), tokenAmounts
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = cc_portal;
        vm.prank(governor);
        portal.setChainPortals(chainSelectors, portals);
        vm.prank(address(ccipRouter));
        portal.ccipReceive(message);
        vm.expectRevert(ChainPortal.ChainPortal__ActionNotExecutable.selector);
        portal.performUpkeep(new bytes(0));
        uint256 allowanceBob = linkToken.allowance(address(portal), bob);
        uint256 allowanceRob = linkToken.allowance(address(portal), rob);
        assertEq(allowanceBob, 0);
        assertEq(allowanceRob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        portal.performUpkeep(new bytes(0));
        allowanceBob = linkToken.allowance(address(portal), bob);
        allowanceRob = linkToken.allowance(address(portal), rob);
        assertEq(allowanceBob, approveAmountBob);
        assertEq(allowanceRob, approveAmountRob);
    }

    function test__RevertOnActionExecution() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            cc_portal,
            crossChainSelector,
            address(linkToken),
            0,
            "based(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = cc_portal;
        vm.prank(governor);
        portal.setChainPortals(chainSelectors, portals);
        vm.prank(address(ccipRouter));
        portal.ccipReceive(message);
        vm.expectRevert(ChainPortal.ChainPortal__ActionNotExecutable.selector);
        portal.performUpkeep(new bytes(0));
        uint256 allowanceBob = linkToken.allowance(address(portal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(ChainPortal.ChainPortal__ActionExecutionFailed.selector);
        portal.performUpkeep(new bytes(0));
    }

    function test__SkipAbortedActionAndExecute() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            cc_portal,
            crossChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = cc_portal;
        vm.prank(governor);
        portal.setChainPortals(chainSelectors, portals);
        vm.startPrank(address(ccipRouter));
        portal.ccipReceive(message);
        portal.ccipReceive(message);
        portal.ccipReceive(message);
        vm.stopPrank();
        vm.startPrank(guardian);
        portal.abortAction(0);
        portal.abortAction(1);
        vm.stopPrank();
        uint256 allowanceBob = linkToken.allowance(address(portal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        portal.performUpkeep(new bytes(0));
        allowanceBob = linkToken.allowance(address(portal), bob);
        assertEq(allowanceBob, approveAmountBob);
        vm.expectRevert(ChainPortal.ChainPortal__NoActionQueued.selector);
        portal.performUpkeep(new bytes(0));
    }

    function test__ExecuteActionSkipAbortedAndRevertOnEmpty() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            cc_portal,
            crossChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = cc_portal;
        vm.prank(governor);
        portal.setChainPortals(chainSelectors, portals);
        vm.startPrank(address(ccipRouter));
        portal.ccipReceive(message);
        portal.ccipReceive(message);
        portal.ccipReceive(message);
        vm.stopPrank();
        vm.startPrank(guardian);
        portal.abortAction(0);
        portal.abortAction(1);
        portal.abortAction(2);
        vm.stopPrank();
        uint256 allowanceBob = linkToken.allowance(address(portal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(ChainPortal.ChainPortal__NoActionQueued.selector);
        portal.performUpkeep(new bytes(0));
    }

    function test__ExecuteActionSkipAbortedAndExecute() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            cc_portal,
            crossChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = cc_portal;
        vm.prank(governor);
        portal.setChainPortals(chainSelectors, portals);
        vm.startPrank(address(ccipRouter));
        portal.ccipReceive(message);
        portal.ccipReceive(message);
        portal.ccipReceive(message);
        portal.ccipReceive(message);
        vm.stopPrank();
        uint256 allowanceBob = linkToken.allowance(address(portal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        portal.performUpkeep(new bytes(0));
        allowanceBob = linkToken.allowance(address(portal), bob);
        assertEq(allowanceBob, approveAmountBob);
        vm.startPrank(guardian);
        portal.abortAction(1);
        portal.abortAction(2);
        vm.stopPrank();
        portal.performUpkeep(new bytes(0));
        vm.expectRevert(ChainPortal.ChainPortal__NoActionQueued.selector);
        portal.performUpkeep(new bytes(0));
    }

    function test__ZeroExecutionDelay() public {
        vm.prank(governor);
        portal.setExecutionDelay(0);
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            cc_portal,
            crossChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = cc_portal;
        vm.prank(governor);
        portal.setChainPortals(chainSelectors, portals);
        vm.prank(address(ccipRouter));
        portal.ccipReceive(message);
        uint256 allowanceBob = linkToken.allowance(address(portal), bob);
        assertEq(allowanceBob, approveAmountBob);
    }
}
