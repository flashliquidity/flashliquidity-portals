// SPDX-License-Identifier: GPL-3.0-only

import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

pragma solidity ^0.8.0;

contract CcipRouterMock {
    using SafeERC20 for IERC20;

    address public immutable s_linkToken;
    uint64 public s_chainSelector;
    mapping(uint64 chainSelector => bool isSupported) public s_isSupportedChain;
    event MessageDelivered(address indexed src, address indexed dest, uint64 destChainId);

    constructor(address linkToken, uint64 chainSelector, uint64[] memory supportedChainIds) {
        s_linkToken = linkToken;
        s_chainSelector = chainSelector;
        for(uint256 i; i < supportedChainIds.length;++i) {
            s_isSupportedChain[supportedChainIds[i]] = true;
        }
    }

    function setChainSelector(uint64 chainSelector) public {
        s_chainSelector = chainSelector;
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
            Client.Any2EVMMessage(messageId, s_chainSelector, abi.encode(msg.sender), message.data, message.tokenAmounts);
        for(uint256 i; i < message.tokenAmounts.length; ++i) {
            Client.EVMTokenAmount memory tokenAmount = message.tokenAmounts[i];
            IERC20(tokenAmount.token).safeTransferFrom(msg.sender, abi.decode(message.receiver, (address)), tokenAmount.amount);
        }
        address receiver = abi.decode(message.receiver, (address));
        IAny2EVMMessageReceiver(receiver).ccipReceive(messageOut);
        emit MessageDelivered(msg.sender, receiver, destinationChainSelector);
    }

    function isChainSupported(uint64 chainSelector) external view returns (bool) {
        return s_isSupportedChain[chainSelector];
    }
}
