// SPDX-License-Identifier: GPL-3.0-only

import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

pragma solidity ^0.8.0;

contract CcipRouterMock {
    address immutable s_linkToken;
    uint64 s_chainId;

    event MessageDelivered(address indexed src, address indexed dest, uint64 destChainId);

    constructor(address linkToken, uint64 chainId) {
        s_linkToken = linkToken;
        s_chainId = chainId;
    }

    // coverage skip workaround
    function test() public {}

    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        returns (bytes32 messageId)
    {
        messageId = bytes32(uint256(0x1));
        Client.Any2EVMMessage memory messageOut =
            Client.Any2EVMMessage(messageId, s_chainId, abi.encode(msg.sender), message.data, message.tokenAmounts);
        address receiver = abi.decode(message.receiver, (address));
        IAny2EVMMessageReceiver(receiver).ccipReceive(messageOut);
        emit MessageDelivered(msg.sender, receiver, destinationChainSelector);
    }

    function isChainSupported(uint64) external pure returns (bool) {
        return true;
    }
}
