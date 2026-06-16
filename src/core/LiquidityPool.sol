//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LiquidityPool is ERC20 {
    IERC20 public tokenA;
    IERC20 public tokenB;
    uint256 public reserveA;
    uint256 public reserveB;

   
    constructor(IERC20 _tokenA, IERC20 _tokenB) ERC20("Rog LP Token", "RLP") {
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function addLiquidity(uint256 amountA, uint256 amountB)  public {
        require(amountA > 0 && amountB > 0,"amount must > 0");
        SafeERC20.safeTransferFrom(tokenA, msg.sender, address(this), amountA);
        SafeERC20.safeTransferFrom(tokenB, msg.sender, address(this), amountB);

        uint256 liquidityTokenAmount;
        if(totalSupply() == 0){
            liquidityTokenAmount = Math.sqrt(amountA * amountB);
        }else{
            liquidityTokenAmount = Math.min(amountA * totalSupply() / reserveA, amountB * totalSupply() / reserveB);
        }
        require(liquidityTokenAmount > 0, "Liquidity must > 0");
        reserveA += amountA;
        reserveB += amountB;
        _mint(msg.sender, liquidityTokenAmount);
    }

    function removeLiquidity(uint liquidityTokenAmount) public {
        require(liquidityTokenAmount > 0 , "Amount LP must greater than zero");
        uint amountA = liquidityTokenAmount * reserveA / totalSupply();
        uint amountB = liquidityTokenAmount * reserveB / totalSupply();

        require(amountA > 0 && amountB > 0, "amount must greater zero");

        reserveA -= amountA;
        reserveB -= amountB;

        _burn(msg.sender, liquidityTokenAmount);

        SafeERC20.safeTransfer(tokenA, msg.sender, amountA);
        SafeERC20.safeTransfer(tokenB, msg.sender, amountB);
    }
    
    
    function swap(uint amountIn,IERC20 _token0) public{

        address tokenIn = address(_token0);

        require(amountIn > 0,"amount must greater than zero");
        require(tokenIn == address(tokenA) || tokenIn ==  address(tokenB), "Invalid token");

        uint amountInWithFee = amountIn * 997/1000; //0.3%

        if(tokenIn == address(tokenA)){
            uint amountOut = reserveB - (reserveA * reserveB / (reserveA + amountInWithFee));
            reserveA += amountIn;
            reserveB -= amountOut;
            SafeERC20.safeTransferFrom(_token0, msg.sender, address(this), amountIn);
            SafeERC20.safeTransfer(tokenB, msg.sender, amountOut);
        }else{

            uint amountOut = reserveA - (reserveB * reserveA / (reserveB + amountInWithFee));
            reserveB += amountIn;
            reserveA -= amountOut;
            SafeERC20.safeTransferFrom(_token0, msg.sender, address(this), amountIn);
            SafeERC20.safeTransfer(tokenA, msg.sender, amountOut);

        }

    }




}