// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract ERC420 is ERC1155, ERC20 {
    using Strings for uint256;

    constructor(
        string memory _dataUrl, 
        string memory _name, 
        string memory _symbol, 
        uint256 __rarityBase
    ) 
    ERC1155(_dataUrl) 
    ERC20(_name, _symbol) {
        _rarityBase = __rarityBase;
        _mint(msg.sender, 0, 10000000000000000000000, "");
    }

    uint160 constant internal ERC20_ID = 0;

    uint256 internal _rarityBase;

    // /// @dev nftId is an automated ID system if you do not impliment one, IDs will start at 1 and incriment, you can override this behavior by overriding the _nextId() function with your own logic
    // uint256 internal _nftId = 1;

    /// @dev used for tracking the ERC20 total supply and used for ensuring NFT non-fungibility. Returned ID 0 in public ERC20 totalSupply() function.
    mapping (address id => uint256) internal _totalSupply;

    function tokenRarity(address owner) public view returns(uint256) {
        return balanceOf(owner, ERC20_ID) > 0 ? logBaseScale(balanceOf(owner, ERC20_ID)) + 1 : 0;
    }

    // gets rarity from balance
    function logBaseScale(uint256 balance) internal view returns (uint256) {
        require(balance > 0, "invalid log");
        
        uint256 result = 0;
        while (balance >= _rarityBase) {
            balance /= _rarityBase;
            result++;
        }
        
        return result;
    }

    function balanceFromRarity(uint256 rarity) internal view returns (uint256) {
        require(rarity > 0, "invalid rarity");

        // Calculate balance using reverse of logBaseScale function
        return _rarityBase ** (rarity - 1);
    }

    // upgradable ERC1155 modified functions

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override virtual {
        // check that batch update is valid.
        if (ids.length != values.length) revert ERC1155InvalidArrayLength(ids.length, values.length);

        // users can only own 1 NFT so can only send an NFT and tokens, should not be transferring more than 2.
        if (values.length > 2) revert ERC1155InvalidArrayLength(ids.length, values.length);
        
        uint256[] memory newIds = new uint256[](1);
        uint256[] memory newValues = new uint256[](1);

        newIds[0] = ERC20_ID;

        if (from != address(0)) {

        }
        for (uint8 i; i < ids.length; i++) {
            if (ids[i] == ERC20_ID) {
                newValues[0] = values[i];
            }
            if (ids[i] > ERC20_ID) {
                newValues[0] = balanceFromRarity(balanceOf(from));
            }
        }
        super._update(from, to, newIds, newValues);

        adjustSftBalance(from);
        adjustSftBalance(to);

        if (from == address(0)) {
            _totalSupply[address(ERC20_ID)] += newValues[0];
        }

        if (to == address(0)) {
            _totalSupply[address(ERC20_ID)] -= newValues[0];
        }

    }

    function adjustSftBalance(address owner) public {
        if (owner != address(0)) {
            uint256[] memory ids = new uint256[](1);
            ids[0] = uint160(owner);
            uint256[] memory values = new uint256[](1);
            if (_totalSupply[owner] < tokenRarity(owner)) {
                values[0] = tokenRarity(owner) - _totalSupply[owner];
                super._update(address(0), owner, ids, values);
                // super._mint(owner, uint160(owner), tokenRarity(owner) - _totalSupply[owner], "");
            }
            if (_totalSupply[owner] > tokenRarity(owner)) {
                values[0] = _totalSupply[owner] - tokenRarity(owner);
                super._update(owner, address(0), ids, values);
                // super._burn(owner, uint160(owner), _totalSupply[owner] - tokenRarity(owner));
            }
            // using your idea of SFTs.
            _totalSupply[owner] = tokenRarity(owner); // if you add the following code they become NFTs: > 0 ? 1 : 0;
        }
    }

    function uri(uint256 id) public view override returns (string memory) {
        
        return string.concat(
            string.concat(
                super.uri(id), 
                tokenRarity(address(uint160(id))).toString()
            ), ".json");
    }

    // upgradable ERC20 modified functions

    /// @dev _update ERC20 functon overriden to convert ERC20 transaction to ERC404 transaction
    function _update(address from, address to, uint256 value) internal virtual override {

        uint256 fromBalance = balanceOf(from);
        if (fromBalance < value && from != address(0)) {
            revert ERC20InsufficientBalance(from, fromBalance, value);
        }

        emit Transfer(from, to, value);

        // syncronize with ERC1155 token @ ERC20_ID(0) and perform associated NFT transfers if applicable
        uint256[] memory ids = new uint256[](1);
        uint256[] memory values = new uint256[](1);
        ids[0] = ERC20_ID;
        values[0] = value;

        _update(from, to, ids, values);
    }

    /// @notice ERC20 balanceOf(address) function
    function balanceOf(address account) public view virtual override returns (uint256) {
        return balanceOf(account, ERC20_ID);
    }

    /// @notice ERC20 totalSupply() function
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply[address(ERC20_ID)];
    }

    /// @dev if approve function is set to uint256.max this will also trigger an approveForAll for specific NFTs aswell.
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal override virtual {
        super._approve(owner, spender, value, emitEvent);

        if (value == type(uint256).max) _setApprovalForAll(owner, spender, true);
        else _setApprovalForAll(owner, spender, false);
    }

}