// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BaseChainPortal} from "../../../contracts/BaseChainPortal.sol";
import {CrossChainPortal} from "../../../contracts/CrossChainPortal.sol";
import {ChainPortal, DataTypes} from "../../../contracts/ChainPortal.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {Guardable} from "flashliquidity-acs/contracts/Guardable.sol";
import {CcipRouterMock} from "../../mocks/CcipRouterMock.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

contract BaseChainPortalTest is Test {
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
    uint32 public executionDelay = 6 hours;
    uint64 public gasLimit = 1e6;

    bytes ChainPortal__InvalidChain =
        abi.encodeWithSelector(ChainPortal.ChainPortal__InvalidChain.selector, crossChainSelector);

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
            7 days
        );
    }

    function test__BCP_SetExecutionDelay() public {
        (,, uint64 currentExecutionDelay) = baseChainPortal.getActionQueueState();
        assertEq(currentExecutionDelay, executionDelay);
        uint64 newExecutionDelay = 30;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        baseChainPortal.setExecutionDelay(newExecutionDelay);
        vm.prank(governor);
        baseChainPortal.setExecutionDelay(newExecutionDelay);
        (,, currentExecutionDelay) = baseChainPortal.getActionQueueState();
        assertEq(currentExecutionDelay, newExecutionDelay);
    }

    function test__BCP_SetGuardians() public {
        address[] memory targets = new address[](1);
        bool[] memory enableds = new bool[](1);
        targets[0] = guardian;
        enableds[0] = false;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        baseChainPortal.setGuardians(targets, enableds);
        vm.prank(guardian);
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        baseChainPortal.setGuardians(targets, enableds);
        assertTrue(baseChainPortal.isGuardian(guardian));
        vm.prank(governor);
        baseChainPortal.setGuardians(targets, enableds);
        assertFalse(baseChainPortal.isGuardian(guardian));
    }

    function test__BCP_SetPortals() public {
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = baseChainSelector;
        portals[0] = address(crossChainPortal);
        assertEq(baseChainPortal.getPortal(chainSelectors[0]), address(0));
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.prank(guardian);
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.startPrank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        assertEq(baseChainPortal.getPortal(chainSelectors[0]), address(crossChainPortal));
        chainSelectors = new uint64[](2);
        vm.expectRevert(ChainPortal.ChainPortal__ArrayLengthMismatch.selector);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.stopPrank();
    }

    function test__BCP_SetLanes() public {
        address[] memory senders = new address[](1);
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory targets = new address[](1);
        bool[] memory enableds = new bool[](1);
        senders[0] = bob;
        chainSelectors[0] = baseChainSelector;
        targets[0] = alice;
        enableds[0] = true;
        assertFalse(baseChainPortal.isAuthorizedLane(senders[0], chainSelectors[0], targets[0]));
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        baseChainPortal.setLanes(senders, chainSelectors, targets, enableds);
        vm.startPrank(governor);
        baseChainPortal.setLanes(senders, chainSelectors, targets, enableds);
        assertTrue(baseChainPortal.isAuthorizedLane(senders[0], chainSelectors[0], targets[0]));
        senders = new address[](2);
        vm.expectRevert(ChainPortal.ChainPortal__ArrayLengthMismatch.selector);
        baseChainPortal.setLanes(senders, chainSelectors, targets, enableds);
        vm.stopPrank();
    }

    function test__BCP_Teleport() public {
        vm.expectRevert(ChainPortal.ChainPortal__ZeroTargets.selector);
        baseChainPortal.teleport(
            crossChainSelector,
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
        chainSelectors[0] = crossChainSelector;
        portals[0] = address(crossChainPortal);
        senders[0] = alice;
        targets[0] = bob;
        enableds[0] = true;
        vm.prank(alice);
        vm.expectRevert(ChainPortal.ChainPortal__LaneNotAvailable.selector);
        baseChainPortal.teleport(
            crossChainSelector,
            gasLimit,
            targets,
            new uint256[](1),
            new string[](1),
            new bytes[](1),
            new address[](0),
            new uint256[](0)
        );
        vm.prank(governor);
        baseChainPortal.setLanes(senders, chainSelectors, targets, enableds);
        vm.prank(alice);
        vm.expectRevert(ChainPortal__InvalidChain);
        baseChainPortal.teleport(
            crossChainSelector,
            gasLimit,
            targets,
            new uint256[](1),
            new string[](1),
            new bytes[](1),
            new address[](0),
            new uint256[](0)
        );
        vm.prank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.prank(alice);
        baseChainPortal.teleport(
            crossChainSelector,
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
        vm.prank(alice);
        vm.expectRevert(ChainPortal.ChainPortal__ArrayLengthMismatch.selector);
        baseChainPortal.teleport(
            crossChainSelector,
            gasLimit,
            targetsWrongLength,
            new uint256[](1),
            new string[](1),
            new bytes[](1),
            new address[](0),
            new uint256[](0)
        );
    }

    function test__BCP_CcipReceive() public {
        DataTypes.CrossChainAction memory action =
            DataTypes.CrossChainAction(governor, new address[](0), new uint256[](0), new string[](0), new bytes[](0));
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage(
            bytes32(uint256(0x01)),
            crossChainSelector,
            abi.encode(address(crossChainPortal)),
            abi.encode(action),
            tokenAmounts
        );
        vm.prank(rob);
        vm.expectRevert(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, rob));
        baseChainPortal.ccipReceive(message);
        vm.prank(address(ccipRouter));
        vm.expectRevert(ChainPortal__InvalidChain);
        baseChainPortal.ccipReceive(message);
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = address(crossChainPortal);
        vm.prank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.prank(address(ccipRouter));
        baseChainPortal.ccipReceive(message);
    }

    function test__BCP_AbortAction() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(crossChainPortal),
            crossChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = address(crossChainPortal);
        vm.prank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.prank(address(ccipRouter));
        baseChainPortal.ccipReceive(message);
        vm.expectRevert(Guardable.Guardable__NotGuardian.selector);
        baseChainPortal.abortAction(0);
        vm.prank(guardian);
        baseChainPortal.abortAction(0);
        uint256 allowanceBob = linkToken.allowance(address(baseChainPortal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(ChainPortal.ChainPortal__NoActionQueued.selector);
        baseChainPortal.performUpkeep(new bytes(0));
    }

    function test__BCP_ExecuteActionSingleTarget() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(crossChainPortal),
            crossChainSelector,
            address(linkToken),
            0,
            "",
            abi.encodeWithSignature("approve(address,uint256)", bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = address(crossChainPortal);
        vm.prank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.prank(address(ccipRouter));
        baseChainPortal.ccipReceive(message);
        vm.expectRevert(ChainPortal.ChainPortal__ActionNotExecutable.selector);
        baseChainPortal.performUpkeep(new bytes(0));
        uint256 allowanceBob = linkToken.allowance(address(baseChainPortal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        baseChainPortal.performUpkeep(new bytes(0));
        allowanceBob = linkToken.allowance(address(baseChainPortal), bob);
        assertEq(allowanceBob, approveAmountBob);
    }

    function test__BCP_ExecuteActionMultipleTarget() public {
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
            bytes32(uint256(0x01)), crossChainSelector, abi.encode(crossChainPortal), abi.encode(action), tokenAmounts
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = address(crossChainPortal);
        vm.prank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.prank(address(ccipRouter));
        baseChainPortal.ccipReceive(message);
        vm.expectRevert(ChainPortal.ChainPortal__ActionNotExecutable.selector);
        baseChainPortal.performUpkeep(new bytes(0));
        uint256 allowanceBob = linkToken.allowance(address(baseChainPortal), bob);
        uint256 allowanceRob = linkToken.allowance(address(baseChainPortal), rob);
        assertEq(allowanceBob, 0);
        assertEq(allowanceRob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        baseChainPortal.performUpkeep(new bytes(0));
        allowanceBob = linkToken.allowance(address(baseChainPortal), bob);
        allowanceRob = linkToken.allowance(address(baseChainPortal), rob);
        assertEq(allowanceBob, approveAmountBob);
        assertEq(allowanceRob, approveAmountRob);
    }

    function test__BCP_RevertOnActionExecution() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(crossChainPortal),
            crossChainSelector,
            address(linkToken),
            0,
            "based(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = address(crossChainPortal);
        vm.prank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.prank(address(ccipRouter));
        baseChainPortal.ccipReceive(message);
        vm.expectRevert(ChainPortal.ChainPortal__ActionNotExecutable.selector);
        baseChainPortal.performUpkeep(new bytes(0));
        uint256 allowanceBob = linkToken.allowance(address(baseChainPortal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(ChainPortal.ChainPortal__ActionExecutionFailed.selector);
        baseChainPortal.performUpkeep(new bytes(0));
    }

    function test__BCP_SkipAbortedActionAndExecute() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(crossChainPortal),
            crossChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = address(crossChainPortal);
        vm.prank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.startPrank(address(ccipRouter));
        baseChainPortal.ccipReceive(message);
        baseChainPortal.ccipReceive(message);
        baseChainPortal.ccipReceive(message);
        vm.stopPrank();
        vm.startPrank(guardian);
        baseChainPortal.abortAction(0);
        baseChainPortal.abortAction(1);
        vm.stopPrank();
        uint256 allowanceBob = linkToken.allowance(address(baseChainPortal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        baseChainPortal.performUpkeep(new bytes(0));
        allowanceBob = linkToken.allowance(address(baseChainPortal), bob);
        assertEq(allowanceBob, approveAmountBob);
        vm.expectRevert(ChainPortal.ChainPortal__NoActionQueued.selector);
        baseChainPortal.performUpkeep(new bytes(0));
    }

    function test__BCP_ExecuteActionSkipAbortedAndRevertOnEmpty() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(crossChainPortal),
            crossChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = address(crossChainPortal);
        vm.prank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.startPrank(address(ccipRouter));
        baseChainPortal.ccipReceive(message);
        baseChainPortal.ccipReceive(message);
        baseChainPortal.ccipReceive(message);
        vm.stopPrank();
        vm.startPrank(guardian);
        baseChainPortal.abortAction(0);
        baseChainPortal.abortAction(1);
        baseChainPortal.abortAction(2);
        vm.stopPrank();
        uint256 allowanceBob = linkToken.allowance(address(baseChainPortal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        vm.expectRevert(ChainPortal.ChainPortal__NoActionQueued.selector);
        baseChainPortal.performUpkeep(new bytes(0));
    }

    function test__BCP_ExecuteActionSkipAbortedAndExecute() public {
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(crossChainPortal),
            crossChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = address(crossChainPortal);
        vm.prank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.startPrank(address(ccipRouter));
        baseChainPortal.ccipReceive(message);
        baseChainPortal.ccipReceive(message);
        baseChainPortal.ccipReceive(message);
        baseChainPortal.ccipReceive(message);
        vm.stopPrank();
        uint256 allowanceBob = linkToken.allowance(address(baseChainPortal), bob);
        assertEq(allowanceBob, 0);
        vm.warp(block.timestamp + executionDelay + 1);
        baseChainPortal.performUpkeep(new bytes(0));
        allowanceBob = linkToken.allowance(address(baseChainPortal), bob);
        assertEq(allowanceBob, approveAmountBob);
        vm.startPrank(guardian);
        baseChainPortal.abortAction(1);
        baseChainPortal.abortAction(2);
        vm.stopPrank();
        baseChainPortal.performUpkeep(new bytes(0));
        vm.expectRevert(ChainPortal.ChainPortal__NoActionQueued.selector);
        baseChainPortal.performUpkeep(new bytes(0));
    }

    function test__BCP_ZeroExecutionDelay() public {
        vm.prank(governor);
        baseChainPortal.setExecutionDelay(0);
        uint256 approveAmountBob = 1000;
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            address(crossChainPortal),
            crossChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, approveAmountBob)
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = address(crossChainPortal);
        vm.prank(governor);
        baseChainPortal.setChainPortals(chainSelectors, portals);
        vm.prank(address(ccipRouter));
        baseChainPortal.ccipReceive(message);
        uint256 allowanceBob = linkToken.allowance(address(baseChainPortal), bob);
        assertEq(allowanceBob, approveAmountBob);
    }
}
