// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {CrossChainPortal} from "../../../contracts/CrossChainPortal.sol";
import {BaseChainPortal} from "../../../contracts/BaseChainPortal.sol";
import {ChainPortal, DataTypes} from "../../../contracts/ChainPortal.sol";
import {CrossChainGovernable} from "flashliquidity-acs/contracts/CrossChainGovernable.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {CrossChainGovernorExecutor} from "../../../contracts/CrossChainGovernorExecutor.sol";
import {Guardable} from "flashliquidity-acs/contracts/Guardable.sol";
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
            intervalCommunicationLost
        );
        address[] memory portals = new address[](1);
        uint64[] memory chainSelectors = new uint64[](1);
        portals[0] = address(crossChainPortal);
        chainSelectors[0] = crossChainSelector;
        vm.prank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
    }

    function test__CCP_SetExecutionDelayOnlyGovernorExecutor() public {
        (,, uint64 currentExecutionDelay) = crossChainPortal.getActionQueueState();
        assertEq(currentExecutionDelay, executionDelay);
        uint64 newExecutionDelay = 30;
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotGovernorExecutor.selector);
        crossChainPortal.setExecutionDelay(newExecutionDelay);
        vm.prank(crossChainPortal.getGovernorExecutorAddr());
        crossChainPortal.setExecutionDelay(newExecutionDelay);
        (,, currentExecutionDelay) = crossChainPortal.getActionQueueState();
        assertEq(currentExecutionDelay, newExecutionDelay);
    }

    function test__CCP_SetGuardiansOnlyGovernorExecutor() public {
        address[] memory targets = new address[](1);
        bool[] memory enableds = new bool[](1);
        targets[0] = guardian;
        enableds[0] = false;
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotGovernorExecutor.selector);
        crossChainPortal.setGuardians(targets, enableds);
        assertTrue(crossChainPortal.isGuardian(guardian));
        vm.prank(crossChainPortal.getGovernorExecutorAddr());
        crossChainPortal.setGuardians(targets, enableds);
        assertFalse(crossChainPortal.isGuardian(guardian));
    }

    function test__CCP_SetIntervalCommunicationLostOnlyGovernorExecutor() public {
        uint32 newInterval = 100;
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotGovernorExecutor.selector);
        crossChainPortal.setIntervalCommunicationLost(newInterval);
        assertFalse(crossChainPortal.getIntervalCommunicationLost() == newInterval);
        vm.prank(crossChainPortal.getGovernorExecutorAddr());
        crossChainPortal.setIntervalCommunicationLost(newInterval);
        assertTrue(crossChainPortal.getIntervalCommunicationLost() == newInterval);
    }

    function test__CCP_SetPortalsOnlyGovernorExecutor() public {
        assertEq(crossChainPortal.getPortal(baseChainSelector), address(baseChainPortal));
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = baseChainSelector;
        portals[0] = rob;
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotGovernorExecutor.selector);
        crossChainPortal.setChainPortals(chainSelectors, portals);
        vm.startPrank(crossChainPortal.getGovernorExecutorAddr());
        crossChainPortal.setChainPortals(chainSelectors, portals);
        assertEq(crossChainPortal.getPortal(chainSelectors[0]), rob);
        chainSelectors = new uint64[](2);
        vm.expectRevert(ChainPortal.ChainPortal__ArrayLengthMismatch.selector);
        crossChainPortal.setChainPortals(chainSelectors, portals);
        vm.stopPrank();
    }

    function test__CCP_SetLanesOnlyGovernorExecutor() public {
        address[] memory senders = new address[](1);
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory targets = new address[](1);
        bool[] memory enableds = new bool[](1);
        senders[0] = bob;
        chainSelectors[0] = baseChainSelector;
        targets[0] = alice;
        enableds[0] = true;
        assertFalse(crossChainPortal.isAuthorizedLane(senders[0], chainSelectors[0], targets[0]));
        vm.expectRevert(CrossChainPortal.CrossChainPortal__NotGovernorExecutor.selector);
        crossChainPortal.setLanes(senders, chainSelectors, targets, enableds);
        vm.startPrank(crossChainPortal.getGovernorExecutorAddr());
        crossChainPortal.setLanes(senders, chainSelectors, targets, enableds);
        assertTrue(crossChainPortal.isAuthorizedLane(senders[0], chainSelectors[0], targets[0]));
        senders = new address[](2);
        vm.expectRevert(ChainPortal.ChainPortal__ArrayLengthMismatch.selector);
        crossChainPortal.setLanes(senders, chainSelectors, targets, enableds);
        vm.stopPrank();
    }

    function test__CCP_CcipReceive() public {
        DataTypes.CrossChainAction memory action =
            DataTypes.CrossChainAction(bob, new address[](0), new uint256[](0), new string[](0), new bytes[](0));
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

    function test__CCP_CcipReceiveSenderIsCrossChainGovernor() public {
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
        assertTrue(linkToken.allowance(crossChainPortal.getGovernorExecutorAddr(), bob) == 0);
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        assertTrue(linkToken.allowance(crossChainPortal.getGovernorExecutorAddr(), bob) == approveAmountBob);
    }

    function test__CCP_AbortAction() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
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

    function test__CCP_ExecuteActionSetPendingGovernor() public {
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            governor,
            address(baseChainPortal),
            baseChainSelector,
            address(crossChainPortal),
            0,
            "setPendingGovernor(address,uint64)",
            abi.encode(bob, crossChainSelector)
        );
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        assertTrue(crossChainPortal.getPendingGovernor() == bob);
        assertTrue(crossChainPortal.getPendingGovernorChainSelector() == crossChainSelector);
    }

    function test__CCP_ExecuteActionGovernanceTransfer() public {
        assertTrue(crossChainPortal.getPendingGovernor() == address(0));
        vm.expectRevert(Guardable.Guardable__NotGuardian.selector);
        crossChainPortal.transferGovernance();
        vm.expectRevert(CrossChainGovernable.CrossChainGovernable__ZeroAddress.selector);
        vm.prank(guardian);
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
        vm.expectRevert(CrossChainGovernable.CrossChainGovernable__TooEarly.selector);
        vm.prank(guardian);
        crossChainPortal.transferGovernance();
        vm.warp(block.timestamp + 3 days + 1);
        vm.prank(guardian);
        crossChainPortal.transferGovernance();
    }

    function test__CCP_EmergencyConnectionLost() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(baseChainPortal),
            baseChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        DataTypes.CrossChainAction memory action = abi.decode(message.data, (DataTypes.CrossChainAction));
        vm.prank(address(ccipRouter));
        crossChainPortal.ccipReceive(message);
        vm.prank(guardian);
        vm.expectRevert(CrossChainPortal.CrossChainPortal__CommunicationNotLost.selector);
        crossChainPortal.emergencyCommunicationLost(action);
        vm.warp(block.timestamp + executionDelay + 1 + crossChainPortal.getIntervalCommunicationLost() + 1);
        vm.prank(guardian);
        crossChainPortal.emergencyCommunicationLost(action);
    }

    function test__CCP_GovernorExecutorOnlyCrossChainPortal() public {
        CrossChainGovernorExecutor governorExecutor =
            CrossChainGovernorExecutor(crossChainPortal.getGovernorExecutorAddr());
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(baseChainPortal),
            baseChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, 1000)
        );
        vm.expectRevert(CrossChainGovernorExecutor.CrossChainGovernorExecutor__NotCrossChainPortal.selector);
        governorExecutor.executeAction(abi.decode(message.data, (DataTypes.CrossChainAction)));
        vm.prank(address(crossChainPortal));
        governorExecutor.executeAction(abi.decode(message.data, (DataTypes.CrossChainAction)));
    }

    function test__CCP_GovernorExecutorRevertOnActionExecution() public {
        CrossChainGovernorExecutor governorExecutor =
            CrossChainGovernorExecutor(crossChainPortal.getGovernorExecutorAddr());
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(baseChainPortal),
            baseChainSelector,
            address(linkToken),
            0,
            "",
            abi.encodeWithSignature("based(address,uint256)", bob, 1000)
        );
        vm.prank(address(crossChainPortal));
        vm.expectRevert(CrossChainGovernorExecutor.CrossChainGovernorExecutor__ActionExecutionFailed.selector);
        governorExecutor.executeAction(abi.decode(message.data, (DataTypes.CrossChainAction)));
    }
}
