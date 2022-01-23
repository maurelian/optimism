// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract FakeL2StandardERC20 {

    address constant OVM_ETH = 0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000;

    // Burn will be called by the L2 Bridge to burn the tokens we are bridging to L1
    function burn(address from, uint256 amount) external {
        from; amount;
    }

    // The L2 Bridge contract will ask which L1 token this L2 token corresponds to.
    // Pretend it is ETH.
    function l1Token() external view returns (address) {
        return OVM_ETH;
    }

}
