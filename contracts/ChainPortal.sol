//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IChainPortal} from "./interfaces/IChainPortal.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Portal} from "./libraries/Portal.sol";

/**
 * @title ChainPortal
 * @author Oddcod3 (@oddcod3)
 * @dev Abstract contract implementing core functionalities for a chain portal, including action set execution, token bridging, and multi-hop routing.
 */
abstract contract ChainPortal is IChainPortal, CCIPReceiver, AutomationCompatibleInterface, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///////////////////////
    // Errors            //
    ///////////////////////

    error ChainPortal__ActionSetNotExecutable();
    error ChainPortal__ActionSetExecutionFailed();
    error ChainPortal__ActionSetNotPending(uint64 actionId);
    error ChainPortal__NotPortalController();
    error ChainPortal__UnauthorizedAbort();
    error ChainPortal__UnauthorizedActionsOrigin();
    error ChainPortal__NoActionSetQueued();
    error ChainPortal__ZeroTargets();
    error ChainPortal__ZeroAddressTarget();
    error ChainPortal__InvalidPortal();
    error ChainPortal__InvalidChain(uint64 chainSelector);
    error ChainPortal__InvalidActionSetId(uint64 actionId);
    error ChainPortal__InconsistentParamsLength();
    error ChainPortal__UnsupportedRoute(uint64 chainSelector);

    ///////////////////////
    // State Variables   //
    ///////////////////////

    Portal.State internal s_portalState;
    uint64 private immutable i_chainSelector;
    address private immutable i_linkToken;
    bytes private s_routingCcipExtraArgs;

    /// @dev Mapping to action set from action id.
    mapping(uint64 actionSetId => Portal.ActionSet actionSet) internal s_actionSets;
    /// @dev Mapping to action set state from action id.
    mapping(uint64 actionSetId => Portal.ActionSetInfo actionSetInfo) internal s_actionInfos;
    /// @dev Mapping to route from destination chain selector.
    mapping(uint64 destChainSelector => Portal.Route route) internal s_routes;
    /// @dev Mapping of authorized origins to decide if an inbound action set should be queued or discarded.
    mapping(address actionOrigin => mapping(uint64 srcChainSelector => bool isAuthorized)) private
        s_authorizedActionOrigins;

    ///////////////////////
    // Events            //
    ///////////////////////

    event ExecutionDelayChanged(uint64 executionDelay);
    event ActionSetSent(bytes32 messageId);
    event ActionSetExecuted(uint256 actionId);
    event ActionSetForwarded(bytes32 inboundMessageId, bytes32 outboundMessageId);
    event ActionSetRejected(bytes32 messageId);
    event ActionSetReceived(uint256 actionId, bytes32 messageId);
    event ActionSetAborted(uint256 actionId);
    event RoutesChanged(uint64[] chainSelectors, uint64[] routeChainSelectors, address[] routePortals);
    event RoutingExtraArgsChanged(bytes extraArgs);
    event ActionOriginsChanged(address[] origins, uint64[] chainSelectors, bool[] authorizeds);

    ///////////////////////
    // Modifiers         //
    ///////////////////////

    modifier onlyPortalController() {
        _revertIfNotController();
        _;
    }

    modifier onlyAuthorizedActionAbort() {
        _revertIfUnauthorizedToAbort();
        _;
    }

    ////////////////////////
    // Functions          //
    ////////////////////////

    constructor(address ccipRouter, address linkToken, uint64 chainSelector, uint32 executionDelay)
        CCIPReceiver(ccipRouter)
    {
        i_chainSelector = chainSelector;
        i_linkToken = linkToken;
        _setExecutionDelay(executionDelay);
        IERC20(linkToken).approve(ccipRouter, type(uint256).max);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////

    receive() external payable {}

    /// @inheritdoc IChainPortal
    function abortAction(uint64 actionId) external onlyAuthorizedActionAbort {
        Portal.State memory portalState = s_portalState;
        if (actionId < portalState.nextActionId || actionId >= portalState.lastActionId) {
            revert ChainPortal__InvalidActionSetId(actionId);
        }
        Portal.ActionSetInfo storage actionInfo = s_actionInfos[actionId];
        if (actionInfo.actionState != Portal.ActionState.PENDING) {
            revert ChainPortal__ActionSetNotPending(actionId);
        }
        actionInfo.actionState = Portal.ActionState.ABORTED;
        emit ActionSetAborted(actionId);
    }

    /// @inheritdoc IChainPortal
    function setExecutionDelay(uint32 executionDelay) external onlyPortalController {
        _setExecutionDelay(executionDelay);
    }

    /// @inheritdoc IChainPortal
    function setRoutingCcipExtraArgs(bytes memory routingCcipExtraArgs) external onlyPortalController {
        s_routingCcipExtraArgs = routingCcipExtraArgs;
        emit RoutingExtraArgsChanged(routingCcipExtraArgs);
    }

    /// @inheritdoc IChainPortal
    function setRoutes(
        uint64[] memory destChainSelectors,
        uint64[] memory routeChainSelectors,
        address[] memory routePortals
    ) external onlyPortalController {
        uint256 destChainSelectorsLength = destChainSelectors.length;
        if (destChainSelectorsLength != routeChainSelectors.length || destChainSelectorsLength != routePortals.length) {
            revert ChainPortal__InconsistentParamsLength();
        }
        address routePortal;
        uint64 routeChainSelector;
        for (uint256 i; i < destChainSelectorsLength;) {
            routePortal = routePortals[i];
            routeChainSelector = routeChainSelectors[i];
            if (routePortal != address(0) && !IRouterClient(i_ccipRouter).isChainSupported(routeChainSelector)) {
                revert ChainPortal__UnsupportedRoute(routeChainSelector);
            }
            s_routes[destChainSelectors[i]] = Portal.Route({portal: routePortal, chainSelector: routeChainSelector});
            unchecked {
                ++i;
            }
        }
        emit RoutesChanged(destChainSelectors, routeChainSelectors, routePortals);
    }

    /// @inheritdoc IChainPortal
    function setActionsOrigins(
        address[] calldata origins,
        uint64[] calldata srcChainSelectors,
        bool[] calldata authorizeds
    ) external onlyPortalController {
        uint256 originsLength = origins.length;
        if (originsLength != srcChainSelectors.length || originsLength != authorizeds.length) {
            revert ChainPortal__InconsistentParamsLength();
        }
        for (uint256 i; i < originsLength;) {
            s_authorizedActionOrigins[origins[i]][srcChainSelectors[i]] = authorizeds[i];
            unchecked {
                ++i;
            }
        }
        emit ActionOriginsChanged(origins, srcChainSelectors, authorizeds);
    }

    /// @inheritdoc IChainPortal
    function transferTokens(address to, address[] memory tokens, uint256[] memory amounts)
        external
        onlyPortalController
    {
        uint256 tokensLen = tokens.length;
        if (tokensLen != amounts.length) revert ChainPortal__InconsistentParamsLength();
        for (uint256 i; i < tokensLen;) {
            IERC20(tokens[i]).safeTransfer(to, amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IChainPortal
    function teleport(
        uint64 destChainSelector,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory ccipExtraArgs
    ) external onlyPortalController {
        uint256 targetsLen = targets.length;
        if (
            targetsLen != values.length || targetsLen != signatures.length || targetsLen != calldatas.length
                || tokens.length != amounts.length
        ) {
            revert ChainPortal__InconsistentParamsLength();
        }
        Portal.Route memory route = s_routes[destChainSelector];
        if (route.portal == address(0) || route.chainSelector == 0) revert ChainPortal__InvalidChain(destChainSelector);
        Portal.ActionSetHeader memory actionSetHeader = Portal.ActionSetHeader({
            sender: msg.sender,
            srcChainSelector: i_chainSelector,
            destChainSelector: destChainSelector,
            ccipExtraArgs: ccipExtraArgs
        });
        Portal.ActionSet memory actionSet =
            Portal.ActionSet({targets: targets, values: values, signatures: signatures, calldatas: calldatas});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(route.portal),
            data: abi.encode(actionSetHeader, actionSet),
            tokenAmounts: _handleBridgeTokens(tokens, amounts),
            extraArgs: route.chainSelector == destChainSelector ? ccipExtraArgs : s_routingCcipExtraArgs,
            feeToken: i_linkToken
        });
        bytes32 messageId = IRouterClient(i_ccipRouter).ccipSend(route.chainSelector, message);
        emit ActionSetSent(messageId);
    }

    /// @inheritdoc IChainPortal
    function executePendingAction() external payable nonReentrant {
        _executeNextPendingActionQueued();
    }

    /**
     * @notice Chainlink Automation
     * @inheritdoc AutomationCompatibleInterface
     */
    function performUpkeep(bytes calldata) external override nonReentrant {
        _executeNextPendingActionQueued();
    }

    ////////////////////////
    // Internal Functions //
    ////////////////////////

    /**
     * @dev This function is used by Chainlink CCIP router to deliver a message.
     * @dev If the destination of the action set is not this chain it will be forwarded to the next portal in the route if any.
     * @param message The Any2EVMMessage struct received from CCIP, containing an action set to be executed or routed to another portals.
     */
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        Portal.Route memory routeIn = s_routes[message.sourceChainSelector];
        if (routeIn.portal == address(0)) revert ChainPortal__InvalidChain(message.sourceChainSelector);
        if (routeIn.portal != abi.decode(message.sender, (address))) revert ChainPortal__InvalidPortal();
        (Portal.ActionSetHeader memory actionSetHeader, Portal.ActionSet memory actionSet) =
            abi.decode(message.data, (Portal.ActionSetHeader, Portal.ActionSet));
        if (actionSetHeader.destChainSelector == i_chainSelector) {
            _handleInboundActionSet(
                actionSet, actionSetHeader.sender, actionSetHeader.srcChainSelector, message.messageId
            );
        } else {
            _forwardDataAndTokens(message, actionSetHeader.destChainSelector, actionSetHeader.ccipExtraArgs);
        }
    }

    /**
     * @dev This function is used to manage incoming action sets to be executed from this portal.
     * @dev If the origin of the action set is not authorized the action set will be discarded.
     * @dev If the origin of the action set is authorized and the targets are not empty the action set will be queued for execution.
     * @param actionSet Inbound action set.
     * @param sender Sender of the action set.
     * @param srcChainSelector Source chain selector of the action set.
     * @param messageId ID of the CCIP message where the action set has been stored.
     */
    function _handleInboundActionSet(
        Portal.ActionSet memory actionSet,
        address sender,
        uint64 srcChainSelector,
        bytes32 messageId
    ) internal {
        if (_isAuthorizedActionOrigin(sender, srcChainSelector)) {
            Portal.State storage portalState = s_portalState;
            portalState.lastMessageTimestamp = uint48(block.timestamp);
            uint64 lastActionId;
            if (actionSet.targets.length > 0) {
                lastActionId = portalState.lastActionId;
                portalState.lastActionId = lastActionId + 1;
                s_actionSets[lastActionId] = actionSet;
                s_actionInfos[lastActionId] = Portal.ActionSetInfo(
                    uint48(block.timestamp + portalState.executionDelay), Portal.ActionState.PENDING
                );
            }
            emit ActionSetReceived(lastActionId, messageId);
        } else {
            emit ActionSetRejected(messageId);
        }
    }

    /**
     * @dev Transfer tokens from msg.sender to this portal and approve tokens to CCIP router.
     * @param tokens Array of tokens to be bridged.
     * @param amounts Array of token amounts to be bridged.
     */
    function _handleBridgeTokens(address[] memory tokens, uint256[] memory amounts)
        private
        returns (Client.EVMTokenAmount[] memory)
    {
        uint256 tokensLength = tokens.length;
        uint256 tokenAmount;
        IERC20 token;
        Client.EVMTokenAmount[] memory tokensData = new Client.EVMTokenAmount[](tokensLength);
        bool notSelf = msg.sender != address(this);
        for (uint256 i; i < tokensLength;) {
            token = IERC20(tokens[i]);
            tokenAmount = amounts[i];
            tokensData[i].token = tokens[i];
            tokensData[i].amount = tokenAmount;
            if (notSelf) token.safeTransferFrom(msg.sender, address(this), tokenAmount);
            token.forceApprove(i_ccipRouter, tokenAmount);
            unchecked {
                ++i;
            }
        }
        return tokensData;
    }

    /**
     * @dev This function forward the inbound action set and tokens to the next portal in the route to reach the destination chain.
     * @param msg2Forward The CCIP message containing the action set and data of tokens to be forwarded.
     * @param destChainSelector The destination chain selector of the message to forward.
     * @param ccipExtraArgs Gas limit and strict sequencing extra args for CCIP.
     */
    function _forwardDataAndTokens(
        Client.Any2EVMMessage memory msg2Forward,
        uint64 destChainSelector,
        bytes memory ccipExtraArgs
    ) internal {
        s_portalState.lastMessageTimestamp = uint48(block.timestamp);
        Portal.Route memory route = s_routes[destChainSelector];
        if (route.chainSelector == 0 || route.portal == address(0)) {
            emit ActionSetRejected(msg2Forward.messageId);
        } else {
            Client.EVMTokenAmount memory tokenData;
            for (uint256 i; i < msg2Forward.destTokenAmounts.length;) {
                tokenData = msg2Forward.destTokenAmounts[i];
                IERC20(tokenData.token).forceApprove(i_ccipRouter, tokenData.amount);
                unchecked {
                    ++i;
                }
            }
            Client.EVM2AnyMessage memory forwardedMsg = Client.EVM2AnyMessage({
                receiver: abi.encode(route.portal),
                data: msg2Forward.data,
                tokenAmounts: msg2Forward.destTokenAmounts,
                extraArgs: route.chainSelector == destChainSelector ? ccipExtraArgs : s_routingCcipExtraArgs,
                feeToken: address(i_linkToken)
            });
            bytes32 messageId = IRouterClient(i_ccipRouter).ccipSend(route.chainSelector, forwardedMsg);
            emit ActionSetForwarded(msg2Forward.messageId, messageId);
        }
    }

    /// @param actionId ID of the action to be executed.
    function _executeActionSet(uint64 actionId) internal {
        bool success;
        bytes memory callData;
        bytes memory resultData;
        string memory signature;
        Portal.ActionSet memory actionSet = s_actionSets[actionId];
        uint256 actionsLength = actionSet.targets.length;
        for (uint256 i; i < actionsLength;) {
            signature = actionSet.signatures[i];
            if (bytes(signature).length > 0) {
                callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), actionSet.calldatas[i]);
            } else {
                callData = actionSet.calldatas[i];
            }
            (success, resultData) = actionSet.targets[i].call{value: actionSet.values[i]}(callData);
            if (!success) {
                if (resultData.length == 0) {
                    revert ChainPortal__ActionSetExecutionFailed();
                }
                assembly {
                    let size := mload(resultData)
                    revert(add(32, resultData), size)
                }
            }
            unchecked {
                ++i;
            }
        }
        emit ActionSetExecuted(actionId);
    }

    /**
     * @notice Executes the next pending action in the queue, skipping aborted actions.
     * @dev If there is no pending action queued, this function will revert.
     * @dev The first pending action in the queue that has not been aborted will be executed.
     */
    function _executeNextPendingActionQueued() internal {
        uint64 nextActionId = s_portalState.nextActionId;
        Portal.ActionSetInfo storage actionInfo = s_actionInfos[nextActionId];
        while (actionInfo.actionState == Portal.ActionState.ABORTED) {
            unchecked {
                ++nextActionId;
            }
            actionInfo = s_actionInfos[nextActionId];
        }
        if (actionInfo.actionState == Portal.ActionState.EMPTY) revert ChainPortal__NoActionSetQueued();
        if (block.timestamp < actionInfo.executionScheduledAt) revert ChainPortal__ActionSetNotExecutable();
        actionInfo.actionState = Portal.ActionState.EXECUTED;
        s_portalState.nextActionId = nextActionId + 1;
        _executeActionSet(nextActionId);
    }

    /// @param executionDelay The minimum execution delay between action set being queued and being executed.
    function _setExecutionDelay(uint32 executionDelay) internal {
        s_portalState.executionDelay = executionDelay;
        emit ExecutionDelayChanged(executionDelay);
    }

    /////////////////////////////
    // Internal View Functions //
    /////////////////////////////

    /// @dev This function must be overridden by the inheriting contracts.
    /// @notice Portal controller role grants access to privileged function to control the behaviour of the portal.
    function _isPortalController() internal view virtual returns (bool);

    /// @dev This function must be overridden by the inheriting contracts.
    /// @return Return true if msg.sender is authorized to abort the execution of action sets.
    function _isAuthorizedToAbort() internal view virtual returns (bool);

    /// @dev This function is used to decide if an action set should be queued or discarded based on the action set origin (sender of the action set).
    /// @return Return true if the action origin is authorized.
    function _isAuthorizedActionOrigin(address origin, uint64 srcChainSelector) internal view virtual returns (bool) {
        return s_authorizedActionOrigins[origin][srcChainSelector];
    }

    /////////////////////////////
    // Private View Functions  //
    /////////////////////////////

    /// @dev Revert if msg.sender is not the portal controller address.
    function _revertIfNotController() private view {
        if (!_isPortalController()) revert ChainPortal__NotPortalController();
    }

    /// @dev Revert if msg.sender is not authorized to abort action sets.
    function _revertIfUnauthorizedToAbort() private view {
        if (!_isAuthorizedToAbort()) revert ChainPortal__UnauthorizedAbort();
    }

    /////////////////////////////
    // External View Functions //
    /////////////////////////////

    /**
     * @inheritdoc AutomationCompatibleInterface
     * @dev This contract integrates with Chainlink Automation implementing the AutomationCompatibleInterface.
     */
    function checkUpkeep(bytes calldata) external view override returns (bool, bytes memory) {
        return (s_actionInfos[s_portalState.nextActionId].executionScheduledAt <= block.timestamp, new bytes(0));
    }

    /// @inheritdoc IChainPortal
    function getPortalState()
        external
        view
        returns (uint64 nextActionId, uint64 lastActionId, uint48 lastMessageTimestamp, uint32 executionDelay)
    {
        Portal.State memory portalState = s_portalState;
        nextActionId = portalState.nextActionId;
        lastActionId = portalState.lastActionId;
        lastMessageTimestamp = portalState.lastMessageTimestamp;
        executionDelay = portalState.executionDelay;
    }

    /// @inheritdoc IChainPortal
    function getActionSetById(uint64 actionId)
        external
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        )
    {
        Portal.ActionSet memory action = s_actionSets[actionId];
        targets = action.targets;
        values = action.values;
        signatures = action.signatures;
        calldatas = action.calldatas;
    }

    /// @inheritdoc IChainPortal
    function getActionSetInfoById(uint64 actionId)
        external
        view
        returns (uint48 executionScheduledAt, uint8 actionState)
    {
        Portal.ActionSetInfo memory actionInfo = s_actionInfos[actionId];
        executionScheduledAt = actionInfo.executionScheduledAt;
        actionState = uint8(actionInfo.actionState);
    }

    /// @inheritdoc IChainPortal
    function getRoute(uint64 destChainSelector) external view returns (uint64 routeChainSelector, address portal) {
        Portal.Route memory route = s_routes[destChainSelector];
        return (route.chainSelector, route.portal);
    }
}
