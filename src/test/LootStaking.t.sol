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

    Loot private loot;
    TemporalLoot private mLoot;
    AdventureGold private agld;
    LootStaking private staking;

    /// @notice MLoot uses block.number to determine valid token IDs.
    uint256 private constant BLOCK_START = 100000;

    // AGLD constants
    uint256 private constant AGLD_SUPPLY = 1e9 * 1e18;

    // STAKING constants
    uint256 private constant NUM_EPOCHS = 5;
    uint256 private constant EPOCH_DURATION = 30;


    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }

    // SETUP HELPERS //

    function claimLoot(uint256 _num) internal returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](_num);
        uint256 i;
        for (i = 1; i <= _num; i++) {
            loot.claim(i);
            ids[i - 1] = i;
        }

        return ids;
    }

    function claimMLoot(uint256 _num) internal returns (uint256[] memory) {
        if (block.number == 0) {
            vm.roll(BLOCK_START);
        }

        uint256[] memory ids = new uint256[](_num);
        uint256 i;
        for (i = 1; i <= _num; i++) {
            mLoot.claim(8000 + i);
            ids[i - 1] = i;
        }

        return ids;
    }

    function mintAGLD(uint256 _amount) internal {
        agld.daoMint(_amount / 1e18);
    }

    function transferAGLD(uint256 _amount) internal {
        agld.transfer(address(staking), _amount);
    }

    function notifyAGLD(uint256 _amount) internal {
        staking.notifyRewardAmount(_amount);
    }

    function transferAndNotifyAGLD(uint256 _amount) internal {
        transferAGLD(_amount);
        notifyAGLD(_amount);
    }

    function mintTransferAndNotifyAGLD(uint256 _amount) internal {
        mintAGLD(_amount);
        transferAGLD(_amount);
        notifyAGLD(_amount);
    }



    function setStartTime(uint256 _timestamp) internal {
        staking.setStakingStartTime(_timestamp);
    }

    // SET UP //

    function setUp() public {
        loot = new Loot();
        mLoot = new TemporalLoot();
        agld = new AdventureGold();

        uint256 lootBips = 9920;
        uint256 mLootBips = 1e4 - lootBips;

        staking = new LootStaking(
            NUM_EPOCHS,
            EPOCH_DURATION,
            lootBips,
            mLootBips,
            address(loot),
            address(mLoot),
            address(agld)
        );
    }

    // TESTS //

    function test_fuzz_setStakingStartTime(uint256 _startTime) public {
        vm.assume(_startTime >= block.timestamp + staking.epochDuration());
        mintTransferAndNotifyAGLD(AGLD_SUPPLY);

        staking.setStakingStartTime(_startTime);
        assertEq(staking.stakingStartTime(), _startTime);
    }

    /// @notice stakingStartTime == 0.
    function test_getCurrentEpoch_NoStartTime() public {
        mintTransferAndNotifyAGLD(AGLD_SUPPLY);

        assertEq(staking.stakingStartTime(), 0);
        assertEq(staking.getCurrentEpoch(), 0);
    }

    /// @notice block.timestamp < stakingStartTime.
    function test_getCurrentEpoch_BeforeStartTime() public {
        mintTransferAndNotifyAGLD(AGLD_SUPPLY);

        uint256 startTime = block.timestamp + staking.epochDuration();
        setStartTime(startTime);

        vm.warp(startTime - 1);
        assertEq(staking.getCurrentEpoch(), 0);
    }

    /// @notice block.timestamp == stakingStartTime.
    function test_getCurrentEpoch_AtStartTime() public {
        mintTransferAndNotifyAGLD(AGLD_SUPPLY);

        uint256 startTime = block.timestamp + staking.epochDuration();
        setStartTime(startTime);

        vm.warp(startTime);
        assertEq(staking.getCurrentEpoch(), 1);
    }

    /// @notice block.timestamp >= stakingStartTime + epochDuration.
    function test_getCurrentEpoch_AfterStartTime() public {
        mintTransferAndNotifyAGLD(AGLD_SUPPLY);

        uint256 startTime = block.timestamp + staking.epochDuration();
        setStartTime(startTime);
        uint256 currentEpoch = staking.getCurrentEpoch();

        vm.warp(startTime + staking.epochDuration());
        assertGt(staking.getCurrentEpoch(), currentEpoch);
    }

    /// @notice block.timestamp > staking end time.
    function test_getCurrentEpoch_AfterStakingEnds() public {
        mintTransferAndNotifyAGLD(AGLD_SUPPLY);

        uint256 startTime = block.timestamp + staking.epochDuration();
        setStartTime(startTime);

        vm.warp(startTime + staking.numEpochs() * staking.epochDuration());
        assertGt(staking.getCurrentEpoch(), staking.numEpochs());
    }

    function test_fuzz_notifyRewardAmount(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount <= AGLD_SUPPLY);
        mintAGLD(AGLD_SUPPLY);

        mintTransferAndNotifyAGLD(_amount);

        assertEq(staking.rewardsAmount(), _amount);
    }

    /// @dev Anything beyond ~300 will incur an error.
    function test_signalLootStake_ManyLootBags(uint256 _amount) public {
        vm.assume(_amount <= 300);

        mintTransferAndNotifyAGLD(AGLD_SUPPLY);

        uint256 startTime = block.timestamp + staking.epochDuration();
        setStartTime(startTime);

        uint256[] memory ids = claimLoot(_amount);

        staking.signalLootStake(ids);
        assertEq(staking.numLootStakedByEpoch(1), ids.length);
    }

    /// @dev Would like to use fuzz testing but large numbers will incur call
    ///      stack error.
    function test_claimLootRewards_BeforeStakingStarts() public {
        mintTransferAndNotifyAGLD(AGLD_SUPPLY);

        uint256 startTime = block.timestamp + staking.epochDuration();
        setStartTime(startTime);

        uint256 num = 1;
        uint256[] memory ids = claimLoot(num);

        staking.signalLootStake(ids);
        assertEq(staking.getClaimableRewardsForLootBag(1), 0);
    }

    /// @dev Would like to use fuzz testing but large numbers will incur call
    ///      stack error.
    function test_claimLootRewards_AfterEpochStarts() public {
        mintTransferAndNotifyAGLD(AGLD_SUPPLY);

        uint256 startTime = block.timestamp + staking.epochDuration();
        setStartTime(startTime);

        uint256 num = 1;
        uint256[] memory ids = claimLoot(num);

        staking.signalLootStake(ids);

        vm.warp(startTime);
        assertEq(staking.getClaimableRewardsForLootBag(1), 0);

        vm.warp(startTime + 1);
        assertEq(staking.getClaimableRewardsForLootBag(1), 0);
    }

    /// @dev Mint fixed amount of tokens and then sends any amount to the
    ///      staking contract in preparation for testing.
    function helper_fuzz_prepareClaiming(uint256 _amount) internal {
        // Basis point calculations fail below 10000 * numEpochs.
        vm.assume(_amount >= 1e4 * staking.numEpochs());
        // Cap fuzzing at AGLD minted.
        vm.assume(_amount <= AGLD_SUPPLY);

        mintAGLD(AGLD_SUPPLY);
        transferAndNotifyAGLD(_amount);

        // Remove excess AGLD from the test contract account.
        agld.transfer(HEVM_ADDRESS, agld.balanceOf(address(this)));
    }

    function test_fuzz_claimLootRewards_BeforeOneEpoch(uint256 _amount) public {
        helper_fuzz_prepareClaiming(_amount);

        uint256 startTime = block.timestamp + staking.epochDuration();
        setStartTime(startTime);

        uint256 num = 5;
        uint256[] memory ids = claimLoot(num);

        // Stake Loot.
        staking.signalLootStake(ids);

        // Fast forward to time before epoch ends.
        vm.warp(startTime + staking.epochDuration() - 1);

        // Claim rewards.
        assertEq(staking.getClaimableRewardsForLootBag(1), 0);
        staking.claimLootRewards(ids);

        assertEq(agld.balanceOf(address(this)), 0);
    }

    function test_fuzz_claimLootRewards_AfterOneEpoch(uint256 _amount) public {
        helper_fuzz_prepareClaiming(_amount);

        // Start staking.
        uint256 startTime = block.timestamp + staking.epochDuration();
        setStartTime(startTime);

        // Claim Loot.
        uint256 num = 5;
        uint256[] memory ids = claimLoot(num);

        // Stake Loot.
        staking.signalLootStake(ids);

        // Fast foward to after epoch.
        vm.warp(startTime + staking.epochDuration());

        // Claim rewards.
        staking.claimLootRewards(ids);

        uint256 rewardPerEpoch = staking.getTotalRewardPerEpoch();
        (uint256 lootWeight,) = staking.getWeightsForEpoch(1);
        uint256 numNFTsStaked = staking.numLootStakedByEpoch(1);
        uint256 expectedReward = staking.getRewardPerEpochPerBag(rewardPerEpoch, lootWeight, numNFTsStaked) * num;
        assertEq(agld.balanceOf(address(this)), expectedReward);
        assertEq(staking.getClaimableRewardsForLootBag(1), 0);

        // Claiming again shouldn't do anything.
        staking.claimLootRewards(ids);
        assertEq(agld.balanceOf(address(this)), expectedReward);
    }

    function test_fuzz_claimLootRewards_AfterTwoEpochs(uint256 _amount) public {
        helper_fuzz_prepareClaiming(_amount);

        // Start staking.
        uint256 startTime = block.timestamp + staking.epochDuration();
        setStartTime(startTime);

        // Claim Loot.
        uint256 num = 5;
        uint256[] memory ids = claimLoot(num);

        // Stake Loot.
        staking.signalLootStake(ids);

        // Fast foward to during epoch.
        vm.warp(startTime + staking.epochDuration() - 1);

        // Stake Loot again.
        staking.signalLootStake(ids);

        // Fast foward to after 2nd epoch.
        vm.warp(startTime + 2 * staking.epochDuration());

        // Claim rewards.
        staking.claimLootRewards(ids);

        uint256 rewardPerEpoch = staking.getTotalRewardPerEpoch();
        (uint256 lootWeight,) = staking.getWeightsForEpoch(1);
        uint256 numNFTsStaked = staking.numLootStakedByEpoch(1);
        uint256 expectedReward = staking.getRewardPerEpochPerBag(rewardPerEpoch, lootWeight, numNFTsStaked) * num * 2;
        assertEq(agld.balanceOf(address(this)), expectedReward);
        assertEq(staking.getClaimableRewardsForLootBag(1), 0);
    }
}
