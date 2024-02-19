// SPDX-License-Identifier: MIT
// TW3's take on what "ERC404" should be
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract BoundERC1155 is ERC1155, ERC20 {
    constructor(string memory _dataUrl, string memory _name, string memory _symbol, uint256 _erc20PerErc721) ERC1155(_dataUrl) ERC20(_name, _symbol) {
        erc20PerErc721 = _erc20PerErc721;
    }

    //erc20 blance at id 0
    uint256 constant private erc20Id = 0;
    //nfts start at 1
    uint256 public erc721Id = 1;

    uint256 public erc20PerErc721;

    mapping (uint256 id => uint256) private _totalSupply; // to replace the ERC20 value which is overriden

    mapping (address tokenOwner => uint256[]) ownedTokens;

    function removeOwnedToken(uint256 id, address from) internal virtual {
        uint256[] memory ownerTokens = ownedTokens[from];

        // will be gas heavy for whales with lots of tokens, using an ERC20 token transfer will be best as it sends the last ones instead of specific tokens. 
        for (uint256 i; i < ownerTokens.length; i++) {

            if (ownerTokens[i] == id) {         
                // remove tokenId from old owner's ownedToken array
                ownedTokens[from][i] = ownerTokens[ownerTokens.length - 1];
                ownedTokens[from].pop();
                break;
            }
        }
    }

    // ERC1155 modified functions

    // addsa approval to the ERC20 contract as well
    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
        _approve(_msgSender(), operator, approved ? type(uint256).max : 0);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual override {
        uint256 erc20Value;
        uint256 erc20ValueExpected;
        uint256 erc721Value;
        uint256 erc721ValueExpected;

        uint256 erc20Index = type(uint256).max;

        // get all transaction values
        for(uint256 i; i < ids.length; i++) {
            if (ids[i] > erc20Id) {
                erc20ValueExpected += erc20PerErc721;
                erc721Value ++;

                if (to != address(0)) {
                    ownedTokens[to].push(ids[i]);
                }
                if (from != address(0)) {
                    removeOwnedToken(ids[i], from);
                } else {
                    _totalSupply[ids[i]] += values[i];
                }
                // update to formal error
                require (_totalSupply[ids[i]] < 2, "NFT not unique");
            } else {
                // update to formal error
                require(erc20Index == type(uint256).max, "Only a single ERC20 transaction per batch update");
                erc20Index = i;

                // get voluntarily sent erc20 value to determine whether to pull any erc721s with the tx
                erc20Value = values[i];
                erc721ValueExpected = (balanceOf(to, erc20Id) + erc20Value) / erc20PerErc721;

                if (from == address(0)) {
                    // Overflow check required: The rest of the code assumes that totalSupply never overflows
                    _totalSupply[erc20Id] += values[i];
                } 
      
                if (to == address(0)) {
                    // Overflow possible: value unchecked, gets checked later in the super._update
                    _totalSupply[erc20Id] -= values[i];
                }
                
            }
        }

        
        // automatically send latest NFTs if none are selected for batch transfer requiring ERC721 tokens.
        // calculates size of erc721Required array max of ownedTokens
        uint256 requiredLength;

        if (erc721ValueExpected > erc721Value) {
            if (erc721ValueExpected - erc721Value < ownedTokens[from].length) {
                requiredLength = erc721ValueExpected - erc721Value;
            } else {
                requiredLength = ownedTokens[from].length;
            }
        }
        
        uint256[] memory erc721Required = new uint256[](requiredLength);

        for (uint256 i; i < requiredLength; i++) {  
            erc721Required[i] = ownedTokens[from][ownedTokens[from].length - 1];
            erc721Value += 1;
            ownedTokens[from].pop();
        }

        // adjust amount of ERC20 needed for the NFT transfer where enough isn't sent by adjusting the value of the erc20Index
        uint256 erc20Required = erc20Value < erc20ValueExpected ? erc20ValueExpected - erc20Value : 0;

        // build final array to pass forward to ERC1155 super._update

        uint256[] memory newIds = new uint256[](ids.length + erc721Value + (erc20Required > 0 ? 1 : 0));
        uint256[] memory newValues = new uint256[](values.length + erc721Value + (erc20Required > 0 ? 1 : 0));

        // include the original array
        for (uint256 i; i < ids.length; i++) {
            newIds[i] = ids[i];
            newValues[i] = values[i];
        }

        // include the NFT values
        // should check for ERC1155 array error first so we can iterate a single time ensuring no out of bounds errors if ids.length > values.length
        for (uint256 i; i < requiredLength; i++) {
            newIds[ids.length + i] = erc721Required[i];
            newValues[ids.length + i] = 1;
        }

        // include any additional erc20 funds
        if (erc20Required > 0) {
            // update _totalSupply for additional funds minted/burned
            if (from == address(0)) {
                // Overflow check required: The rest of the code assumes that totalSupply never overflows
                _totalSupply[erc20Id] += erc20Required;
            } 
    
            if (to == address(0)) {
                // Overflow possible: value unchecked, gets checked later in the super._update
                _totalSupply[erc20Id] -= erc20Required;
            }
            newIds[newIds.length-1] = erc20Id;
            newValues[newValues.length-1] = erc20Required;
        }

        // fulfill the transfer with bound values
        super._update(from, to, newIds, newValues);
        
        // check balances for any newly split or assembled tokens
        checkErc721Balances(from);
        checkErc721Balances(to);

    }

    function checkErc721Balances(address _address) internal virtual {
        if (_address != address(0)) {
            uint256[] memory finalIds = new uint256[](1);
            uint256[] memory finalValues = new uint256[](1);
            finalValues[0] = 1;

            // updates balance, burning any tokens which have been split, should only ever be off by 1, except while burning.
            while (balanceOf(_address) / erc20PerErc721 < ownedTokens[_address].length) {
                finalIds[0] = ownedTokens[_address][ownedTokens[_address].length -1];
                ownedTokens[_address].pop();
                // burn - adjust array instead and use single super._update at function end
                // add sender and receiver addresses to set for final super._update
                super._update(_address, address(0), finalIds, finalValues);
                // emit burn
            }

            // updates balance, minting any tokens which have been combined, should only ever be off by 1, except while minting.
            while (balanceOf(_address) / erc20PerErc721 > ownedTokens[_address].length) {
                // skips used ids from custom minting finds next available erc721Id
                while (_totalSupply[erc721Id] > 0) {
                    erc721Id ++;
                }

                finalIds[0] = erc721Id;
                ownedTokens[_address].push(erc721Id);
                _totalSupply[erc721Id] += 1;
                // update to formal error
                require (_totalSupply[erc721Id] < 2, "NFT not unique");
                
                // mint
                super._update(address(0), _address, finalIds, finalValues);

                // emit mint
            }
        }
    }


    // bound ERC20 modified functions

    function _update(address from, address to, uint256 value) internal virtual override {
        // emit ERC20 event and perform _update on ERC1155 to track balances
        uint256 fromBalance = balanceOf(from);
        if (fromBalance < value && from != address(0)) {
            revert ERC20InsufficientBalance(from, fromBalance, value);
        }

        emit Transfer(from, to, value);

        // syncronize with ERC1155 token @ erc20Id(0) and perform associated NFT transfers if applicable
        uint256[] memory ids = new uint256[](1);
        uint256[] memory values = new uint256[](1);
        ids[0] = erc20Id;
        values[0] = value;

        _update(from, to, ids, values);
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return balanceOf(account, erc20Id);
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply[erc20Id];
    }

    // if value is max or 0 adjust setApprovalForAll for ERC1155
    function approve(address spender, uint256 value) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        if (value == type(uint256).max) _setApprovalForAll(owner, spender, true);
        else if (value == 0) _setApprovalForAll(owner, spender, false);
        return true;
    }
}
