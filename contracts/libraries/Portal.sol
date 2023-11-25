//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Portal {
    struct State {
        uint64 nextActionId;
        uint64 lastActionId;
        uint48 lastMessageTimestamp;
        uint32 executionDelay;
    }

    struct Route {
        uint64 chainSelector;
        address portal;
    }

    struct ActionSet {
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
    }

    struct ActionSetHeader {
        address sender;
        uint64 srcChainSelector;
        uint64 destChainSelector;
        bytes ccipExtraArgs;
    }

    struct ActionSetInfo {
        uint48 executionScheduledAt;
        ActionState actionState;
    }

    enum ActionState {
        EMPTY,
        PENDING,
        EXECUTED,
        ABORTED
    }
}
