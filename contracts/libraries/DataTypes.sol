//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library DataTypes {
    struct CrossChainAction {
        address sender;
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
    }

    struct ActionInfo {
        uint64 timestampQueued;
        uint64 sourceChainSelector;
        ActionState actionState;
    }

    struct ActionQueueState {
        uint64 nextActionId;
        uint64 lastActionId;
        uint64 executionDelay;
    }

    enum ActionState {
        EMPTY,
        PENDING,
        EXECUTED,
        ABORTED
    }
}
