// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StakingReward is ReentrancyGuard, Ownable {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    mapping(address => uint256) public stakedAmount;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public userRewardPerTokenPaid;

    uint256 public rewardRate;
    uint256 public rewardsDuration = 7 days;
    uint256 public periodFinish = block.timestamp + rewardsDuration;
    uint256 public lastUpdateTime = block.timestamp;

    uint256 public rewardPerTokenStored;
    uint256 public totalStaked;

    error InvalidAmount();
    error InsufficientRewards();

    constructor(
        address _stakingToken,
        address _rewardToken
    ) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    function notifyRewardAmount(
        uint256 reward
    ) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 leftover = rewardRate * (periodFinish - block.timestamp);
            rewardRate = (leftover + reward) / rewardsDuration;
        }
        require(rewardRate * rewardsDuration <= rewardToken.balanceOf(address(this)),InsufficientRewards());
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function erned(address account) public view returns (uint256) {
        return
            (((rewardPerToken() - userRewardPerTokenPaid[account]) *
                stakedAmount[account]) / 1e18) + rewards[account];
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((lastTimeRewardApplicable() - lastUpdateTime) *
                rewardRate *
                1e18) / totalStaked);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        rewards[account] = erned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
        _;
    }

    function stake(
        uint256 amount
    ) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, InvalidAmount());
        stakedAmount[msg.sender] += amount;
        totalStaked += amount;
        SafeERC20.safeTransferFrom(
            stakingToken,
            msg.sender,
            address(this),
            amount
        );
    }

    function withdraw(
        uint256 amount
    ) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, InvalidAmount());
        stakedAmount[msg.sender] -= amount;
        totalStaked -= amount;
        SafeERC20.safeTransfer(stakingToken, msg.sender, amount);
    }

    function claimReward() public nonReentrant updateReward(msg.sender) {
        require(rewards[msg.sender] > 0, InsufficientRewards());
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        SafeERC20.safeTransfer(rewardToken, msg.sender, reward);
    }
}
