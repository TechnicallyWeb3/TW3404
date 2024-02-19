// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./boundERC1155.sol";

contract ImplimentationContract is TW3404{

    constructor(string memory urlERC1155, string memory nameERC20, string memory symbolERC20, uint256 ERC20perERC721) TW3404(urlERC1155, nameERC20, symbolERC20, ERC20perERC721) {

    }

    function mintErc20(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function mintErc721(uint256 id) external {
        _mint(msg.sender, id, 1, "");
    }

    function batchMint(uint256 erc20Amount, uint256[] memory erc721Ids) external {
            uint256[] memory erc721Values = new uint256[]((erc721Ids.length));
        if (erc20Amount > 0) {
            uint256[] memory ids = new uint256[](erc721Ids.length + 1);
            uint256[] memory values = new uint256[]((erc721Ids.length + 1));
            for (uint256 i; i < erc721Ids.length; i++) {
                ids[i] = erc721Ids[i];
                values[i] = 1;
            }
            values[values.length - 1] = erc20Amount;
            _mintBatch(msg.sender, ids, values, "");
        } else {
            for (uint256 i; i < erc721Ids.length; i++) {
                erc721Values[i] = 1;
            }
            _mintBatch(msg.sender, erc721Ids, erc721Values, "");
        }
    }
}