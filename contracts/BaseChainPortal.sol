//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {Guardable} from "flashliquidity-acs/contracts/Guardable.sol";
import {ChainPortal, Client, DataTypes} from "./ChainPortal.sol";

/**
 * @title BaseChainPortal
 * @author Oddcod3 (@oddcod3)
 *
 * @dev Main portal deployed on the base chain where the FlashLiquidity governor is deployed.
 *
 * @notice This contract is used to communicate with other CrossChainPortals.
 * @notice The FlashLiquidity governor can use this contract to govern CrossChainPortals.
 * @notice The FlashLiquidity governor can use this contract to govern cross-chain contracts indirectly (cross-chain contracts must be governed by CrossChainPortal).
 */
contract BaseChainPortal is Governable, Guardable, ChainPortal {
    error BaseChainPortal__SelfCallNotAuthorized();

    constructor(address governor, address guardian, address ccipRouter, address linkToken, uint64 executionDelay)
        Governable(governor)
        Guardable(guardian)
        ChainPortal(ccipRouter, linkToken, executionDelay)
    {
        s_isGuardian[governor] = true;
    }

    /// @inheritdoc Guardable
    function setGuardians(address[] calldata guardians, bool[] calldata enableds) external override onlyGovernor {
        _setGuardians(guardians, enableds);
    }

    /// @inheritdoc ChainPortal
    function abortAction(uint64 actionId) external override onlyGuardian {
        _abortAction(actionId);
    }

    /// @inheritdoc ChainPortal
    function setExecutionDelay(uint64 executionDelay) external override onlyGovernor {
        _setExecutionDelay(executionDelay);
    }

    /// @inheritdoc ChainPortal
    function setChainPortals(uint64[] calldata destChainSelectors, address[] calldata portals)
        external
        override
        onlyGovernor
    {
        _setChainPortals(destChainSelectors, portals);
    }

    /// @inheritdoc ChainPortal
    function setLanes(
        address[] calldata senders,
        uint64[] calldata destChainSelectors,
        address[] calldata receivers,
        bool[] calldata enableds
    ) external override onlyGovernor {
        _setLanes(senders, destChainSelectors, receivers, enableds);
    }

    /**
     * @notice This function is used by the Chainlink CCIP router to deliver a message.
     * @notice If the execution delay is 0, this function immediately executes the action included in the received message.
     * @param message The Any2EVMMessage struct received from CCIP, containing a cross-chain action to be executed.
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
