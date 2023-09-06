//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CrossChainGovernable} from "flashliquidity-acs/contracts/CrossChainGovernable.sol";
import {Guardable} from "flashliquidity-acs/contracts/Guardable.sol";
import {ChainPortal, DataTypes} from "./ChainPortal.sol";
import {CrossChainGovernorExecutor} from "./CrossChainGovernorExecutor.sol";

/**
 * @title CrossChainPortal
 * @author Oddcod3 (@oddcod3)
 *
 * @dev Cross-chain portals are not deployed on the same chain where FlashLiquidity governor is deployed.
 *
 * @notice This contract is used to communicate with other CrossChainPortals and with BaseChainPortal.
 * @notice Cross-chain governor can use the BaseChainPortal to govern cross-chain contracts indirectly with this portal.
 * @notice Action sent by cross-chain governor are executed by the CrossChainGovernorExecutor associated with this portal.
 * @notice CrossChainGovernorExecutor should be granted the role of owner/governor for the contracts that require cross-chain governance
 */
contract CrossChainPortal is CrossChainGovernable, Guardable, ChainPortal {
    error CrossChainPortal__NotGovernorExecutor();
    error CrossChainPortal__CommunicationNotLost();
    error CrossChainPortal__TargetIsGovernorExecutor();

    CrossChainGovernorExecutor private immutable s_governorExecutor;
    uint32 private s_intervalCommunicationLost;

    modifier onlyGovernorExecutor() {
        _revertIfNotGovernorExecutor();
        _;
    }

    event IntervalGuardianGoneRogueChanged(uint32 indexed newInterval);
    event IntervalCommunicationLostChanged(uint32 indexed newInterval);
    event InboundGovernorActionExecuted(bytes32 indexed messageId);

    constructor(
        address governor,
        address guardian,
        address baseChainPortal,
        address ccipRouter,
        address linkToken,
        uint64 governorChainSelector,
        uint64 executionDelay,
        uint32 intervalCommunicationLost
    )
        CrossChainGovernable(governor, governorChainSelector)
        Guardable(guardian)
        ChainPortal(ccipRouter, linkToken, executionDelay)
    {
        s_intervalCommunicationLost = intervalCommunicationLost;
        s_chainPortals[governorChainSelector] = baseChainPortal;
        s_governorExecutor = new CrossChainGovernorExecutor();
        s_isGuardian[address(s_governorExecutor)] = true;
    }

    /**
     * @param intervalCommunicationLost The time interval between the last timestamp an action has been received and the timestamp of the current block.
     * @notice When this interval is exceeded the communication with the base portal is considered lost
     */
    function setIntervalCommunicationLost(uint32 intervalCommunicationLost) external onlyGovernorExecutor {
        s_intervalCommunicationLost = intervalCommunicationLost;
        emit CommunicationLostIntervalChanged(intervalCommunicationLost);
    }

    /// @inheritdoc CrossChainGovernable
    function setPendingGovernor(address pendingGovernor, uint64 pendingGovernorChainSelector)
        external
        override
        onlyGovernorExecutor
    {
        _setPendingGovernor(pendingGovernor, pendingGovernorChainSelector);
    }

    /// @inheritdoc CrossChainGovernable
    function transferGovernance() external override onlyGuardian {
        _transferGovernance();
    }

    /// @inheritdoc Guardable
    function setGuardians(address[] calldata guardians, bool[] calldata enableds)
        external
        override
        onlyGovernorExecutor
    {
        _setGuardians(guardians, enableds);
    }

    /// @inheritdoc ChainPortal
    function abortAction(uint64 actionId) external override onlyGuardian {
        _abortAction(actionId);
    }

    /// @inheritdoc ChainPortal
    function setExecutionDelay(uint64 executionDelay) external override onlyGovernorExecutor {
        _setExecutionDelay(executionDelay);
    }

    /// @inheritdoc ChainPortal
    function setChainPortals(uint64[] calldata chainSelectors, address[] calldata portals)
        external
        override
        onlyGovernorExecutor
    {
        _setChainPortals(chainSelectors, portals);
    }

    /// @inheritdoc ChainPortal
    function setLanes(
        address[] calldata senders,
        uint64[] calldata destChainSelectors,
        address[] calldata receivers,
        bool[] calldata enableds
    ) external override onlyGovernorExecutor {
        _setLanes(senders, destChainSelectors, receivers, enableds);
    }

    /**
     * @param action The CrossChainAction struct containing the emergency action to be executed by the cross chain governor executor.
     * @dev This function can be executed by guardians only if communication with the base portal has been lost.
     */
    function emergencyCommunicationLost(DataTypes.CrossChainAction memory action) external onlyGuardian {
        if (!_isCommunicationLost()) {
            revert CrossChainPortal__CommunicationNotLost();
        }
        s_governorExecutor.executeAction(action);
    }

    /**
     * @param message The Any2EVMMessage struct received from CCIP, containing a cross-chain action to be executed.
     * @dev This function is used by Chainlink CCIP router to deliver a message.
     * @dev If the action inbound is sent by cross-chain governor then is forwarded to the governor-executor and immediately executed.
     * @dev Otherwise if execution delay is greater than 0 the action is queued till maturity for execution.
     * @dev Instead if the execution delay is 0, this function immediately executes the received action.
     */
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        address sourceChainPortal = s_chainPortals[message.sourceChainSelector];
        if (sourceChainPortal == address(0)) {
            revert ChainPortal__InvalidChain(message.sourceChainSelector);
        }
        if (sourceChainPortal != abi.decode(message.sender, (address))) {
            revert ChainPortal__InvalidPortal();
        }
        DataTypes.ActionQueueState storage queueState = s_queueState;
        DataTypes.CrossChainAction memory action = abi.decode(message.data, (DataTypes.CrossChainAction));
        _revertIfTargetGovernorExecutor(action.targets);
        if (action.sender == _getGovernor() && message.sourceChainSelector == _getGovernorChainSelector()) {
            s_governorExecutor.executeAction(action);
            emit InboundGovernorActionExecuted(message.messageId);
        } else {
            if (queueState.executionDelay > 0) {
                uint64 lastActionId = queueState.lastActionId;
                queueState.lastActionId = lastActionId + 1;
                s_actions[lastActionId] = action;
                s_actionInfos[lastActionId] = DataTypes.ActionInfo(
                    uint64(block.timestamp), message.sourceChainSelector, DataTypes.ActionState.PENDING
                );
                emit InboundActionQueued(lastActionId, message.messageId);
            } else {
                _executeAction(action);
                emit InboundActionExecuted(message.messageId);
            }
        }
    }

    /**
     * @notice This function reverts if sender is not the governor-executor contract associated with this portal
     */
    function _revertIfNotGovernorExecutor() internal view {
        if (msg.sender != address(s_governorExecutor)) {
            revert CrossChainPortal__NotGovernorExecutor();
        }
    }

    /**
     * @notice This function reverts if governor-executor address is included in the targets array
     */
    function _revertIfTargetGovernorExecutor(address[] memory targets) internal view {
        address governorExecutor = address(s_governorExecutor);
        uint256 targetsLength = targets.length;
        for (uint256 i; i < targetsLength; ) {
            if (targets[i] == governorExecutor) {
                revert CrossChainPortal__TargetIsGovernorExecutor();
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @return True if communication with the base portal has been lost lost; otherwise, false.
     */
    function _isCommunicationLost() internal view returns (bool) {
        DataTypes.ActionQueueState memory queueState = s_queueState;
        DataTypes.ActionInfo memory actionInfo = s_actionInfos[queueState.lastActionId - 1];
        if (queueState.lastActionId == 0 || queueState.executionDelay == 0) return false;
        return block.timestamp - actionInfo.timestampQueued > s_intervalCommunicationLost;
    }

    /**
     * @return Return the inteval after which, if no message has been received, communication with base portal is considered lost
     */
    function getIntervalCommunicationLost() external view returns (uint32) {
        return s_intervalCommunicationLost;
    }

    /**
     * @return Return the governor-executor address associated with this cross-chain portal
     */
    function getGovernorExecutorAddr() external view returns (address) {
        return address(s_governorExecutor);
    }
}
