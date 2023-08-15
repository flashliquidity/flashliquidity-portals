//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGovernable {
    /**
     * @param pendingGovernor The new pending governor address.
     * @notice A call to transfer governance is required to promote the new pending governor to the governor role.
     */
    function setPendingGovernor(address pendingGovernor) external;

    /**
     * @notice Promote the pending governor to the governor role.
     */
    function transferGovernance() external;

    function getGovernor() external view returns (address);

    function getPendingGovernor() external view returns (address);

    function getGovTransferReqTimestamp() external view returns (uint64);
}
