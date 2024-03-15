// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract BoundERC1155 is ERC1155, ERC20 {

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

    /// @dev ownedTokens mapping containing an array of an addresses owned tokens. Used for automatically pulling NFTs with ERC20 transactions.
    mapping (address tokenOwner => uint256[]) internal _ownedTokens;

    /// @dev To use your own management of tokens you'll need to override this function. If overriding _update(address, address, uint[], uint[]) you may need to also override this function.
    /// @notice Use this functoion to get a list of tokens owned by an address.
    function ownedTokens(address _address) public view virtual returns (uint256[] memory) {
        return _ownedTokens[_address];
    }

    /// @dev When specific tokens are minted, burned or transacted this function gets called to remove the specific token from owner's list. Otherwise the last token gets used.
    function removeOwnedToken(uint256 id, address owner) internal virtual {
        uint256[] memory ownerTokens = _ownedTokens[owner];

        // will be gas heavy for whales with lots of tokens looking for early tokens, using an ERC20 token transfer will be best as it sends the last ones instead of specific tokens. 
        for (uint256 i = ownerTokens.length - 1; i >= 0; i++) {

            if (ownerTokens[i] == id) {         
                // remove tokenId owner old owner's ownedToken array
                _ownedTokens[owner][i] = ownerTokens[ownerTokens.length - 1];
                _ownedTokens[owner].pop();
                break;
            }

            if (i == 0) revert(); // Token not owned by owner: error ERC721InvalidOwner(address owner); ?
        }
    }

    // ERC1155 modified functions

    /// @dev The ERC1155 setApprovalForAll function also adds approval for the ERC20 token as well. If this is undesired override this function
    /// @notice Allows an operator to control all the tokens you own when approved is set to true.
    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
        _approve(_msgSender(), operator, approved ? type(uint256).max : 0);
    }

    /// @dev _update is overriding the native ERC1155 function to syncronize ERC20 (ID 0) and NFT (ID >= 1) transactions.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual override {

        if (ids.length != values.length) revert ERC1155InvalidArrayLength(ids.length, values.length);

        // set variables to calculate expected and actual ERC20 and NFTs included in the batch transaction
        uint256 erc20Value;
        uint256 erc20ValueExpected;
        uint256 nftValue;
        uint256 nftValueExpected;

        // get all transaction values from the batch
        for(uint256 i; i < ids.length; i++) {

            // Check if the current ID is an NFT
            if (ids[i] > ERC20_ID) {
                // update expected and actual values
                erc20ValueExpected += _erc20PerNft;
                nftValue ++;

                // if not burning add ownedTokens to receiver
                if (to != address(0)) {
                    _ownedTokens[to].push(ids[i]);
                }

                // if not minting remove ownedTokens from sender
                if (from != address(0)) {
                    removeOwnedToken(ids[i], from);
                } 
                // if minting update supply to check for non-fungibility
                else {
                    _totalSupply[ids[i]] += values[i];
                }
                // update to formal error
                require (_totalSupply[ids[i]] < 2, "NFT not unique");
            } 

            // Current ID is ERC20
            else {

                // get voluntarily sent erc20 value to determine whether to pull any NFTs with the tx
                erc20Value += values[i];
                nftValueExpected = (balanceOf(to, ERC20_ID) + erc20Value) / _erc20PerNft;

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

        
        // automatically send latest NFTs if none are selected for batch transfer requiring NFT tokens.
        // calculates size of nftRequired array to a max of _ownedTokens
        uint256 requiredLength;

        if (nftValueExpected > nftValue) {
            if (nftValueExpected - nftValue < _ownedTokens[from].length) {
                requiredLength = nftValueExpected - nftValue;
            } else {
                requiredLength = _ownedTokens[from].length;
            }
        }
        
        // builds the array of any extra NFTs not batched from the end of the sender's ownedTokens list
        uint256[] memory nftRequired = new uint256[](requiredLength);

        for (uint256 i; i < requiredLength; i++) {  
            nftRequired[i] = _ownedTokens[from][_ownedTokens[from].length - 1];
            nftValue += 1;
            _ownedTokens[from].pop();
            _ownedTokens[to].push(nftRequired[i]);
        }

        // adjust amount of ERC20 needed for the NFT transfer where enough isn't sent by adjusting the value of the erc20Index
        uint256 erc20Required = erc20Value < erc20ValueExpected ? erc20ValueExpected - erc20Value : 0;

        // build final array to pass forward to ERC1155 super._update
        uint256[] memory newIds = new uint256[](ids.length + nftValue + (erc20Required > 0 ? 1 : 0));
        uint256[] memory newValues = new uint256[](values.length + nftValue + (erc20Required > 0 ? 1 : 0));

        // include the original array
        for (uint256 i; i < ids.length; i++) {
            newIds[i] = ids[i];
            newValues[i] = values[i];
        }

        // include the additional NFT values
        for (uint256 i; i < requiredLength; i++) {
            newIds[ids.length + i] = nftRequired[i];
            newValues[ids.length + i] = 1;
        }

        // include any additional erc20 funds
        if (erc20Required > 0) {
            // update _totalSupply for additional funds minted/burned
            if (from == address(0)) {
                // Overflow check required: The rest of the code assumes that totalSupply never overflows
                _totalSupply[ERC20_ID] += erc20Required;
            } 
    
            if (to == address(0)) {
                // Overflow possible: value unchecked, gets checked later in the super._update
                _totalSupply[ERC20_ID] -= erc20Required;
            }
            newIds[newIds.length-1] = ERC20_ID;
            newValues[newValues.length-1] = erc20Required;
        }

        // fulfill the transfer with bound values
        super._update(from, to, newIds, newValues);
        
        // check balances for any newly split or assembled tokens
        adjustNftBalances(from);
        adjustNftBalances(to);

    }

    /// @dev adjustNftBalances will adjust balances of NFTs as a result of splitting or combining of tokens. 
    /// @dev If you plan to use a fixed queue of tokens you can override this function to replace address(0) with address(this) and only mint from address(0) if balanceOf(address(this)) == 0
    function adjustNftBalances(address _address) internal virtual {
        if (_address != address(0)) {
            uint256[] memory finalIds = new uint256[](1);
            uint256[] memory finalValues = new uint256[](1);
            finalValues[0] = 1;

            uint256 expectedNfts = balanceOf(_address) / _erc20PerNft;

            uint256 adjustmentLength;
            // updates balance, burning any tokens which have been split, should only ever be off by 1, except while burning.
            while (expectedNfts < _ownedTokens[_address].length) {
                finalIds[0] = _ownedTokens[_address][_ownedTokens[_address].length -1];
                _ownedTokens[_address].pop();
                // burn - adjust array instead and use single super._update at function end
                // add sender and receiver addresses to set for final super._update

                super._update(_address, address(0), finalIds, finalValues);
                // emit burn

                adjustmentLength ++;
            }

            // updates balance, minting any tokens which have been combined, should only ever be off by 1, except while minting.
            while (expectedNfts > _ownedTokens[_address].length) {
                
                _nextId();

                finalIds[0] = _nftId;
                _ownedTokens[_address].push(_nftId);
                _totalSupply[_nftId] += 1;
                // update to formal error
                require (_totalSupply[_nftId] < 2, "NFT not unique");
                
                // mint
                super._update(address(0), _address, finalIds, finalValues);

                // emit mint
                adjustmentLength ++;
            }
        }
    }

    /// @dev You may override this function to choose your own Id pattern by default it starts at 1 and incriments skipping any used IDs.
    function _nextId() internal virtual {
        // automatic ID picking, skips used ids from custom minting finds next available _nftId
        while (_totalSupply[_nftId] > 0) {
            _nftId ++;
        }
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
    function approve(address spender, uint256 value) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        if (value == type(uint256).max) _setApprovalForAll(owner, spender, true);
        else if (value == 0) _setApprovalForAll(owner, spender, false);
        return true;
    }

    // ERC404 specific functions
    // function erc20PerNft() public view virtual returns (uint256) {
    //     return _erc20PerNft;
    // }
}
