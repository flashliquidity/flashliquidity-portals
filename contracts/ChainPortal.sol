//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IChainPortal} from "./interfaces/IChainPortal.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DataTypes} from "./libraries/DataTypes.sol";

/**
 * @title ChainPortal
 * @author Oddcod3 (@oddcod3)
 *
 * @dev This abstract contract contains the core logic for a generic chain portal.
 * @dev The ChainPortal empowers cross-chain communication and token bridging between
 *      different portals deployed across multiple EVM chains.
 *
 * @notice Functionalities:
 * - send cross-chain actions to be executed by the receivier portal on the destination chain
 * - receive and execute cross-chain actions sent from other authorized portals deployed across different chains
 * - bridge allowed tokens to a receving portal on destination chain
 * - combine cross-chain actions and token bridging in a single message
 *
 * @dev This contract is the base class inherited from BaseChainPortal and CrossChainPortal.
 */
abstract contract ChainPortal is IChainPortal, CCIPReceiver, AutomationCompatibleInterface {
    using SafeERC20 for IERC20;

    ///////////////////////
    // Errors            //
    ///////////////////////

    error ChainPortal__ActionNotExecutable();
    error ChainPortal__ActionExecutionFailed();
    error ChainPortal__ActionNotPending(uint128 actionId);
    error ChainPortal__NoActionQueued();
    error ChainPortal__ZeroTargets();
    error ChainPortal__ZeroAddressTarget();
    error ChainPortal__LaneNotAvailable();
    error ChainPortal__InvalidPortal();
    error ChainPortal__InvalidChain(uint64 chainSelector);
    error ChainPortal__InvalidActionId(uint128 actionId);
    error ChainPortal__ArrayLengthMismatch();

    ///////////////////////
    // State Variables   //
    ///////////////////////

    DataTypes.ActionQueueState internal s_queueState;
    LinkTokenInterface private immutable i_linkToken;

    /// @dev Mapping to action struct from action id
    mapping(uint64 actionId => DataTypes.CrossChainAction action) internal s_actions;
    /// @dev Mapping to action state from action id
    mapping(uint64 actionId => DataTypes.ActionInfo actionInfo) internal s_actionInfos;
    /// @dev Mapping to destination portal address from destination chain selector
    mapping(uint64 destChainSelector => address portal) internal s_chainPortals;
    /// @dev Nested mapping of authorized communication lanes (sender -> chainSelector -> target)
    mapping(address sender => mapping(uint64 destChainSelector => mapping(address target => bool))) private s_lanes;

    ///////////////////////
    // Events            //
    ///////////////////////

    event ExecutionDelayChanged(uint64 indexed executionDelay);
    event OutboundActionSent(bytes32 indexed messageId);
    event InboundActionQueued(uint256 indexed actionId, bytes32 indexed messageId);
    event ActionAborted(uint256 indexed actionId);
    event QueuedActionExecuted(uint256 indexed actionId);
    event InboundActionExecuted(bytes32 indexed messageId);
    event LanesChanged(
        address[] indexed senders, address[] indexed targets, uint64[] indexed chainSelectors, bool[] isEnabled
    );
    event ChainPortalsChanged(uint64[] indexed chainSelectors, address[] indexed portals);

    ///////////////////////
    // Modifiers         //
    ///////////////////////

    modifier onlyAuthorizedLanes(uint64 chainSelector, address[] memory targets) {
        _revertIfUnauthorizedLanes(chainSelector, targets);
        _;
    }

    ////////////////////////
    // Functions          //
    ////////////////////////

    constructor(address ccipRouter, address linkToken, uint64 executionDelay) CCIPReceiver(ccipRouter) {
        i_linkToken = LinkTokenInterface(linkToken);
        i_linkToken.approve(ccipRouter, type(uint256).max);
        _setExecutionDelay(executionDelay);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////

    /// @inheritdoc IChainPortal
    function abortAction(uint64 actionId) external virtual;

    /// @inheritdoc IChainPortal
    function setExecutionDelay(uint64 executionDelay) external virtual;

    /// @inheritdoc IChainPortal
    function setChainPortals(uint64[] calldata chainSelectors, address[] calldata portals) external virtual;

    /// @inheritdoc IChainPortal
    function setLanes(
        address[] calldata senders,
        uint64[] calldata destChainSelectors,
        address[] calldata targets,
        bool[] calldata enableds
    ) external virtual;

    /// @inheritdoc IChainPortal
    function teleport(
        uint64 chainSelector,
        uint64 gasLimit,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        address[] memory tokens,
        uint256[] memory amounts
    ) external onlyAuthorizedLanes(chainSelector, targets) {
        if (
            targets.length != values.length || values.length != signatures.length
                || signatures.length != calldatas.length || tokens.length != amounts.length
        ) revert ChainPortal__ArrayLengthMismatch();
        if (targets.length == 0) {
            revert ChainPortal__ZeroTargets();
        }
        address chainPortal = s_chainPortals[chainSelector];
        if (chainPortal == address(0)) {
            revert ChainPortal__InvalidChain(chainSelector);
        }
        Client.EVM2AnyMessage memory message = _buildMessage(
            gasLimit, chainPortal, targets, values, signatures, calldatas, _handleTokensBridging(tokens, amounts)
        );
        bytes32 _messageId = IRouterClient(i_router).ccipSend(chainSelector, message);
        emit OutboundActionSent(_messageId);
    }

    /**
     * @notice Chainlink Automation
     * @inheritdoc AutomationCompatibleInterface
     */
    function performUpkeep(bytes calldata) external override {
        _executeNextPendingActionQueued();
    }

    ////////////////////////
    // Internal Functions //
    ////////////////////////

    /**
     * @notice Executes the next pending action in the queue, skipping aborted actions.
     * @dev If there is no pending action queued, the function will revert.
     * @dev The first pending action that is not aborted will be executed.
     */
    function _executeNextPendingActionQueued() internal {
        uint64 nextActionId = s_queueState.nextActionId;
        DataTypes.ActionInfo storage actionInfo = s_actionInfos[nextActionId];
        while (actionInfo.actionState == DataTypes.ActionState.ABORTED) {
            unchecked {
                ++nextActionId;
            }
            actionInfo = s_actionInfos[nextActionId];
        }
        if (actionInfo.actionState == DataTypes.ActionState.EMPTY) {
            revert ChainPortal__NoActionQueued();
        }
        if (!_isActionExecutable(actionInfo.timestampQueued)) {
            revert ChainPortal__ActionNotExecutable();
        }
        actionInfo.actionState = DataTypes.ActionState.EXECUTED;
        s_queueState.nextActionId = nextActionId + 1;
        _executeAction(s_actions[nextActionId]);
        emit QueuedActionExecuted(nextActionId);
    }

    /**
     * @param action The CrossChainAction struct of the action to be executed
     */
    function _executeAction(DataTypes.CrossChainAction memory action) internal {
        bool success;
        bytes memory callData;
        bytes memory resultData;
        uint256 targetsLength = action.targets.length;
        for (uint256 i; i < targetsLength;) {
            if (bytes(action.signatures[i]).length == 0) {
                callData = action.calldatas[i];
            } else {
                callData = abi.encodePacked(bytes4(keccak256(bytes(action.signatures[i]))), action.calldatas[i]);
            }
            (success, resultData) = action.targets[i].call{value: action.values[i]}(callData);
            if (!success) {
                if (resultData.length == 0) {
                    revert ChainPortal__ActionExecutionFailed();
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
    }

    /**
     * @param actionId The ID of the action to be aborted
     */
    function _abortAction(uint64 actionId) internal {
        DataTypes.ActionQueueState memory queueState = s_queueState;
        if (actionId < queueState.nextActionId || actionId >= queueState.lastActionId) {
            revert ChainPortal__InvalidActionId(actionId);
        }
        DataTypes.ActionInfo storage actionInfo = s_actionInfos[actionId];
        if (actionInfo.actionState != DataTypes.ActionState.PENDING) {
            revert ChainPortal__ActionNotPending(actionId);
        }
        actionInfo.actionState = DataTypes.ActionState.ABORTED;
        emit ActionAborted(actionId);
    }

    /**
     * @param executionDelay The minimum execution delay that actions must be subjected to between being queued and being executed.
     */
    function _setExecutionDelay(uint64 executionDelay) internal {
        s_queueState.executionDelay = executionDelay;
        emit ExecutionDelayChanged(executionDelay);
    }

    /**
     * @param chainSelectors Array of chain selectors.
     * @param portals Array of portal addresses corresponding to each chain selector in the chainSelectors array.
     * @notice The chainSelectors and portals arrays must have the same length.
     */
    function _setChainPortals(uint64[] calldata chainSelectors, address[] calldata portals) internal {
        uint256 chainSelectorsLength = chainSelectors.length;
        if (chainSelectorsLength != portals.length) {
            revert ChainPortal__ArrayLengthMismatch();
        }
        for (uint256 i; i < chainSelectorsLength;) {
            if (!IRouterClient(i_router).isChainSupported(chainSelectors[i])) {
                revert IRouterClient.UnsupportedDestinationChain(chainSelectors[i]);
            }
            s_chainPortals[chainSelectors[i]] = portals[i];
            unchecked {
                ++i;
            }
        }
        emit ChainPortalsChanged(chainSelectors, portals);
    }

    /**
     * @param senders Array of sender addresses.
     * @param destChainSelectors Array of destination chain selectors.
     * @param targets Array of target addresses.
     * @param enableds Array of boolean values to enable/disable a lane for every: senders[i] -> destChainSelectors[i] -> targets[i].
     * @notice This function is used to enable/disable lanes between senders and targets on destination chains.
     * @notice The senders, targets, destChainSelectors, and enableds arrays must have the same length.
     */
    function _setLanes(
        address[] calldata senders,
        uint64[] calldata destChainSelectors,
        address[] calldata targets,
        bool[] calldata enableds
    ) internal {
        uint256 sendersLength = senders.length;
        if (
            senders.length != targets.length || targets.length != destChainSelectors.length
                || destChainSelectors.length != enableds.length
        ) {
            revert ChainPortal__ArrayLengthMismatch();
        }
        for (uint256 i; i < sendersLength;) {
            if (targets[i] == address(0)) {
                revert ChainPortal__ZeroAddressTarget();
            }
            s_lanes[senders[i]][destChainSelectors[i]][targets[i]] = enableds[i];
            unchecked {
                ++i;
            }
        }
        emit LanesChanged(senders, targets, destChainSelectors, enableds);
    }

    ////////////////////////
    // Private Functions  //
    ////////////////////////

    /**
     * @param tokens Array of tokens to be bridged.
     * @param amounts Array of token amounts to be bridged.
     * @notice Transfer tokens from msg.sender to this portal and approve tokens to CCIP router.
     */
    function _handleTokensBridging(address[] memory tokens, uint256[] memory amounts)
        private
        returns (Client.EVMTokenAmount[] memory)
    {
        uint256 tokensLength = tokens.length;
        uint256 tokenAmount;
        IERC20 token;
        Client.EVMTokenAmount[] memory tokensData = new Client.EVMTokenAmount[](tokensLength);
        for (uint256 i; i < tokensLength;) {
            token = IERC20(tokens[i]);
            tokenAmount = amounts[i];
            tokensData[i].token = tokens[i];
            tokensData[i].amount = tokenAmount;
            token.safeTransferFrom(msg.sender, address(this), tokenAmount);
            token.approve(i_router, tokenAmount);
            unchecked {
                ++i;
            }
        }
        return tokensData;
    }

    /////////////////////////////
    // Private View Functions  //
    /////////////////////////////

    /**
     * @param gasLimit Gas limit used for the execution of the action on the destination chain.
     * @param chainPortal Address of the portal on the destination chain.
     * @param targets Array of target addresses to interact with.
     * @param values Array of values of the native destination token to send to the target addresses.
     * @param signatures Array of function signatures to be called at the target addresses.
     * @param calldatas Array of encoded function call parameters.
     * @param tokensData Array of token addresses and amounts to be bridged to the destination chain.
     * @notice This function builds and returns the EVM2AnyMessage struct from the given parameters.
     */
    function _buildMessage(
        uint64 gasLimit,
        address chainPortal,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        Client.EVMTokenAmount[] memory tokensData
    ) private view returns (Client.EVM2AnyMessage memory) {
        DataTypes.CrossChainAction memory action = DataTypes.CrossChainAction({
            sender: msg.sender,
            targets: targets,
            values: values,
            signatures: signatures,
            calldatas: calldatas
        });
        return Client.EVM2AnyMessage({
            receiver: abi.encode(chainPortal),
            data: abi.encode(action),
            tokenAmounts: tokensData,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: gasLimit, strict: false})),
            feeToken: address(i_linkToken)
        });
    }

    /**
     * @param timestampQueued Timestamp of when the action has been queued.
     */
    function _isActionExecutable(uint64 timestampQueued) private view returns (bool) {
        return timestampQueued != 0 && block.timestamp - timestampQueued > s_queueState.executionDelay;
    }

    /**
     * @param chainSelector Selector of the destination chain.
     * @param targets Array of target addresses.
     * @notice Revert if the action includes targets on destination chains with no lanes available from this portal for msg.sender.
     * @notice Save gas by skipping storage loads if equal targets are in sequence.
     */
    function _revertIfUnauthorizedLanes(uint64 chainSelector, address[] memory targets) private view {
        address tempTarget;
        for (uint256 i; i < targets.length; i++) {
            if (targets[i] != tempTarget) {
                tempTarget = targets[i];
                if (!s_lanes[msg.sender][chainSelector][tempTarget]) {
                    revert ChainPortal__LaneNotAvailable();
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /////////////////////////////
    // External View Functions //
    /////////////////////////////

    /// @inheritdoc IChainPortal
    function getActionQueueState()
        external
        view
        returns (uint64 nextActionId, uint64 lastActionId, uint64 executionDelay)
    {
        DataTypes.ActionQueueState memory queueState = s_queueState;
        nextActionId = queueState.nextActionId;
        lastActionId = queueState.lastActionId;
        executionDelay = queueState.executionDelay;
    }

    /// @inheritdoc IChainPortal
    function getActionById(uint64 actionId)
        external
        view
        returns (
            address sender,
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        )
    {
        DataTypes.CrossChainAction memory action = s_actions[actionId];
        sender = action.sender;
        targets = action.targets;
        values = action.values;
        signatures = action.signatures;
        calldatas = action.calldatas;
    }

    /// @inheritdoc IChainPortal
    function getActionInfoById(uint64 actionId)
        external
        view
        returns (uint64 timestampQueued, uint64 fromChainSelector, uint8 actionState)
    {
        DataTypes.ActionInfo memory actionInfo = s_actionInfos[actionId];
        timestampQueued = actionInfo.timestampQueued;
        fromChainSelector = actionInfo.sourceChainSelector;
        actionState = uint8(actionInfo.actionState);
    }

    /// @inheritdoc IChainPortal
    function isAuthorizedLane(address sender, uint64 destChainSelector, address target) external view returns (bool) {
        return s_lanes[sender][destChainSelector][target];
    }

    /// @inheritdoc IChainPortal
    function getPortal(uint64 chainSelector) external view returns (address portal) {
        return s_chainPortals[chainSelector];
    }

    /**
     * @inheritdoc AutomationCompatibleInterface
     * @dev This contract integrates with Chainlink Automation implementing the AutomationCompatibleInterface.
     */
    function checkUpkeep(bytes calldata) external view override returns (bool, bytes memory) {
        return (_isActionExecutable(s_actionInfos[s_queueState.nextActionId].timestampQueued), new bytes(0));
    }
}
