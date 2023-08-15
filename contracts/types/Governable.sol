//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IGovernable} from "../interfaces/IGovernable.sol";

/**
 * @title Governable
 * @notice A 2-step governable contract with a delay between setting the pending governor and transferring governance.
 */
contract Governable is IGovernable {
    error Governable__ZeroAddress();
    error Governable__NotAuthorized();
    error Governable__TooEarly(uint64 timestampReady);

    address private s_governor;
    address private s_pendingGovernor;
    uint64 private s_govTransferReqTimestamp;
    uint32 public constant TRANSFER_GOVERNANCE_DELAY = 3 days;

    event GovernanceTrasferred(address indexed oldGovernor, address indexed newGovernor);
    event PendingGovernorChanged(address indexed pendingGovernor);

    modifier onlyGovernor() {
        _revertIfNotGovernor();
        _;
    }

    constructor(address governor) {
        s_governor = governor;
        emit GovernanceTrasferred(address(0), governor);
    }

    function setPendingGovernor(address pendingGovernor) external onlyGovernor {
        if (pendingGovernor == address(0)) {
            revert Governable__ZeroAddress();
        }
        s_pendingGovernor = pendingGovernor;
        s_govTransferReqTimestamp = uint64(block.timestamp);
        emit PendingGovernorChanged(pendingGovernor);
    }

    function transferGovernance() external {
        address newGovernor = s_pendingGovernor;
        address oldGovernor = s_governor;
        uint64 govTransferReqTimestamp = s_govTransferReqTimestamp;
        if (newGovernor == address(0)) {
            revert Governable__ZeroAddress();
        }
        if (msg.sender != oldGovernor && msg.sender != newGovernor) {
            revert Governable__NotAuthorized();
        }
        if (block.timestamp - govTransferReqTimestamp < TRANSFER_GOVERNANCE_DELAY) {
            revert Governable__TooEarly(govTransferReqTimestamp + TRANSFER_GOVERNANCE_DELAY);
        }
        s_pendingGovernor = address(0);
        s_governor = newGovernor;
        emit GovernanceTrasferred(oldGovernor, newGovernor);
    }

    function _revertIfNotGovernor() internal view {
        if (msg.sender != s_governor) {
            revert Governable__NotAuthorized();
        }
    }

    function _getGovernor() internal view returns (address) {
        return s_governor;
    }

    function _getPendingGovernor() internal view returns (address) {
        return s_pendingGovernor;
    }

    function _getGovTransferReqTimestamp() internal view returns (uint64) {
        return s_govTransferReqTimestamp;
    }

    function getGovernor() external view returns (address) {
        return _getGovernor();
    }

    function getPendingGovernor() external view returns (address) {
        return _getPendingGovernor();
    }

    function getGovTransferReqTimestamp() external view returns (uint64) {
        return _getGovTransferReqTimestamp();
    }
}
