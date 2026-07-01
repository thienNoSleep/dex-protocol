// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, stdError} from "forge-std/Test.sol";
import {MockERC20} from "src/tokens/MockERC20.sol";
import {RogStringX} from "src/tokens/RogStringX.sol";
import {StakingReward} from "src/core/StakingReward.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract testStakingReward is Test {
    MockERC20 public stakeToken;
    RogStringX public rewardToken;
    StakingReward public stakingReward;
    address alice;
    address bob;

    function setUp() public {
        stakeToken = new MockERC20("LPToken", "LPT");
        rewardToken = new RogStringX();
        stakingReward = new StakingReward(address(stakeToken), address(rewardToken));
        rewardToken.mint(address(stakingReward), 1000000);
        stakeToken.mint(address(this), 10000000);

        stakingReward.notifyRewardAmount(1000000);

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        stakeToken.mint(alice, 10000);

        vm.prank(alice);
        stakeToken.approve(address(stakingReward), 1000);

        vm.prank(alice);
        stakingReward.stake(1000);
    }

  //happy path

    function testStakingFunction() public {
        stakeToken.approve(address(stakingReward), 200);
        stakingReward.stake(200);

        vm.warp(block.timestamp + 1 days);
        assertEq(stakingReward.earned(alice), 72000);
        assertEq(stakingReward.totalStaked(), 1200);
        assertEq(stakingReward.stakedAmount(address(this)), 200);
    }

    function testWithdrawFunction() public {
        vm.prank(alice);
        stakingReward.withdraw(1000);
        assertEq(stakeToken.balanceOf(alice), 10000);
        assertEq(stakingReward.stakedAmount(alice), 0);
    }

    function testClaimFunction() public {
        vm.warp(block.timestamp + 1 days);
        assertEq(stakingReward.earned(alice), 86400);
        vm.prank(alice);
        stakingReward.claimReward();
        assertEq(rewardToken.balanceOf(alice), 86400);
        assertEq(stakingReward.rewards(alice), 0);
    }

   //unhappy path

    // Staking more mid-period must bank the already-earned reward first,
    // then accrue the new stake going forward.
    function testStakeAgainBanksThenAccrues() public {
        // Day 1: alice sole staker (1000) -> earns 86400.
        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        stakeToken.approve(address(stakingReward), 1000);
        vm.prank(alice);
        stakingReward.stake(1000); // updateReward banks day-1 reward before stake grows

        // Day-1 reward locked into rewards[] at the moment of the second stake.
        assertEq(stakingReward.rewards(alice), 86400);
        assertEq(stakingReward.stakedAmount(alice), 2000);

        // Day 2: still sole staker -> whole drip (86400) is hers again.
        vm.warp(block.timestamp + 1 days);
        assertEq(stakingReward.earned(alice), 172800);
    }

    // Two funding rounds: the leftover of the first period rolls into the new rate.
    function testNotifyRollsLeftover() public {
        // Fund more first: rate will rise to 2, solvency needs >= 2*604800.
        rewardToken.mint(address(stakingReward), 1000000);

        // Immediately re-notify while period is still active -> else branch.
        // leftover = rewardRate(1) * rewardsDuration(604800) = 604800.
        // new rate = (604800 + 1000000) / 604800 = 2 (floor).
        stakingReward.notifyRewardAmount(1000000);
        assertEq(stakingReward.rewardRate(), 2);
    }

   //revert

    function testStakeZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(StakingReward.InvalidAmount.selector);
        stakingReward.stake(0);
    }

    function testWithdrawZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(StakingReward.InvalidAmount.selector);
        stakingReward.withdraw(0);
    }

    function testWithdrawMoreThanStakedReverts() public {
        vm.prank(alice);
        vm.expectRevert(StakingReward.InsufficientStake.selector);
        stakingReward.withdraw(2000);
    }

    function testClaimWithNoRewardReverts() public {
        // bob never staked -> earned 0 -> banked 0 -> guard trips.
        vm.prank(bob);
        vm.expectRevert(StakingReward.InsufficientRewards.selector);
        stakingReward.claimReward();
    }

    function testNotifyByNonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        stakingReward.notifyRewardAmount(1000);
    }

    function testNotifyMoreThanFundedReverts() public {
        // rate*duration would exceed the contract's reward balance (1,000,000).
        vm.expectRevert(StakingReward.InsufficientRewards.selector);
        stakingReward.notifyRewardAmount(10000000);
    }

    //event

    function testStakeEmitsEvent() public {
        stakeToken.approve(address(stakingReward), 500);
        // check indexed topic1 (user) + data (amount); emitter = staking contract.
        vm.expectEmit(true, false, false, true, address(stakingReward));
        emit StakingReward.Staked(address(this), 500);
        stakingReward.stake(500);
    }

    function testClaimEmitsRewardPaid() public {
        vm.warp(block.timestamp + 1 days);
        vm.expectEmit(true, false, false, true, address(stakingReward));
        emit StakingReward.RewardPaid(alice, 86400);
        vm.prank(alice);
        stakingReward.claimReward();
    }
}
