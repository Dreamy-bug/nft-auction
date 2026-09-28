// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyNFT.sol";

contract MyNFTTest is Test {
    MyNFT public nft;
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        nft = new MyNFT();
    }

    // ============ 部署测试 ============

    function test_Deployment() public view {
        assertEq(nft.name(), "MyNFT");
        assertEq(nft.symbol(), "MNFT");
        assertEq(nft.totalSupply(), 0);
        assertEq(nft.owner(), owner);
        assertEq(nft.MAX_SUPPLY(), 10000);
    }

    // ============ 铸造测试 ============

    function test_Mint() public {
        string memory uri = "https://api.example.com/token/1";
        uint256 tokenId = nft.mint(user1, uri);

        assertEq(tokenId, 1);
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.balanceOf(user1), 1);
        assertEq(nft.tokenURI(1), uri);
    }

    function test_MintMultiple() public {
        nft.mint(user1, "uri1");
        nft.mint(user2, "uri2");
        nft.mint(user1, "uri3");

        assertEq(nft.totalSupply(), 3);
        assertEq(nft.balanceOf(user1), 2);
        assertEq(nft.balanceOf(user2), 1);
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.ownerOf(2), user2);
        assertEq(nft.ownerOf(3), user1);
    }

    function test_MintToZeroAddressReverts() public {
        vm.expectRevert("Cannot mint to zero address");
        nft.mint(address(0), "uri");
    }

    function test_MintNotOwnerReverts() public {
        vm.prank(user1);
        vm.expectRevert();
        nft.mint(user1, "uri");
    }

    function test_MintEmitEvent() public {
        string memory uri = "https://api.example.com/token/1";

        vm.expectEmit(true, true, false, true);
        emit MyNFT.NFTMinted(user1, 1, uri);

        nft.mint(user1, uri);
    }

    // ============ 转移测试 ============

    function test_TransferFrom() public {
        nft.mint(user1, "uri");

        vm.prank(user1);
        nft.approve(user2, 1);

        vm.prank(user2);
        nft.transferFrom(user1, user2, 1);

        assertEq(nft.ownerOf(1), user2);
        assertEq(nft.balanceOf(user1), 0);
        assertEq(nft.balanceOf(user2), 1);
    }

    function test_SafeTransferFrom() public {
        nft.mint(user1, "uri");

        vm.prank(user1);
        nft.approve(user2, 1);

        vm.prank(user2);
        nft.safeTransferFrom(user1, user2, 1);

        assertEq(nft.ownerOf(1), user2);
    }

    // ============ 授权测试 ============

    function test_Approve() public {
        nft.mint(user1, "uri");

        vm.prank(user1);
        nft.approve(user2, 1);

        assertEq(nft.getApproved(1), user2);
    }

    function test_SetApprovalForAll() public {
        nft.mint(user1, "uri1");
        nft.mint(user1, "uri2");

        vm.prank(user1);
        nft.setApprovalForAll(user2, true);

        assertTrue(nft.isApprovedForAll(user1, user2));
    }

    // ============ 接口支持测试 ============

    function test_SupportsInterface() public view {
        // ERC721 interface ID
        assertTrue(nft.supportsInterface(0x80ac58cd));
        // ERC165 interface ID
        assertTrue(nft.supportsInterface(0x01ffc9a7));
        // ERC721Metadata interface ID
        assertTrue(nft.supportsInterface(0x5b5e139f));
    }

    // ============ TokenURI测试 ============

    function test_TokenURI() public {
        string memory uri = "ipfs://QmTestHash/token1";
        nft.mint(user1, uri);

        assertEq(nft.tokenURI(1), uri);
    }

    function test_TokenURINonExistentReverts() public {
        vm.expectRevert();
        nft.tokenURI(999);
    }
}
