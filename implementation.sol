// SPDX-License-Identifier: MIT
// TW3's take on what "ERC404" should be
pragma solidity ^0.8.20;

import "./boundERC1155.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

contract ERC404DeploymentContract is BoundERC1155 {

    constructor(
        string memory urlERC1155, 
        string memory nameERC20, 
        string memory symbolERC20, 
        uint256 ERC20perNFT
    ) BoundERC1155(urlERC1155, nameERC20, symbolERC20, ERC20perNFT) 
    // Ownable(msg.sender) 
    {}

    // receive() external payable {
    //     TW3_donateToDeveloper();
    // }

    // function TW3_donateToDeveloper() public payable {
    //     (bool success, ) = owner().call{value: msg.value}("");
    //     require(success, "donateToOwner failed");
    // }

    // // used to collect/refund any token transfers sent to the contract as donations/accidentally
    // function TW3_transferERC20(
    //     address tokenAddress,
    //     address to,
    //     uint256 amount
    // ) external onlyOwner() {
    //     IERC20 token = IERC20(tokenAddress);
    //     token.transfer(to, amount);
    // }

    /// @dev This is an example of implementing the ERC20 _mint(address, uint) function. Since ERC721 also has a _mint(address, uint) function this causes a collission unlike mixing ERC1155.
    /// @notice Use this function to mint ERC20 tokens and if you mint more than 1000000000000000000 you'll also mint NFTs too.
    function mintErc20(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    /// @dev This is an example of implementing the ERC1155 _mint(address, uint, uint[], uint[]) function. Since ERC20's signature is _mint(address, uint) function this is safe for mixing with ERC20.
    /// @dev Since any id above 0 is an NFT you'll get errors if you try to mint more than 1.
    /// @notice Use this function to mint an ERC1155 NFT with the ID number you specify if available.
    function mintNft(uint256 id) external {
        _mint(msg.sender, id, 1, "");
    }

    /// @dev This is an example of building a batch transaction for minting multiple tokens (ERC20 and NFT) at once.
    ///@notice Enter in an amount of ERC20 you want to mint and an array of specific IDs you want to mint. If you do not specify you'll get the next available NFT IDs but gas may cost more.
    function batchMint(uint256 erc20Amount, uint256[] memory nftIds) external {
            uint256[] memory nftValues = new uint256[]((nftIds.length));
        if (erc20Amount > 0) {
            uint256[] memory ids = new uint256[](nftIds.length + 1);
            uint256[] memory values = new uint256[]((nftIds.length + 1));
            for (uint256 i; i < nftIds.length; i++) {
                ids[i] = nftIds[i];
                values[i] = 1;
            }
            values[values.length - 1] = erc20Amount;
            _mintBatch(msg.sender, ids, values, "");
        } else {
            for (uint256 i; i < nftIds.length; i++) {
                nftValues[i] = 1;
            }
            _mintBatch(msg.sender, nftIds, nftValues, "");
        }
    }

    // add in queuing and whitelist logic by overriding the _update function, 
    // could use address(this) to store NFTs instead of burning and minting excluding whitelist from 
    // should include the ability to perform the super._update from BoundERC1155 to allow for whitelisted transactions. superUpdate(data)?
}
