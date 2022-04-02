// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

import "../LootStaking.sol";
import "../MLoot.sol";
import "../Loot.sol";
import "../AdventureGold.sol";

contract LootStakingTest is DSTest, ERC721TokenReceiver {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    /// @notice MLoot uses block.number to determine valid token IDs.
    uint256 private constant BLOCK_START = 100000;

    Loot private loot;
    TemporalLoot private mLoot;
    AdventureGold private agld;
    LootStaking private staking;

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }

    function setUp() public {
        vm.roll(BLOCK_START);

        loot = new Loot();
        mLoot = new TemporalLoot();
        agld = new AdventureGold();

        // 5 epochs, 60 seconds each
        staking = new LootStaking(
            5,
            30,
            9920,
            80,
            address(loot),
            address(mLoot),
            address(agld)
        );

        // claim loot
        uint256 numLootsToClaim = 6;
        for (uint256 i = 1; i < numLootsToClaim; i++) {
            loot.claim(i);
            mLoot.claim(8000 + i);
        }

        // mint 1B AGLD
        agld.daoMint(1e9);

        // send AGLD
        agld.transfer(address(staking),100000e18);

        // notify AGLD received
        staking.notifyRewardAmount(100000e18);

        // // set staking start
        // uint256 startTimeUnixSeconds = block.timestamp + 900;
        // staking.setStakingStartTime(startTimeUnixSeconds);
    }

    function testSetStartStaking() public {
        vm.warp(BLOCK_START);
        // console.log(staking.rewardsAmount());
        uint256[] memory lootIds = new uint256[](1);
        lootIds[0] = 1;
        // console.log("1");
        // console.log("1");
        staking.setStakingStartTime(BLOCK_START + 30);
        // console.log("1");
        staking.signalLootStake(lootIds);
        // console.log("1");
        vm.warp(BLOCK_START + 70);
        // console.log("1");
        console.log("rewards", staking.getClaimableRewardsForLootBag(1));
    }

    // function testAdjustWeights() public {
    //     staking.setWeightsForEpoch(5, 5000, 5000);
    // }

    // function testNotifyRewardAmount() public {
    //     staking.notifyRewardAmount(8000000e18);
    // }
}
