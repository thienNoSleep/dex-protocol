// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "src/tokens/MockERC20.sol";
import {RogStringX} from "src/tokens/RogStringX.sol";
import {StakingReward} from "src/core/StakingReward.sol";

contract testStakingReward is Test {
    MockERC20 public stakeToken;
    RogStringX public rewardToken;
    StakingReward public stakingReward;
    address alice;

    function setUp() public {
        stakeToken = new MockERC20("LPToken", "LPT");
        rewardToken = new RogStringX();
        stakingReward = new StakingReward(address(stakeToken), address(rewardToken));
        rewardToken.mint(address(stakingReward), 1000000);
        stakeToken.mint(address(this), 10000000);

        stakingReward.notifyRewardAmount(1000000);

        alice = makeAddr("alice");
        stakeToken.mint(alice, 10000);

        vm.prank(alice);
        stakeToken.approve(address(stakingReward), 1000);

        vm.prank(alice);
        stakingReward.stake(1000);
    }

    function testStakingFunction() public {
        stakeToken.approve(address(stakingReward), 200);
        stakingReward.stake(200);

        vm.warp(block.timestamp + 1 days);
        assertEq(stakingReward.erned(alice), 72000);
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
        assertEq(stakingReward.erned(alice), 86400);
        vm.prank(alice);
        stakingReward.claimReward();
        assertEq(rewardToken.balanceOf(alice), 86400);
        assertEq(stakingReward.rewards(alice), 0);
    }
}
