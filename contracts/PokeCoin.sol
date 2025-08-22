// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract PokeCoin is ERC20, ERC20Burnable, ERC20Permit, Pausable, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_SUPPLY = 500000 * 1e18;

    error CapExceeded();
    error ZeroAddress();
    error NotThisToken();

    constructor(address initialOwner, uint256 initialSupply)
        ERC20("PokeCoin", "POKE")
        ERC20Permit("PokeCoin")
        Ownable(initialOwner)
    {
        if (initialOwner == address(0)) revert ZeroAddress();
        if (initialSupply > MAX_SUPPLY) revert CapExceeded();

        if (initialSupply > 0) {
            _mint(initialOwner, initialSupply);
        }
    }

    function mint(address to, uint256 amount) external onlyOwner {
        if (totalSupply() + amount > MAX_SUPPLY) revert CapExceeded();
        _mint(to, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(this)) revert NotThisToken();
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20)
    {
        if (paused()) revert("Pausable: paused");
        super._update(from, to, value);
    }


}
