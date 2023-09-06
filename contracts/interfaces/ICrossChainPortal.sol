//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IChainPortal} from "./IChainPortal.sol";

interface ICrossChainPortal is IChainPortal {
    
    function setIntervalCommunicationLost(uint32 intervalCommunicationLost) external;

    function setIntervalGuardianGoneRogue(uint32 intervalGuardianGoneRogue) external;

    function getGovernorExecutorAddr(address governorExecutor) external;
}
