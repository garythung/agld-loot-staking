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
        staking = new LootStaking(5, 60, 9920, 80);

        uint256 numLootsToClaim = 6;
        for (uint256 i = 1; i < numLootsToClaim; i++) {
            loot.claim(i);
            mLoot.claim(8000 + i);
        }
    }

    function testSetStartStaking() public {
        staking.setStakingStartTime(block.timestamp + staking.epochDuration() + 86400);
    }

    function testAdjustWeights() public {
        staking.setWeightsForEpoch(5, 5000, 5000);
    }

    function testNotifyRewardAmount() public {
        staking.notifyRewardAmount(8000000e18);
    }
}
