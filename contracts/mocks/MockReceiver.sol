// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../BridgeCore.sol";

contract MockReceiver{
    receive() external payable{
        revert("MockReceiver: revert");
    }

    function sendNativeToBridge(
        address bridge,
        address token
    ) external payable {
        BridgeCore(bridge).send{value: msg.value}(
            token,
            address(this),
            2,
            msg.value
        );
    }
}