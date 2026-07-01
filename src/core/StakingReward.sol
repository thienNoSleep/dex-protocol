// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StakingReward
 * @author ThienLe
 * @notice Stake `stakingToken` to earn `rewardToken`, distributed at a constant rate
 *         over a fixed reward period. Based on the Synthetix StakingRewards accounting
 *         pattern: rewards are tracked with a global accumulator so payout is O(1) per
 *         user with no on-chain looping over stakers.
 * @dev Rewards must be funded by transferring `rewardToken` into this contract BEFORE
 *      the owner calls `notifyRewardAmount` (Pattern A). The solvency check in
 *      `notifyRewardAmount` reverts if the promised rate is not backed by the balance.
 */
contract StakingReward is ReentrancyGuard, Ownable {
    /// @notice Token users deposit to stake (e.g. an LP token).
    IERC20 public immutable stakingToken;
    /// @notice Token paid out as rewards.
    IERC20 public immutable rewardToken;

    /// @notice Amount currently staked by each user.
    mapping(address => uint256) public stakedAmount;
    /// @notice Reward already earned and banked for each user, awaiting claim.
    mapping(address => uint256) public rewards;
    /// @notice Value of `rewardPerTokenStored` at each user's last interaction (their bookmark).
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice Reward tokens distributed per second across the whole pool.
    uint256 public rewardRate;
    /// @notice Length of a reward period. Each `notifyRewardAmount` (re)starts this window.
    uint256 public rewardsDuration = 7 days;
    /// @notice Timestamp at which the current reward period ends.
    uint256 public periodFinish;
    /// @notice Timestamp of the last accumulator update.
    uint256 public lastUpdateTime;

    /// @notice Global accumulator: reward per staked token, scaled by 1e18.
    uint256 public rewardPerTokenStored;
    /// @notice Total amount staked across all users.
    uint256 public totalStaked;

    /// @notice Thrown when an amount argument is zero.
    error InvalidAmount();
    /// @notice Thrown on claim with nothing earned, or when a reward rate is not fully funded.
    error InsufficientRewards();
    /// @notice Thrown when not enough stake token.
    error InsufficientStake();

    /// @notice Emitted when a user stakes.
    /// @param user The staker.
    /// @param amount Amount staked.
    event Staked(address indexed user, uint256 amount);
    /// @notice Emitted when a user withdraws staked tokens.
    /// @param user The withdrawer.
    /// @param amount Amount withdrawn.
    event Withdrawn(address indexed user, uint256 amount);
    /// @notice Emitted when a user claims their reward.
    /// @param user The claimer.
    /// @param amount Reward tokens paid out.
    event RewardPaid(address indexed user, uint256 amount);
    /// @notice Emitted when the owner funds a new reward period.
    /// @param rewardAmount Reward amount added to the period.
    event RewardAdded(uint256 rewardAmount);

    /**
     * @notice Deploys the staking pool.
     * @param _stakingToken Token users stake.
     * @param _rewardToken Token distributed as rewards.
     */
    constructor(address _stakingToken, address _rewardToken) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    /**
     * @notice Starts or tops up a reward period, setting the per-second reward rate.
     * @dev Owner only. Transfer `rewardToken` into this contract BEFORE calling. If the
     *      current period is still active, undistributed reward (`leftover`) is rolled into
     *      the new rate. Reverts with `InsufficientRewards` if the rate is not backed by the
     *      contract's reward balance. Settles the accumulator first via `updateReward`.
     * @param rewardAmount New reward tokens to distribute over `rewardsDuration`.
     */
    function notifyRewardAmount(uint256 rewardAmount) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = rewardAmount / rewardsDuration;
        } else {
            uint256 leftover = rewardRate * (periodFinish - block.timestamp);
            rewardRate = (leftover + rewardAmount) / rewardsDuration;
        }
        require(rewardRate * rewardsDuration <= rewardToken.balanceOf(address(this)), InsufficientRewards());
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;

        emit RewardAdded(rewardAmount);
    }

    /**
     * @notice The last timestamp at which rewards are applicable.
     * @dev Clamps to `periodFinish` so emission freezes once the period ends.
     * @return The lesser of the current time and `periodFinish`.
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /**
     * @notice Total reward currently earned by an account (banked plus not-yet-settled).
     * @param account The account to query.
     * @return The account's total claimable reward.
     */
    function earned(address account) public view returns (uint256) {
        return (((rewardPerToken() - userRewardPerTokenPaid[account]) * stakedAmount[account]) / 1e18) + rewards[account];
    }

    /**
     * @notice Current value of the reward-per-token accumulator.
     * @dev Returns the stored value when nothing is staked (no one to credit, avoids div-by-zero).
     *      The `1e18` scaling preserves precision against integer-division flooring.
     * @return The accumulated reward per staked token, scaled by 1e18.
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalStaked);
    }

    /**
     * @notice Settles reward accounting before a state-changing action.
     * @dev Cranks the global accumulator, stamps the clock, banks the account's earned reward,
     *      then bookmarks the account. Order matters: each line consumes the pre-update value of
     *      the line below it. Pass `address(0)` when there is no specific account (e.g. funding).
     * @param account The account being updated, or `address(0)` for none.
     */
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        rewards[account] = earned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
        _;
    }

    /**
     * @notice Stakes `amount` of `stakingToken`.
     * @dev Settles rewards first, then updates balances before pulling tokens (checks-effects-interactions).
     * @param amount Amount to stake. Must be greater than zero.
     */
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, InvalidAmount());
        stakedAmount[msg.sender] += amount;
        totalStaked += amount;
        SafeERC20.safeTransferFrom(stakingToken, msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Withdraws `amount` of previously staked `stakingToken`.
     * @dev Reverts with InsufficientStake() if amount exceeds staked balance.
     * @param amount Amount to withdraw. Must be greater than zero.
     */
    function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, InvalidAmount());
        require(amount <= stakedAmount[msg.sender],InsufficientStake());
        stakedAmount[msg.sender] -= amount;
        totalStaked -= amount;
        SafeERC20.safeTransfer(stakingToken, msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Claims the caller's accrued reward.
     * @dev Settles rewards first, then zeroes the caller's balance before transferring
     *      (checks-effects-interactions). Reverts with `InsufficientRewards` if nothing is owed.
     */
    function claimReward() external nonReentrant updateReward(msg.sender) {
        require(rewards[msg.sender] > 0, InsufficientRewards());
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        SafeERC20.safeTransfer(rewardToken, msg.sender, reward);

        emit RewardPaid(msg.sender, reward);
    }
}
