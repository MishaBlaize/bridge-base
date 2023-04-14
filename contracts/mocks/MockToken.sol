// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract MockToken is ERC20, AccessControl {
    uint8 internal _decimals;
    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Access is denied");
        _;
    }

    constructor(
        string memory name,
        string memory symbols,
        uint8 decimalsNumber
    ) ERC20(name, symbols) {
        _decimals = decimalsNumber;
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mints desired amount of tokens for the recipient
     * @param _receiver Receiver of the tokens.
     * @param _amount Amount (in wei - smallest decimals)
     */
    function mintFor(address _receiver, uint256 _amount) external onlyOwner {
        require(_receiver != address(0), "Zero address");
        require(_receiver != address(this), "Incorrect address");
        require(_amount > 0, "Incorrect amount");
        _mint(_receiver, _amount);
    }

    function mint(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Incorrect amount");
        _mint(_msgSender(), _amount);
    }
}
