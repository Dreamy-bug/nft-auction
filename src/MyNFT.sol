// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MyNFT
 * @dev 简单的ERC721 NFT合约，支持铸造和URI存储
 * @notice 用于NFT拍卖市场的演示和测试
 */
contract MyNFT is ERC721, ERC721URIStorage, Ownable {
    // Token ID计数器
    uint256 private _tokenIdCounter;

    // 最大供应量
    uint256 public constant MAX_SUPPLY = 10000;

    /**
     * @dev NFT铸造事件
     * @param minter 铸造者地址
     * @param tokenId 新创建的Token ID
     * @param uri 元数据URI
     */
    event NFTMinted(address indexed minter, uint256 indexed tokenId, string uri);

    /**
     * @dev 构造函数
     * @notice 初始化NFT集合名称和符号，设置合约所有者
     */
    constructor() ERC721("MyNFT", "MNFT") Ownable(msg.sender) {}

    /**
     * @dev 铸造NFT
     * @param to 接收者地址
     * @param uri NFT的元数据URI（通常是IPFS链接）
     * @return 新创建的Token ID
     * @notice 只有合约所有者可以铸造
     */
    function mint(address to, string memory uri) public onlyOwner returns (uint256) {
        require(_tokenIdCounter < MAX_SUPPLY, "Max supply reached");
        require(to != address(0), "Cannot mint to zero address");

        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;

        _safeMint(to, newTokenId);
        _setTokenURI(newTokenId, uri);

        emit NFTMinted(to, newTokenId, uri);

        return newTokenId;
    }

    /**
     * @dev 重写tokenURI函数
     * @param tokenId Token ID
     * @return 元数据URI
     * @notice 需要重写以解决多重继承的冲突
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev 检查接口支持
     * @param interfaceId 接口ID
     * @return 是否支持该接口
     * @notice 实现ERC165标准，支持接口查询
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev 查询总供应量
     * @return 已铸造的NFT数量
     */
    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter;
    }
}
