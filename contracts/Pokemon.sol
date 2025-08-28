// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC1155/ERC1155.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/access/AccessControl.sol";

contract PokemonCollection is ERC1155, AccessControl {

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ---------- Supply caps ----------
    /// @dev Per-id maximum total supply
    mapping(uint256 => uint256) public maxSupply;

    /// @dev Per-id amount minted so far
    mapping(uint256 => uint256) public minted;

    // ---------- Events ----------
    event BaseURISet(string newURI);
    event MaxSupplySet(uint256 indexed id, uint256 newMax);
    event MaxSupplyBatchSet(uint256[] ids, uint256[] newMaxes);

    // ---------- Errors (gas-efficient) ----------
    error ZeroAddress();
    error LengthMismatch();
    error CapNotSet();               // cap must be set before minting
    error CapExceeded();             // would exceed maxSupply[id]
    error NewMaxBelowMinted();       // cannot reduce below already minted

    // ---------- Constructor ----------
    /**
     * @param baseURI          e.g., ipfs://<CID>/{id}.json
     * @param admin            address that will hold DEFAULT_ADMIN_ROLE
     */
    constructor(
        string memory baseURI,
        address admin
    ) ERC1155(baseURI) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // Assign MINTER_ROLE to admin by default; you can grant others later
        _grantRole(MINTER_ROLE, admin);
    }

    // ---------- Admin: URI Management ----------
    function setURI(string calldata newURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newURI);
        emit BaseURISet(newURI);
    }

    // ---------- Admin: Supply caps ----------
    /// @notice Set/raise the cap for a single id. Cannot lower below minted[id].
    function setMaxSupply(uint256 id, uint256 newMax)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newMax < minted[id]) revert NewMaxBelowMinted();
        maxSupply[id] = newMax;
        emit MaxSupplySet(id, newMax);
    }

    /// @notice Batch version for setting caps based on tiers (off-chain categorization)
    /// @dev Call this with arrays of IDs grouped by tier and their corresponding caps
    ///      Example: setMaxSupplyBatch([1,2,3], [4,4,4]) for Common tier
    ///               setMaxSupplyBatch([4,5], [3,3]) for Uncommon tier
    function setMaxSupplyBatch(uint256[] calldata ids, uint256[] calldata newMaxes)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (ids.length != newMaxes.length) revert LengthMismatch();
        for (uint256 i = 0; i < ids.length; i++) {
            if (newMaxes[i] < minted[ids[i]]) revert NewMaxBelowMinted();
            maxSupply[ids[i]] = newMaxes[i];
        }
        emit MaxSupplyBatchSet(ids, newMaxes);
    }

    // ---------- View Functions ----------
    /// @notice Get remaining mintable amount for a token
    /// @param id The token ID
    /// @return The remaining mintable amount
    function getRemainingMintable(uint256 id) public view returns (uint256) {
        uint256 max = maxSupply[id];
        if (max == 0) return 0;
        uint256 current = minted[id];
        return max > current ? max - current : 0;
    }

    /// @notice Get remaining mintable amounts for multiple tokens
    /// @param ids Array of token IDs
    /// @return remainings Array of remaining mintable amounts
    function getRemainingMintableBatch(uint256[] calldata ids) 
        public 
        view 
        returns (uint256[] memory remainings) 
    {
        remainings = new uint256[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            remainings[i] = getRemainingMintable(ids[i]);
        }
    }

    // ---------- Minting (role-gated, cap-checked) ----------
    /**
     * @notice Mint copies of a species (id) to `to`.
     *         Requires cap to be set and not exceeded.
     */
    function mint(address to, uint256 id, uint256 amount, bytes calldata data)
        external
        onlyRole(MINTER_ROLE)
    {
        uint256 cap = maxSupply[id];
        if (cap == 0) revert CapNotSet();
        uint256 afterMint = minted[id] + amount;
        if (afterMint > cap) revert CapExceeded();

        minted[id] = afterMint;
        _mint(to, id, amount, data);
    }

    /**
     * @notice Batch mint multiple ids/amounts to `to`.
     *         Requires each id cap to be set and not exceeded.
     * @dev Ideal for minting entire tier groups at once
     *      Example: mintBatch(treasury, [1,2,3], [4,4,4], 0x) for all Commons
     */
    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    )
        external
        onlyRole(MINTER_ROLE)
    {
        if (ids.length != amounts.length) revert LengthMismatch();

        // Check & update minted counts first (checks-effects-interactions)
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 cap = maxSupply[ids[i]];
            if (cap == 0) revert CapNotSet();
            uint256 afterMint = minted[ids[i]] + amounts[i];
            if (afterMint > cap) revert CapExceeded();
            minted[ids[i]] = afterMint;
        }

        _mintBatch(to, ids, amounts, data);
    }

    /**
     * @notice Convenience function to mint max supply for specific IDs
     * @dev Useful for minting all copies at once based on their set caps
     * @param to Address to mint to
     * @param ids Array of token IDs to mint max supply for
     * @param data Additional data
     */
    function mintMaxBatch(
        address to,
        uint256[] calldata ids,
        bytes calldata data
    )
        external
        onlyRole(MINTER_ROLE)
    {
        uint256[] memory amounts = new uint256[](ids.length);
        
        // Calculate amounts to mint (max - already minted)
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 cap = maxSupply[ids[i]];
            if (cap == 0) revert CapNotSet();
            uint256 remaining = cap - minted[ids[i]];
            if (remaining == 0) revert CapExceeded();
            amounts[i] = remaining;
            minted[ids[i]] = cap;
        }
        
        _mintBatch(to, ids, amounts, data);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}