//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IChainPortal {
    /**
     * @param actionId ID of the action to be aborted.
     */
    function abortAction(uint64 actionId) external;

    /**
     * @param executionDelay The minimum execution delay that actions must be subjected to between being queued and being executed.
     */
    function setExecutionDelay(uint64 executionDelay) external;

    /**
     * @param chainSelectors Array of chain selectors.
     * @param portals Array of portal addresses for every chain selector included in the chainSelectors array.
     * @notice The chainSelectors and portals arrays must have the same length.
     */
    function setChainPortals(uint64[] calldata chainSelectors, address[] calldata portals) external;

    /**
     * @param senders Array of sender addresses.
     * @param destChainSelectors Array of destination chain selectors.
     * @param targets Array of target addresses.
     * @param enableds Array of boolean values to enable/disable a lane for every: senders[i] -> destChainSelectors[i] -> targets[i].
     * @notice This function is used to enable/disable lanes between senders and targets on destination chains.
     * @notice This function revert if the senders, targets, destChainSelectors, and enableds arrays don't have the same length.
     */
    function setLanes(
        address[] calldata senders,
        uint64[] calldata destChainSelectors,
        address[] calldata targets,
        bool[] calldata enableds
    ) external;

    /**
     * @dev Sends a cross-chain action and/or bridges tokens to another portal on destination chain.
     * @param chainSelector Chain selector of the destination chain
     * @param gasLimit Gas limit for execution of the action on destination chain
     * @param targets Array of target addresses to interact with
     * @param values Array of values of native destination token to send to target addresses
     * @param signatures Array of function signatures to be called for target addresses
     * @param calldatas Array of calldatas for low level calls to target addresses
     * @param tokens Array of tokens to be bridged to the destination chain
     * @param amounts Array of token amounts to be bridged to destination chain
     * @notice Tokens are bridged to the destination portal address
     * @notice Approvals to this portal of token amounts to be bridged is required before calling this function
     */
    function teleport(
        uint64 chainSelector,
        uint64 gasLimit,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        address[] memory tokens,
        uint256[] memory amounts
    ) external;

    /**
     * @notice This function returns the action queue state.
     */
    function getActionQueueState()
        external
        view
        returns (uint64 nextActionId, uint64 lastActionId, uint64 executionDelay, uint64 lastTimePendingActionExecuted);

    /**
     * @notice This function returns action parameters given the ID of the action.
     */
    function getActionById(uint64 actionId)
        external
        view
        returns (
            address sender,
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        );

    /**
     * @notice This function return action info parameters given the id of the action
     */
    function getActionInfoById(uint64 actionId)
        external
        view
        returns (uint64 timestampQueued, uint64 fromChainSelector, uint8 actionState);

    /**
     * @param sender Sender address of the action.
     * @param destChainSelector Selector of the destination chain.
     * @param target Target address of the action on the destination chain.
     * @notice Check if it is possible to route actions from the sender to the target on the destination chain selected.
     */
    function isAuthorizedLane(address sender, uint64 destChainSelector, address target) external view returns (bool);

    /**
     * @notice This function returns the address of the portal given the chain selector or address(0) if the portal is not set.
     * @return portal The address of the portal corresponding to the given chain selector, or address(0) if not set.
     */
    function getPortal(uint64 chainSelector) external view returns (address portal);
}
