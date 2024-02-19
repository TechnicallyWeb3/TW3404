TW3404 is my rendition of "ERC404" using a combined ERC1155 and ERC20 contract to achieve the same results, while allowing NFTs to become transferrable.

In the original "ERC404" tokens were burned and re-minted, this has since been updated but by using ERC1155 and binding the ERC20 tokens users and platforms can take advantage of BatchTransfers so users can specify which NFTs to include in their transfer. If they don't specify tokenIds in their ERC1155 transfer or use an ERC20 transfer it'll take their latest ownedTokens. Users who are trying to use an ERC20 platform where they want to keep their latest can send themselves a batch transfer of NFTs they don't care to lose/want to send before initiating the ERC20 transfer.

Feel free to comment or contribute!
