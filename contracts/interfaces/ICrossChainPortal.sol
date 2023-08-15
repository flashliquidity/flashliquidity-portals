//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ICrossChainGovernable} from "./ICrossChainGovernable.sol";
import {IGuardable} from "./IGuardable.sol";
import {IChainPortal} from "./IChainPortal.sol";

interface ICrossChainPortal is ICrossChainGovernable, IGuardable, IChainPortal {}
