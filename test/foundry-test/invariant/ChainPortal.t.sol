// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {GovernorPortal} from "../../../contracts/GovernorPortal.sol";
import {CrossChainGovernorPortal} from "../../../contracts/CrossChainGovernorPortal.sol";
import {ChainPortal, Portal} from "../../../contracts/ChainPortal.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {Guardable} from "flashliquidity-acs/contracts/Guardable.sol";
import {CcipRouterMock} from "../../mocks/CcipRouterMock.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

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
    }

    // coverage skip workaround
    function test() public {}

    function invariant__LastActionIdIsAlwaysGreaterOrEqualNextActionId() public {
        (uint64 nextActionId, uint64 lastActionId,,) = governorPortal.getPortalState();
        assertTrue(lastActionId >= nextActionId);
    }

    function invariant__ExpectedActionState() public {
        (uint64 nextActionId, uint64 lastActionId,,) = governorPortal.getPortalState();
        (, uint8 lastActionState) = governorPortal.getActionSetInfoById(lastActionId);
        (, uint8 nextActionState) = governorPortal.getActionSetInfoById(nextActionId);
        if (lastActionId == 0 || lastActionId == nextActionId) {
            assertTrue(nextActionState == 0);
        } else if (lastActionId == nextActionId) {
            assertTrue(nextActionState == 1 || nextActionState == 4);
        }
        assertTrue(lastActionState == 0);
    }
}
