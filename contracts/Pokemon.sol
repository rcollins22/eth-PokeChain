// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/ERC1155/ERC1155.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/token/common/ERC2981.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/utils/introspection/IERC165.sol";


contract PokemonCollection is ERC1155, AccessControl, ERC2981 {

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
     * @param royaltyReceiver  ERC2981 default royalty receiver (0x0 to disable)
     * @param royaltyFeeBps    royalty in basis points (e.g., 500 = 5%)
     */
    constructor(
        string memory baseURI,
        address admin,
        address royaltyReceiver,
        uint96 royaltyFeeBps
    ) ERC1155(baseURI) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // Assign MINTER_ROLE to admin by default; you can grant others later
        _grantRole(MINTER_ROLE, admin);

        // Optional royalties (can be disabled by passing receiver = 0x0)
        if (royaltyReceiver != address(0)) {
            _setDefaultRoyalty(royaltyReceiver, royaltyFeeBps);
        }
    }

    // ---------- Admin: URI / Royalties ----------
    function setURI(string calldata newURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newURI);
        emit BaseURISet(newURI);
    }

    /// @notice Set default ERC2981 royalty (applies to all ids unless overridden)
    function setDefaultRoyalty(address receiver, uint96 feeBps)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (receiver == address(0)) revert ZeroAddress();
        _setDefaultRoyalty(receiver, feeBps);
    }

    /// @notice Clear default royalty
    function deleteDefaultRoyalty() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _deleteDefaultRoyalty();
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

    /// @notice Batch version for convenience when bootstrapping many species.
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

    // ---------- Interface support ----------
    /**
     * @dev Required when mixing ERC1155, AccessControl, and ERC2981
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
