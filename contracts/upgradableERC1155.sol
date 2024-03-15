// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract UpgradableERC1155 is ERC1155, ERC20 {

    constructor(
        string memory _dataUrl, 
        string memory _name, 
        string memory _symbol, 
        uint256 __erc20PerNft) 
        ERC1155(_dataUrl) 
        ERC20(_name, _symbol) {
        _erc20PerNft = __erc20PerNft;
    }

    uint256 constant internal ERC20_ID = 0;
    
    /// @dev nftId is an automated ID system if you do not impliment one, IDs will start at 1 and incriment, you can override this behavior by overriding the _nextId() function with your own logic
    uint256 internal _nftId = 1;

    /// @dev erc20PerNft is the amount of pieces of ERC20 token make up an NFT. This number is represented in wei. Allows deployers the ability to make an NFT worth 1, 100  or any other amount of ERC20 token.
    /// @notice For typical ERC404 operation set this value to 1000000000000000000.
    uint256 immutable internal _erc20PerNft;

    /// @dev used for tracking the ERC20 total supply and used for ensuring NFT non-fungibility. Returned ID 0 in public ERC20 totalSupply() function.
    mapping (uint256 id => uint256) internal _totalSupply;

    mapping (address owner => uint256) internal _ownedTokenId;


    /// @dev _update is overriding the native ERC1155 function to syncronize ERC20 (ID 0) and NFT (ID >= 1) transactions.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual override {

        // check that batch update is valid.
        if (ids.length != values.length) revert ERC1155InvalidArrayLength(ids.length, values.length);

        // users can only own 1 NFT so can only send an NFT and tokens, should not be transferring more than 2.
        if (values.length >= 2) revert ERC1155InvalidArrayLength(ids.length, values.length);

        // set variables to calculate expected and actual ERC20 and NFTs included in the batch transaction
        uint256 erc20Value;
        uint256 erc20ValueExpected;
        uint256 erc20Index;

        // get all transaction values from the batch
        for(uint256 i; i < ids.length; i++) {

            // Check if the current ID is an NFT
            if (ids[i] > ERC20_ID) {
                // update expected and actual values
                erc20ValueExpected += _erc20PerNft;

                // if minting update supply to check for non-fungibility of NFTs
                if (from == address(0)) {
                    _totalSupply[ids[i]] += values[i];
                }
                // update to formal error
                require (_totalSupply[ids[i]] < 2, "NFT not unique");
            } 

            // Current ID is ERC20
            else {

                // get voluntarily sent erc20 value to determine whether to pull any NFTs with the tx
                erc20Value += values[i];
                erc20Index = i;

                if (from == address(0)) {
                    // Overflow check required: The rest of the code assumes that totalSupply never overflows
                    _totalSupply[ERC20_ID] += values[i];
                } 
      
                if (to == address(0)) {
                    // Overflow possible: value unchecked, gets checked later in the super._update
                    _totalSupply[ERC20_ID] -= values[i];
                }
                
            }
        }

        // if only NFT was transfered send all tokens with it
        if (erc20Value == 0) erc20Value = balanceOf(from);

        // adjust amount of ERC20 needed for the NFT transfer where enough isn't sent by adjusting the value of the erc20Index
        values[erc20Index] = erc20Value < erc20ValueExpected ? erc20ValueExpected : erc20Value;

        // fulfill the transfer with bound values
        super._update(from, to, ids, values);
        
        // check balances for any newly split or assembled tokens
        adjustNfts(from);
        adjustNfts(to);

    }

    function adjustNfts(address owner) internal virtual {
        // if user should have NFT assign ID
        if (balanceOf(owner, ERC20_ID)/_erc20PerNft > 0) {
            if (_ownedTokenId[owner] == 0) {
                _ownedTokenId[owner] = _nextId();
            }
        }
        // if user shouldn't have ID remove ID
        else {
            if (_ownedTokenId[owner] > 0) {
                _ownedTokenId[owner] = 0;
            }
        }
    }

    /// @dev You may override this function to choose your own Id pattern by default it starts at 1 and incriments skipping any used IDs.
    function _nextId() internal virtual returns (uint256) {
        uint256 nextId = _nftId;
        // automatic ID picking, skips used ids from custom minting finds next available _nftId
        while (_totalSupply[_nftId] > 0) {
            _nftId ++;
        }
        return nextId;
    }

    // bound ERC20 modified functions

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
        return _totalSupply[ERC20_ID];
    }

    /// @dev if approve function is set to uint256.max this will also trigger an approveForAll for specific NFTs aswell.
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal override virtual {
        super._approve(owner, spender, value, emitEvent);

        if (value == type(uint256).max) _setApprovalForAll(owner, spender, true);
        else _setApprovalForAll(owner, spender, false);
    }
}
