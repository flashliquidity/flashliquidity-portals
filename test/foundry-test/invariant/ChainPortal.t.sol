// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BaseChainPortal} from "../../../contracts/BaseChainPortal.sol";
import {ChainPortal} from "../../../contracts/ChainPortal.sol";
import {Governable} from "../../../contracts/types/Governable.sol";
import {Guardable} from "../../../contracts/types/Guardable.sol";
import {CcipRouterMock} from "../../mocks/CcipRouterMock.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

contract ChainPortalTest is Test {
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
            uint64(block.chainid)
        );
        portal = new BaseChainPortal(
            governor,
            guardian,
            address(ccipRouter),
            address(linkToken),
            executionDelay
        );
        uint64[] memory chainSelectors = new uint64[](1);
        address[] memory portals = new address[](1);
        chainSelectors[0] = crossChainSelector;
        portals[0] = cc_portal;
        vm.prank(governor);
        portal.setChainPortals(chainSelectors, portals);
        Client.Any2EVMMessage memory message = buildMessageWithSingleAction(
            bob,
            cc_portal,
            crossChainSelector,
            address(linkToken),
            0,
            "approve(address,uint256)",
            abi.encode(bob, 100)
        );
        vm.prank(address(ccipRouter));
        portal.ccipReceive(message);
        targetSender(address(ccipRouter));
        targetSender(governor);
        targetContract(address(portal));
    }

    // coverage skip workaround
    function test() public {}

    function invariantLastActionIdIsAlwaysGreaterOrEqualNextActionId() public {
        (uint64 nextActionId, uint64 lastActionId,,) = portal.getActionQueueState();
        assertTrue(lastActionId >= nextActionId);
    }

    function invariantExpectedActionState() public {
        (uint64 nextActionId, uint64 lastActionId,,) = portal.getActionQueueState();
        (,, uint8 lastActionState) = portal.getActionInfoById(lastActionId);
        (,, uint8 nextActionState) = portal.getActionInfoById(nextActionId);
        if (lastActionId == 0 || lastActionId == nextActionId) {
            assertTrue(nextActionState == 0);
        } else if(lastActionId == nextActionId) {
            assertTrue(nextActionState == 1 || nextActionState == 4);
        }
        assertTrue(lastActionState == 0);
    }
}
