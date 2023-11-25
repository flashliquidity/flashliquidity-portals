//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IChainPortal {
    /// @param actionId ID of the action to be aborted.
    function abortAction(uint64 actionId) external;

    /// @param executionDelay The minimum execution delay that actions must be subjected to between being queued and being executed.
    function setExecutionDelay(uint32 executionDelay) external;

    /// @param routingCcipExtraArgs The extra args for Chainlink CCIP to be used in multi-hop routing to forward a message to the next portal on the route
    function setRoutingCcipExtraArgs(bytes memory routingCcipExtraArgs) external;

    /**
     * @dev This function is used to manage actions origin authorization.
     * @dev Incoming action sets are queued for execution by the receiver portal only if the sender is an authorized origin, otherwise they are discarded
     * @param origins Array of addresses to authorize/unauthorize as valid action origins
     * @param srcChainSelectors Array of source chain selectors
     * @param authorizeds Array of boolean values for origin authorization
     * @notice The origin, srcChainSelectors and authorizeds arrays must have the same length.
     */
    function setActionsOrigins(
        address[] calldata origins,
        uint64[] calldata srcChainSelectors,
        bool[] calldata authorizeds
    ) external;

    /**
     * @param destChainSelectors Array of destination chain selectors.
     * @param routeChainSelectors Array of route chain selectors.
     * @param routePortals Array of portal addresses for route chain selectors.
     * @notice The chainSelectors and portals arrays must have the same length.
     */
    function setRoutes(
        uint64[] calldata destChainSelectors,
        uint64[] calldata routeChainSelectors,
        address[] calldata routePortals
    ) external;

    /**
     * @dev Sends a cross-chain action and/or bridges tokens to another portal on destination chain.
     * @param destChainSelector Chain selector of the destination chain
     * @param targets Array of target addresses to interact with
     * @param values Array of values of native destination token to send to target addresses
     * @param signatures Array of function signatures to be called for target addresses
     * @param calldatas Array of calldatas for low level calls to target addresses
     * @param tokens Array of tokens to be bridged to the destination chain
     * @param amounts Array of token amounts to be bridged to destination chain
     * @param ccipExtraArgs Gas limit for execution of the action on destination chain
     * @notice Tokens are bridged to the destination portal address
     * @notice Approvals of token amounts to this portal is required before calling this function
     */
    function teleport(
        uint64 destChainSelector,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory ccipExtraArgs
    ) external;

    /// @dev Execute the next mature pending action set in the queue if any (auto-skip aborted action set)
    function executePendingAction() external payable;

    /// @dev This function returns the action queue state.
    function getPortalState()
        external
        view
        returns (uint64 nextActionId, uint64 lastActionId, uint48 lastQueued, uint32 executionDelay);

    /// @dev This function returns action parameters given the ID of the action.
    function getActionSetById(uint64 actionId)
        external
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        );

    /// @dev This function return action info parameters given the id of the action
    function getActionSetInfoById(uint64 actionId)
        external
        view
        returns (uint48 executionScheduledAt, uint8 actionState);

    /**
     * @dev This function returns the route, if any, for a given destination chain selector.
     * @dev The route include the next portal address and the next chain selector to reach the destination chain.
     * @dev If the destination chain cannot be reached in one single hop the return values routeChainSelector and portal will be the next hop on the route to reach the destination chain.
     * @return routeChainSelector The route chain selector to reach the destination chain (if the destination chain can be reached in one hop this will be the destination chain selector)
     * @return portal The address of the portal corresponding to the given chain selector, or address(0) if not set.
     */
    function getRoute(uint64 destChainSelector) external view returns (uint64 routeChainSelector, address portal);
}
