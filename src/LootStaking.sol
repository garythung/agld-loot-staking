// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "abdk-libraries-solidity/ABDKMathQuad.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";
import {ERC721 as SolmateERC721} from "solmate/tokens/ERC721.sol";

library Math {
  // Source: https://medium.com/coinmonks/math-in-solidity-part-3-percents-and-proportions-4db014e080b1
  // Calculates x * y / z. Useful for doing percentages like Amount * Percent numerator / Percent denominator
  // Example: Calculate 1.25% of 100 ETH (aka 125 basis points): mulDiv(100e18, 125, 10000)
  function mulDiv(uint256 x, uint256 y, uint256 z) internal pure returns (uint256) {
    return ABDKMathQuad.toUInt(
      ABDKMathQuad.div(
        ABDKMathQuad.mul(
          ABDKMathQuad.fromUInt(x),
          ABDKMathQuad.fromUInt(y)
        ),
        ABDKMathQuad.fromUInt(z)
      )
    );
  }
}

contract LootStaking is Ownable {
    using SafeTransferLib for SolmateERC20;

    /*///////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error StartTimeInvalid();
    error StakingAlreadyStarted();
    error StakingNotActive();
    error StakingEnded();
    error EpochInvalid();
    error NoRewards();
    error WeightsInvalid();
    error NotBagOwner();
    error BagAlreadyStaked();

    /*///////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    event RewardsAdded(uint256 indexed _rewards);
    event StakingStarted(uint256 indexed _startTime);
    event WeightsSet(uint256 indexed _lootWeight, uint256 indexed _mLootWeight);
    event BagsStaked(address indexed _owner, uint256 indexed _numBags);
    event RewardsClaimed(address indexed _owner, uint256 indexed _amount);

    /*///////////////////////////////////////////////////////////////
                             CONSTANTS
    // //////////////////////////////////////////////////////////////*/
    SolmateERC20 public constant AGLD = SolmateERC20(0xf02b847FF664072c0241AA8dB32998Bbc51Bd984);
    SolmateERC721 public constant LOOT = SolmateERC721(0x84E3547f63ad6E5A1c4FE82594977525C764F0E8);
    SolmateERC721 public constant MLOOT = SolmateERC721(0xD991EafE6b2D36F786365e0cEB3b6Dbe61097c90);

    /*///////////////////////////////////////////////////////////////
                             STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice When staking begins.
    uint256 public stakingStartTime;
    uint256 public immutable numEpochs;
    uint256 public immutable epochDuration;
    uint256 public rewardsAmount;

    /// @notice Loot reward share weight represented as basis points.
    uint256[] private lootWeights;
    /// @notice mLoot reward share weight represented as basis points.
    uint256[] private mLootWeights;

    mapping(uint256 => mapping(uint256 => bool)) public stakedLootIdsByEpoch;
    mapping(uint256 => uint256[]) public epochsByLootId;
    mapping(uint256 => uint256) public numLootStakedByEpoch;

    mapping(uint256 => mapping(uint256 => bool)) public stakedMLootIdsByEpoch;
    mapping(uint256 => uint256[]) public epochsByMLootId;
    mapping(uint256 => uint256) public numMLootStakedByEpoch;

    /*///////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the staking contract with the num epochs, duration, and
    ///         initial weights for all epochs.
    /// @param _numEpochs The number of epochs in the staking period.
    /// @param _epochDuration The duration of each epoch in seconds.
    /// @param _lootWeight The initial weight for Loot bags in basis points.
    /// @param _mLootWeight The initial weight for mLoot bags in basis points.
    constructor(
        uint256 _numEpochs,
        uint256 _epochDuration,
        uint256 _lootWeight,
        uint256 _mLootWeight
    ) {
        numEpochs = _numEpochs;
        epochDuration = _epochDuration;

        lootWeights = new uint256[](numEpochs);
        mLootWeights = new uint256[](numEpochs);

        for (uint256 i = 0; i < numEpochs;) {
            lootWeights[i] = _lootWeight;
            mLootWeights[i] = _mLootWeight;
            unchecked { ++i; }
        }
    }

    /*///////////////////////////////////////////////////////////////
                             ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets starting time for staking rewards. Must be at least 1 epoch
    ///         after the current time.
    /// @param _startTime The unix time to start staking rewards in seconds.
    function setStakingStartTime(
        uint256 _startTime
    ) external onlyOwner {
        if (rewardsAmount == 0) revert NoRewards();
        if (stakingStartTime != 0) revert StakingAlreadyStarted();
        if (_startTime < block.timestamp + epochDuration) revert StartTimeInvalid();
        stakingStartTime = _startTime;

        emit StakingStarted(_startTime);
    }

    /// @notice Set epoch weights. Can only set for an epoch in the future.
    /// @param _epoch The epoch to set weights for.
    /// @param _lootWeight The reward share weight for Loot bags in basis points.
    /// @param _mLootWeight The reward share weight for mLoot bags in basis points.
    function setWeightsForEpoch(
        uint256 _epoch,
        uint256 _lootWeight,
        uint256 _mLootWeight
    ) external onlyOwner {
        uint256 currentEpoch = getCurrentEpoch();
        if (_epoch <= currentEpoch || _epoch > numEpochs) revert EpochInvalid();
        if (_lootWeight + _mLootWeight != 1e4) revert WeightsInvalid();

        lootWeights[_epoch - 1] = _lootWeight;
        mLootWeights[_epoch - 1] = _mLootWeight;

        emit WeightsSet(_lootWeight, _mLootWeight);
    }

    /// @notice Increase the internal balance of rewards. This should be called
    ///         after sending tokens to this contract.
    /// @param _amount The amount of rewards to increase.
    function notifyRewardAmount(
        uint256 _amount
    ) external onlyOwner {
        if (stakingStartTime != 0) revert StakingAlreadyStarted();

        // Proper ERC-20 implementation ensures total supply capped at uint256 max.
        unchecked {
            rewardsAmount += _amount;
        }

        emit RewardsAdded(_amount);
    }

    /*///////////////////////////////////////////////////////////////
                             STAKING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Stakes Loot bags for upcoming epoch.
    /// @param _ids Loot bags to stake.
    function signalLootStake(
        uint256[] calldata _ids
    ) external {
        _signalStake(_ids, LOOT, stakedLootIdsByEpoch, numLootStakedByEpoch);
    }

    /// @notice Stakes mLoot bags for upcoming epoch.
    /// @param _ids mLoot bags to stake.
    function signalMLootStake(
        uint256[] calldata _ids
    ) external {
        _signalStake(_ids, MLOOT, stakedMLootIdsByEpoch, numMLootStakedByEpoch);
    }

    /// @notice Stakes token ids of a specific collection for the immediate next
    ///         epoch.
    /// @param _ids NFT token IDs to stake.
    /// @param _nftToken NFT collection being staked.
    /// @param stakedNFTsByEpoch Mapping of staked NFT token IDs by epoch.
    /// @param numNFTsStakedByEpoch Mapping of number of staked NFT token IDs by epoch.
    function _signalStake(
        uint256[] calldata _ids,
        SolmateERC721 _nftToken,
        mapping(uint256 => mapping(uint256 => bool)) storage stakedNFTsByEpoch,
        mapping(uint256 => uint256) storage numNFTsStakedByEpoch
    ) internal {
        if (stakingStartTime == 0) revert StakingNotActive();
        uint256 currentEpoch = getCurrentEpoch();
        if (currentEpoch >= numEpochs) revert StakingEnded();
        uint256 nextEpoch = currentEpoch + 1;

        uint256 length = _ids.length;
        uint256 bagId;
        for (uint256 i = 0; i < length;) {
            bagId = _ids[i];
            if (_nftToken.ownerOf(bagId) != msg.sender) revert NotBagOwner();
            if (stakedNFTsByEpoch[nextEpoch][bagId]) revert BagAlreadyStaked();

            // Loot cannot overflow.
            // mLoot unlikely to reach overflow limit.
            unchecked {
                ++numNFTsStakedByEpoch[nextEpoch];
            }
            stakedNFTsByEpoch[nextEpoch][bagId] = true;

            unchecked { ++i; }
        }

        emit BagsStaked(msg.sender, length);
    }

    /// @notice Claims all staking rewards for specific Loot bags.
    /// @param _ids Loot bags to claim rewards for.
    function claimLootRewards(
        uint256[] calldata _ids
    ) external {
        _claimRewards(_ids, LOOT, lootWeights, epochsByLootId, numLootStakedByEpoch);
    }

    /// @notice Claims all staking rewards for specific mLoot bags.
    /// @param _ids Loot bags to claim rewards for.
    function claimMLootRewards(
        uint256[] calldata _ids
    ) external {
        _claimRewards(_ids, MLOOT, mLootWeights, epochsByMLootId, numMLootStakedByEpoch);
    }

    /// @notice Claims the rewards for token IDs of a specific collection.
    /// @param _ids NFT token IDs to claim rewards for.
    function _claimRewards(
        uint256[] calldata _ids,
        SolmateERC721 nftToken,
        uint256[] storage nftWeights,
        mapping(uint256 => uint256[]) storage epochsByNFTId,
        mapping(uint256 => uint256) storage numNFTsStakedByEpoch
    ) internal {
        uint256 rewards;
        uint256 rewardPerEpoch = getTotalRewardPerEpoch();
        uint256 currentEpoch = getCurrentEpoch();

        uint256 length = _ids.length;
        uint256 bagId;
        uint256 epochsLength;
        uint256 epoch;
        uint256 j;
        for (uint256 i = 0; i < length;) {
            bagId = _ids[i];
            if (nftToken.ownerOf(bagId) != msg.sender) revert NotBagOwner();

            epochsLength = epochsByNFTId[bagId].length;
            for (j = 0; j < epochsLength;) {
                epoch = epochsByNFTId[bagId][j];
                if (epoch != currentEpoch) {
                    // Proper ERC-20 implementation ensures total supply capped at uint256 max.
                    unchecked {
                        rewards += Math.mulDiv(rewardPerEpoch, nftWeights[epoch - 1], 10000) / numNFTsStakedByEpoch[epoch - 1];
                    }
                }

                unchecked { ++j; }
            }

            // Clear epochs that the bag's rewards have been claimed for.
            if (epochsByNFTId[bagId][epochsLength - 1] == currentEpoch) {
                epochsByNFTId[bagId] = [currentEpoch];
            } else {
                delete epochsByNFTId[bagId];
            }
            unchecked { ++i; }
        }

        AGLD.safeTransfer(msg.sender, rewards);
        emit RewardsClaimed(msg.sender, rewards);
    }

    /*///////////////////////////////////////////////////////////////
                             GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims all staking rewards for Loot bags.
    /// @return currentEpoch The current epoch. 0 represents time before the first epoch.
    function getCurrentEpoch() public view returns (uint256 currentEpoch) {
        if (block.timestamp < stakingStartTime) return 0;
        currentEpoch = ((block.timestamp - stakingStartTime) / epochDuration) + 1;
    }

    /// @notice Gets the bag reward weights for an epoch.
    /// @param _epoch The epoch to get the weights for.
    /// @return lootWeight The weight for Loot bags in basis points.
    /// @return mLootWeight The weight for mLoot bags in basis points.
    function getWeightsForEpoch(
        uint256 _epoch
    ) public view returns (uint256 lootWeight, uint256 mLootWeight) {
        lootWeight = lootWeights[_epoch - 1];
        mLootWeight = mLootWeights[_epoch - 1];
    }

    /// @notice Gets the amount of rewards allotted per epoch.
    /// @return amount Amount of rewards per epoch.
    function getTotalRewardPerEpoch() public view returns (uint256 amount) {
        amount = rewardsAmount / numEpochs;
    }

    /// @notice Calculates the currently claimable rewards for a Loot bag.
    /// @dev Grab the epochs the bag was staked for and run calculation for each
    ///      epoch.
    /// @param _id The bag to calculate rewards for.
    /// @return rewards Claimable rewards for the bag.
    function getRewardsForLootBag(uint256 _id) external view returns (uint256 rewards) {
        rewards = _getRewardsForEpochs(lootWeights, epochsByLootId[_id], numLootStakedByEpoch);
    }

    /// @notice Calculates the currently claimable rewards for a Loot bag.
    /// @dev Grab the epochs the bag was staked for and run calculation for each
    ///      epoch.
    /// @param _id The bag to calculate rewards for.
    /// @return rewards Claimable rewards for the bag.
    function getRewardsForMLootBag(uint256 _id) external view returns (uint256 rewards) {
        rewards = _getRewardsForEpochs(mLootWeights, epochsByMLootId[_id], numMLootStakedByEpoch);
    }

    /// @notice Calculates the currently claimable rewards for a bag that was
    ///         staked in a list of epochs.
    /// @param _nftWeights The list of NFT reward weights.
    /// @param _epochs The epochs the bag was staked in.
    function _getRewardsForEpochs(
        uint256[] memory _nftWeights,
        uint256[] memory _epochs,
        mapping(uint256 => uint256) storage numNFTsStakedByEpoch
    ) internal view returns (uint256 rewards) {
        uint256 rewardPerEpoch = getTotalRewardPerEpoch();
        uint256 currentEpoch = getCurrentEpoch();

        uint256 epochsLength = _epochs.length;
        uint256 epoch;
        for (uint256 j = 0; j < epochsLength;) {
            epoch = _epochs[j];
            if (epoch != currentEpoch) {
                unchecked {
                    rewards += Math.mulDiv(rewardPerEpoch, _nftWeights[epoch - 1], 10000) / numNFTsStakedByEpoch[epoch - 1];
                }
            }

            unchecked { ++j; }
        }
    }
}
