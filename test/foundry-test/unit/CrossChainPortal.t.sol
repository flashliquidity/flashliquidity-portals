// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {CrossChainPortal} from "../../../contracts/CrossChainPortal.sol";
import {BaseChainPortal} from "../../../contracts/BaseChainPortal.sol";
import {ChainPortal} from "../../../contracts/ChainPortal.sol";
import {CrossChainGovernable} from "../../../contracts/types/CrossChainGovernable.sol";
import {Governable} from "../../../contracts/types/Governable.sol";
import {Guardable} from "../../../contracts/types/Guardable.sol";
import {CcipRouterMock} from "../../mocks/CcipRouterMock.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

contract CrossChainPortalTest is Test {
    BaseChainPortal public baseChainPortal;
    CrossChainPortal public crossChainPortal;
    CcipRouterMock public ccipRouter;
    ERC20Mock public linkToken;
    address public governor = makeAddr("governor");
    address public guardian = makeAddr("guardian");
    address public bob = makeAddr("bob");
    address public alice = makeAddr("alice");
    address public rob = makeAddr("rob");

    uint64 public baseChainSelector = uint64(block.chainid);
    uint64 public crossChainSelector = uint64(4444);
    uint64 public gasLimit = 1e6;
    uint32 public executionDelay = 6 hours;
    uint32 public intervalCommunicationLost = 21 days;
    uint32 public intervalGuardianGoneRogue = 7 days;

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
        ChainPortal.CrossChainAction memory action =
            ChainPortal.CrossChainAction(sender, targets, values, signatures, calldatas);
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
            crossChainSelector
        );
        baseChainPortal = new BaseChainPortal(
            governor,
            guardian,
            address(ccipRouter),
            address(linkToken),
            executionDelay
        );
        crossChainPortal = new CrossChainPortal(
            governor,
            guardian,
            address(baseChainPortal),
            address(ccipRouter),
            address(linkToken),
            baseChainSelector,
            executionDelay,
            intervalGuardianGoneRogue,
            intervalCommunicationLost
        );
        address[] memory portals = new address[](1);
        uint64[] memory chainSelectors = new uint64[](1);
        portals[0] = address(crossChainPortal);
        chainSelectors[0] = crossChainSelector;
        vm.prank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
    }

    function testSetExecutionDelayOnlySelf() public {
        (,, uint64 currentExecutionDelay,) = crossChainPortal.getActionQueueState();
        assertEq(currentExecutionDelay, executionDelay);
        uint64 newExecutionDelay = 30;
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotSelfCall.selector);
        crossChainPortal.setExecutionDelay(newExecutionDelay);
        vm.prank(address(crossChainPortal));
        crossChainPortal.setExecutionDelay(newExecutionDelay);
        (,, currentExecutionDelay,) = crossChainPortal.getActionQueueState();
        assertEq(currentExecutionDelay, newExecutionDelay);
    }

    function testSetGuardiansOnlySelf() public {
        address[] memory targets = new address[](1);
        bool[] memory enableds = new bool[](1);
        targets[0] = guardian;
        enableds[0] = false;
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotSelfCall.selector);
        crossChainPortal.setGuardians(targets, enableds);
        assertTrue(crossChainPortal.isGuardian(guardian));
        vm.prank(address(crossChainPortal));
        crossChainPortal.setGuardians(targets, enableds);
        assertFalse(crossChainPortal.isGuardian(guardian));
    }

    function testSetIntervalGuardianGoneRogueOnlySelf() public {
        uint32 newInterval = 100;
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotSelfCall.selector);
        crossChainPortal.setIntervalGuardianGoneRogue(newInterval);
        assertFalse(crossChainPortal.getIntervalGuardianGoneRogue() == newInterval);
        vm.prank(address(crossChainPortal));
        crossChainPortal.setIntervalGuardianGoneRogue(newInterval);
        assertTrue(crossChainPortal.getIntervalGuardianGoneRogue() == newInterval);
    }

    function testSetIntervalCommunicationLostOnlySelf() public {
        uint32 newInterval = 100;
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotSelfCall.selector);
        crossChainPortal.setIntervalCommunicationLost(newInterval);
        assertFalse(crossChainPortal.getIntervalCommunicationLost() == newInterval);
        vm.prank(address(crossChainPortal));
        crossChainPortal.setIntervalCommunicationLost(newInterval);
        assertTrue(crossChainPortal.getIntervalCommunicationLost() == newInterval);
    }

    function testSetPortalsOnlySelf() public {
        assertEq(crossChainPortal.getPortal(baseChainSelector), address(baseChainPortal));
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = baseChainSelector;
        portals[0] = rob;
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotSelfCall.selector);
        crossChainPortal.setChainPortals(chainSelectors, portals);
        vm.startPrank(address(crossChainPortal));
        crossChainPortal.setChainPortals(chainSelectors, portals);
        assertEq(crossChainPortal.getPortal(chainSelectors[0]), rob);
        chainSelectors = new uint64[](2);
        vm.expectRevert(ChainPortal.ChainPortal__ArrayLengthMismatch.selector);
        crossChainPortal.setChainPortals(chainSelectors, portals);
        vm.stopPrank();
    }

    function testSetLanesOnlySelf() public {
        address[] memory senders = new address[](1);
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory targets = new address[](1);
        bool[] memory enableds = new bool[](1);
        senders[0] = bob;
        chainSelectors[0] = baseChainSelector;
        targets[0] = alice;
        enableds[0] = true;
        assertFalse(crossChainPortal.isAuthorizedLane(senders[0], chainSelectors[0], targets[0]));
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotSelfCall.selector);
        crossChainPortal.setLanes(senders, chainSelectors, targets, enableds);
        vm.startPrank(address(crossChainPortal));
        crossChainPortal.setLanes(senders, chainSelectors, targets, enableds);
        assertTrue(crossChainPortal.isAuthorizedLane(senders[0], chainSelectors[0], targets[0]));
        senders = new address[](2);
        vm.expectRevert(ChainPortal.ChainPortal__ArrayLengthMismatch.selector);
        crossChainPortal.setLanes(senders, chainSelectors, targets, enableds);
        vm.stopPrank();
    }

    function testCcipReceive() public {
        ChainPortal.CrossChainAction memory action =
            ChainPortal.CrossChainAction(governor, new address[](0), new uint256[](0), new string[](0), new bytes[](0));
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage(
            bytes32(uint256(0x01)), baseChainSelector, abi.encode(baseChainPortal), abi.encode(action), tokenAmounts
        );
        Client.Any2EVMMessage memory message2 = Client.Any2EVMMessage(
            bytes32(uint256(0x02)), baseChainSelector, abi.encode(bob), abi.encode(action), tokenAmounts
        );
        assertEq(crossChainPortal.getPortal(baseChainSelector), address(baseChainPortal));
        vm.prank(rob);
        vm.expectRevert(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, rob));
        crossChainPortal.ccipReceive(message);
        vm.startPrank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.expectRevert(ChainPortal.ChainPortal__InvalidPortal.selector);
        crossChainPortal.ccipReceive(message2);
        vm.stopPrank();
    }

    function testTeleport() public {
        vm.expectRevert(ChainPortal.ChainPortal__ZeroTargets.selector);
        crossChainPortal.teleport(
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
        address[] memory senders = new address[](1);
        address[] memory targets = new address[](1);
        bool[] memory enableds = new bool[](1);
        chainSelectors[0] = baseChainSelector;
        senders[0] = alice;
        targets[0] = bob;
        enableds[0] = true;
        vm.expectRevert(ChainPortal.ChainPortal__LaneNotAvailable.selector);
        crossChainPortal.teleport(
            baseChainSelector,
            gasLimit,
            targets,
            new uint256[](1),
            new string[](1),
            new bytes[](1),
            new address[](0),
            new uint256[](0)
        );
        vm.prank(address(crossChainPortal));
        crossChainPortal.setLanes(senders, chainSelectors, targets, enableds);
        assertEq(crossChainPortal.getPortal(baseChainSelector), address(baseChainPortal));
        vm.startPrank(alice);
        crossChainPortal.teleport(
            baseChainSelector,
            gasLimit,
            targets,
            new uint256[](1),
            new string[](1),
            new bytes[](1),
            new address[](0),
            new uint256[](0)
        );
        vm.stopPrank();
    }

    function testAbortAction() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            governor,
            address(baseChainPortal),
            baseChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.expectRevert(Guardable.Guardable__NotGuardian.selector);
        crossChainPortal.abortAction(0);
        vm.prank(guardian);
        crossChainPortal.abortAction(0);
        uint256 allowanceBob = linkToken.allowance(address(crossChainPortal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(ChainPortal.ChainPortal__NoActionQueued.selector);
        crossChainPortal.performUpkeep(new bytes(0));
    }

    function testExecuteActionSetPendingGovernorRevertIfNotCrossChainGovernor() public {
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(baseChainPortal),
            baseChainSelector,
            address(crossChainPortal),
            0,
            "setPendingGovernor(address,uint64)",
            abi.encode(bob, baseChainSelector)
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotFromBaseChainGovernor.selector);
        crossChainPortal.performUpkeep(new bytes(0));
    }

    function testExecuteActionSetPendingGovernorRevertIfZeroChainSelector() public {
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            governor,
            address(baseChainPortal),
            baseChainSelector,
            address(crossChainPortal),
            0,
            "setPendingGovernor(address,uint64)",
            abi.encode(bob, 0)
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(CrossChainGovernable.CrossChainGovernable__ZeroChainId.selector);
        crossChainPortal.performUpkeep(new bytes(0));
    }

    function testExecuteActionSetPendingGovernor() public {
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            governor,
            address(baseChainPortal),
            baseChainSelector,
            address(crossChainPortal),
            0,
            "setPendingGovernor(address,uint64)",
            abi.encode(bob, baseChainSelector)
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.warp(block.timestamp + executionDelay + 1);
        crossChainPortal.performUpkeep(new bytes(0));
        assertEq(crossChainPortal.getPendingGovernor(), bob);
        assertEq(crossChainPortal.getPendingGovernorChainSelector(), baseChainSelector);
    }

    function testExecuteActionGovernanceTransfer() public {
        assertTrue(crossChainPortal.getPendingGovernor() == address(0));
        vm.expectRevert(CrossChainGovernable.CrossChainGovernable__ZeroAddress.selector);
        crossChainPortal.transferGovernance();
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            governor,
            address(baseChainPortal),
            baseChainSelector,
            address(crossChainPortal),
            0,
            "setPendingGovernor(address,uint64)",
            abi.encode(bob, baseChainSelector)
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.warp(block.timestamp + executionDelay + 1);
        crossChainPortal.performUpkeep(new bytes(0));
        vm.expectRevert(CrossChainGovernable.CrossChainGovernable__TooEarly.selector);
        crossChainPortal.transferGovernance();
        vm.warp(block.timestamp + 3 days + 1);
        crossChainPortal.transferGovernance();
    }

    function testExecuteActionSetExecutionDelayRevertIfNotCrossChainGovernor() public {
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(baseChainPortal),
            baseChainSelector,
            address(crossChainPortal),
            0,
            "setExecutionDelay(uint64)",
            abi.encode(uint64(1000))
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotFromBaseChainGovernor.selector);
        crossChainPortal.performUpkeep(new bytes(0));
    }

    function testExecuteActionSetLanesRevertIfNotCrossChainGovernor() public {
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(baseChainPortal),
            baseChainSelector,
            address(crossChainPortal),
            0,
            "setLanes(address[],uint64[],address[],bool[])",
            abi.encode(new address[](0), new uint64[](0), new address[](0), new bool[](0))
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotFromBaseChainGovernor.selector);
        crossChainPortal.performUpkeep(new bytes(0));
    }

    function testExecuteActionSetChainPortalsRevertIfNotCrossChainGovernor() public {
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(baseChainPortal),
            baseChainSelector,
            address(crossChainPortal),
            0,
            "setChainPortals(uint64[],address[])",
            abi.encode(new uint64[](0), new address[](0))
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotFromBaseChainGovernor.selector);
        crossChainPortal.performUpkeep(new bytes(0));
    }

    function testExecuteActionSetGuardiansRevertIfNotCrossChainGovernor() public {
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(baseChainPortal),
            baseChainSelector,
            address(crossChainPortal),
            0,
            "setExecutionDelay(uint64)",
            abi.encode(3601)
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotFromBaseChainGovernor.selector);
        crossChainPortal.performUpkeep(new bytes(0));
    }

    function testExecuteActionSetIntervalGuardianGoneRogueRevertIfNotCrossChainGovernor() public {
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(baseChainPortal),
            baseChainSelector,
            address(crossChainPortal),
            0,
            "setIntervalGuardianGoneRogue(uint32)",
            abi.encode(3601)
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotFromBaseChainGovernor.selector);
        crossChainPortal.performUpkeep(new bytes(0));
    }

    function testExecuteActionSetIntervalCommunicationLostRevertIfNotCrossChainGovernor() public {
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(baseChainPortal),
            baseChainSelector,
            address(crossChainPortal),
            0,
            "setIntervalCommunicationLost(uint32)",
            abi.encode(3601)
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotFromBaseChainGovernor.selector);
        crossChainPortal.performUpkeep(new bytes(0));
    }

    function testGuardianGoneRogue() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            governor,
            address(baseChainPortal),
            baseChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.prank(guardian);
        vm.warp(block.timestamp + executionDelay + 1);
        crossChainPortal.performUpkeep(new bytes(0));
        vm.warp(block.timestamp + crossChainPortal.getIntervalGuardianGoneRogue() + 1);
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.prank(guardian);
        vm.expectRevert(CrossChainPortal.CrossChainPortal__GuardianGoneRogue.selector);
        crossChainPortal.abortAction(1);
    }

    function testEmergencyConnectionLost() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            governor,
            address(baseChainPortal),
            baseChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.prank(guardian);
        vm.expectRevert(CrossChainGovernable.CrossChainGovernable__CommunicationNotLost.selector);
        crossChainPortal.emergencyCommunicationLost(message);
        vm.warp(block.timestamp + executionDelay + 1 + crossChainPortal.getIntervalCommunicationLost() + 1);
        vm.prank(guardian);
        crossChainPortal.emergencyCommunicationLost(message);
    }
}
