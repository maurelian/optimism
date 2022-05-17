// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

contract Burner {
    constructor() payable {
        selfdestruct(payable(address(this)));
    }
}

library Burn {
    function eth(uint256 _amount) internal {
        new Burner{ value: _amount }();
    }

    function gas(uint256 _amount) internal {
        uint256 i = 0;
        uint256 initialGas = gasleft();
        while (initialGas - gasleft() < _amount) {
            ++i;
        }
    }
}
