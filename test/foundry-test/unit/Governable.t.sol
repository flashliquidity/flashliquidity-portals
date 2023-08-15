// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Governable} from "../../../contracts/types/Governable.sol";

contract GovernableTest is Test {
    Governable public governable;
    address public governor = makeAddr("governor");
    address public bob = makeAddr("bob");
    address public alice = makeAddr("alice");

    uint64 private constant TRANSFER_GOVERNANCE_DELAY = 3 days;

    function setUp() public {
        vm.prank(governor);
        vm.warp(1696969691);
        governable = new Governable(governor);
    }

    function testSetPendingGovernor() public {
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        governable.setPendingGovernor(bob);
        assertEq(governable.getPendingGovernor(), address(0));
        assertEq(governable.getGovTransferReqTimestamp(), uint64(0));
        vm.prank(governor);
        governable.setPendingGovernor(bob);
        assertEq(governable.getPendingGovernor(), bob);
        assertEq(governable.getGovTransferReqTimestamp(), 1696969691);
    }

    function testGovernorTransferGovernance() public {
        vm.startPrank(governor);
        vm.expectRevert(Governable.Governable__ZeroAddress.selector);
        governable.transferGovernance();
        governable.setPendingGovernor(bob);
        vm.stopPrank();
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        governable.transferGovernance();
        vm.prank(governor);
        vm.expectRevert(
            abi.encodeWithSelector(
                Governable.Governable__TooEarly.selector, block.timestamp + TRANSFER_GOVERNANCE_DELAY
            )
        );
        governable.transferGovernance();
        vm.warp(block.timestamp + TRANSFER_GOVERNANCE_DELAY + 1);
        vm.prank(bob);
        governable.transferGovernance();
        assertEq(governable.getGovernor(), bob);
    }

    function testPendingGovernorTransferGovernance() public {
        vm.prank(governor);
        governable.setPendingGovernor(bob);
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        governable.transferGovernance();
        vm.warp(block.timestamp + TRANSFER_GOVERNANCE_DELAY + 1);
        vm.prank(governor);
        governable.transferGovernance();
        assertEq(governable.getGovernor(), bob);
    }
}
