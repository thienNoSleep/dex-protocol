// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LiquidityPool} from "src/core/LiquidityPool.sol";
import {MockERC20} from "src/tokens/MockERC20.sol";
import {RogStringX} from "src/tokens/RogStringX.sol";
import {console} from "lib/forge-std/src/console.sol";

contract TestLP is Test{
    
    LiquidityPool public liquidityPool;
    MockERC20 public mockERC20;
    RogStringX public rogStringX;
    MockERC20 public  tokenInvalid;
    

    function setUp() public{
        mockERC20 = new MockERC20("BitcoinFake","BTCF");
        rogStringX = new RogStringX();
        liquidityPool = new LiquidityPool(mockERC20,rogStringX);
        tokenInvalid = new MockERC20("Test","T");
    }

    function test_addLiquidity() public{
        rogStringX.approve(address(liquidityPool), 1000);
        mockERC20.approve(address(liquidityPool), 1000);

        liquidityPool.addLiquidity(100,100);

        assertEq(liquidityPool.reserveA(),100);
        assertEq(liquidityPool.reserveB(),100);
        assertEq(liquidityPool.balanceOf(address(this)),100);
    }

    function test_swap() public {
        rogStringX.approve(address(liquidityPool), 99999999999);
        mockERC20.approve(address(liquidityPool), 99999999999);

        liquidityPool.addLiquidity(1000,1000);

        uint  kBefore = liquidityPool.reserveA() * liquidityPool.reserveB();
        
        liquidityPool.swap(100,rogStringX);

        uint kAfter = liquidityPool.reserveA() * liquidityPool.reserveB();
        assertEq(rogStringX.balanceOf(address(liquidityPool)),1100);
        assertEq(mockERC20.balanceOf(address(liquidityPool)),910);
        assertEq(liquidityPool.balanceOf(address(this)),1000);
        assertGe(kAfter,kBefore);

    }

    function test_removeLiquidity() public {
        rogStringX.approve(address(liquidityPool), 10000);
        mockERC20.approve(address(liquidityPool), 10000);

        liquidityPool.addLiquidity(100,100);
        assertEq(liquidityPool.balanceOf(address(this)),100);
        liquidityPool.addLiquidity(100,50);
        assertEq(liquidityPool.balanceOf(address(this)),150);
        liquidityPool.removeLiquidity(150);
        assertEq(liquidityPool.balanceOf(address(this)),0);
        assertEq(liquidityPool.totalSupply(),0);
    }



    function test_swap_revertOnZero() public {
        vm.expectRevert(LiquidityPool.InvalidAmount.selector);
        liquidityPool.swap(0,rogStringX);
    }

    function test_add_liquidity_revertOnZero() public{
        vm.expectRevert(LiquidityPool.InvalidAmount.selector);
        liquidityPool.addLiquidity(0, 10);
    }

    function test_remove_liquidity_revertOnZero() public{
        vm.expectRevert(LiquidityPool.InvalidAmount.selector);
        liquidityPool.removeLiquidity(0);
    }

    function test_swap_invalid_token() public{
        vm.expectRevert(LiquidityPool.InvalidToken.selector);
        liquidityPool.swap(100,tokenInvalid);
    }


    //test fuzz function 

    function test_swap_fuzz(uint amountIn) public{
        amountIn = bound(amountIn, 1, 10000);

        mockERC20.approve(address(liquidityPool), 1000000);
        rogStringX.approve(address(liquidityPool), 1000000);

        
        liquidityPool.addLiquidity(1000, 1000);
        uint kBefore = liquidityPool.reserveA() * liquidityPool.reserveB();
        liquidityPool.swap(amountIn, rogStringX);
        uint kAfter = liquidityPool.reserveA() * liquidityPool.reserveB();
        assertGe(kAfter,kBefore);

    }





}