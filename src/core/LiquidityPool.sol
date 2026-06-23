//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


   /**  @title LiquidityPool 
        @author ThienLe
        @notice   Constant-product (x*y=k) AMM pool for an arbitrary ERC20 pair. Mints LP tokens to providers; 0.3% swap fee accrues to reserves.
     */


contract LiquidityPool is ERC20,ReentrancyGuard {
    IERC20 public tokenA;
    IERC20 public tokenB;
    uint256 public reserveA;
    uint256 public reserveB;
    event LiquidityAdded(address indexed provider, uint amountA, uint amountB, uint liquidityTokenAmount);
    event LiquidityRemoved(address indexed Cashouted,uint amountA,uint amountB, uint lpBurn);
    event Swapped(address indexed Swapper, uint amountIn, uint amountOut);
    error InvalidAmount();
    error InsufficientLiquidity();
    error InvalidToken();
    
    /**
    @param _tokenA First token of the pair
    @param _tokenB Second token of the pair
    */
    
    constructor(IERC20 _tokenA, IERC20 _tokenB) ERC20("Rog LP Token", "RLP") {  
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    /**@notice add liquidity in to pool and mint LP token for provider 
     * @param amountA amount of tokenA that provider liquidity wanted to add in pool
     * @param amountB amount of tokenB that provider liquidity wanted to add in pool
     * @dev First provider (totalSupply==0) mints sqrt(amountA*amountB) to set initial price.
            Later providers mint min-proportional to reserves; off-ratio excess is absorbed, no extra LP.
     */
    function addLiquidity(uint256 amountA, uint256 amountB)  public nonReentrant {
        require(amountA > 0 && amountB > 0, InvalidAmount());

        uint256 liquidityTokenAmount;
        if(totalSupply() == 0){
            liquidityTokenAmount = Math.sqrt(amountA * amountB);
        }else{
            liquidityTokenAmount = Math.min(amountA * totalSupply() / reserveA, amountB * totalSupply() / reserveB);
        }
        require(liquidityTokenAmount > 0, InsufficientLiquidity());
        reserveA += amountA;
        reserveB += amountB;
        _mint(msg.sender, liquidityTokenAmount);
        SafeERC20.safeTransferFrom(tokenA, msg.sender, address(this), amountA);
        SafeERC20.safeTransferFrom(tokenB, msg.sender, address(this), amountB);

        emit LiquidityAdded(msg.sender, amountA, amountB, liquidityTokenAmount);
    }
   /**@notice remove liquidity from pool by provider and take back their pair token plus fee automatic
     * @param liquidityTokenAmount amount of LP token that liquidity provider wanted to remove 
     * @dev this function is automatic plus fee for provider by swap function so dont need another plus again
     */
    function removeLiquidity(uint liquidityTokenAmount) public nonReentrant{
        require(liquidityTokenAmount > 0 , InvalidAmount());
        uint amountA = liquidityTokenAmount * reserveA / totalSupply();
        uint amountB = liquidityTokenAmount * reserveB / totalSupply();

        require(amountA > 0 && amountB > 0, InvalidAmount());

        reserveA -= amountA;
        reserveB -= amountB;

        _burn(msg.sender, liquidityTokenAmount);

        SafeERC20.safeTransfer(tokenA, msg.sender, amountA);
        SafeERC20.safeTransfer(tokenB, msg.sender, amountB);
        emit LiquidityRemoved(msg.sender, amountA, amountB, liquidityTokenAmount);
    }
    /**@notice swap token to another token in pool
     * @param amountIn amount of token that trader want to swap
     * @param _token0  kind of token that trader wanted to trade
     * @dev amountInWithFee = amountIn * 997/1000 => that amount token want to trade is shrink to 99.7% , 0.3% is fee for liquidity provider
     */
    
    function swap(uint amountIn,IERC20 _token0) public nonReentrant {

        address tokenIn = address(_token0);

        require(amountIn > 0,InvalidAmount());
        require(tokenIn == address(tokenA) || tokenIn ==  address(tokenB), InvalidToken());

        uint amountInWithFee = amountIn * 997/1000; //0.3%

        //x*y=k
        if(tokenIn == address(tokenA)){
            uint amountOut = reserveB * amountInWithFee / (reserveA + amountInWithFee);
            reserveA += amountIn;
            reserveB -= amountOut;
            SafeERC20.safeTransferFrom(_token0, msg.sender, address(this), amountIn);
            SafeERC20.safeTransfer(tokenB, msg.sender, amountOut);
            emit Swapped(msg.sender, amountIn, amountOut);
        }else{

            uint amountOut = amountInWithFee * reserveA / (reserveB + amountInWithFee);
            reserveB += amountIn;
            reserveA -= amountOut;
            SafeERC20.safeTransferFrom(_token0, msg.sender, address(this), amountIn);
            SafeERC20.safeTransfer(tokenA, msg.sender, amountOut);
            emit Swapped(msg.sender, amountIn, amountOut);
        }

        
    }




}