// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "./lib/Math.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "solmate/utils/SafeTransferLib.sol";
import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";
import {ERC721 as SolmateERC721} from "solmate/tokens/ERC721.sol";

// import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
// import {ERC20 as SolmateERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
// import {ERC721 as SolmateERC721} from "@rari-capital/solmate/src/tokens/ERC721.sol";

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
    error RewardsNotReceived();
    error WeightsInvalid();
    error NotBagOwner();
    error BagAlreadyStaked();

    /*///////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    event RewardsAdded(uint256 _rewards);
    event StakingStarted(uint256 _startTime);
    event WeightsSet(uint256 indexed _epoch, uint256 _lootWeight, uint256 _mLootWeight);
    event LootBagsStaked(address indexed _owner, uint256 indexed _epoch, uint256[] _bagIds);
    event MLootBagsStaked(address indexed _owner, uint256 indexed _epoch, uint256[] _bagIds);
    event LootRewardsClaimed(address indexed _owner, uint256 _amount, uint256 indexed _epoch, uint256[] _bagIds);
    event MLootRewardsClaimed(address indexed _owner, uint256 _amount, uint256 indexed _epoch, uint256[] _bagIds);

    /*///////////////////////////////////////////////////////////////
                             CONSTANTS
    // //////////////////////////////////////////////////////////////*/
    SolmateERC721 public LOOT;
    SolmateERC721 public MLOOT;
    SolmateERC20 public AGLD;

    /*///////////////////////////////////////////////////////////////
                             STORAGE
    //////////////////////////////////////////////////////////////*/
    uint256 public stakingStartTime;
    uint256 public immutable numEpochs;
    uint256 public immutable epochDuration;
    uint256 public rewardsAmount;

    /// @notice Loot reward share weight represented as basis points. Epochs are 1-indexed.
    mapping(uint256 => uint256) private lootWeightsByEpoch;

    /// @notice mLoot reward share weight represented as basis points. Epochs are 1-indexed.
    mapping(uint256 => uint256) private mLootWeightsByEpoch;

    // Loot storage vars

    /// @notice Loot IDs staked in each epoch. Epochs are 1-indexed.
    mapping(uint256 => mapping(uint256 => bool)) public stakedLootIdsByEpoch;

    /// @notice Track epochs a Loot is staked in. We remove epochs when rewards
    ///         are claimed.
    mapping(uint256 => uint256[]) public epochsByLootId;

    /// @notice Number of Loot staked in each epoch. Values are only incremented.
    mapping(uint256 => uint256) public numLootStakedByEpoch;

    // mLoot storage vars

    /// @notice mLoot IDs staked in each epoch. Epochs are 1-indexed.
    mapping(uint256 => mapping(uint256 => bool)) public stakedMLootIdsByEpoch;

    /// @notice Track epochs an mLoot is staked in. We remove epochs when
    ///         rewards are claimed.
    mapping(uint256 => uint256[]) public epochsByMLootId;

    /// @notice Number of mLoot staked in each epoch. Values are only incremented.
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
    /// @param _lootAddress Loot contract address.
    /// @param _mLootAddress mLoot contract address.
    /// @param _agldAddress Adventure Gold contract address.
    constructor(
        uint256 _numEpochs,
        uint256 _epochDuration,
        uint256 _lootWeight,
        uint256 _mLootWeight,
        address _lootAddress,
        address _mLootAddress,
        address _agldAddress
    ) {
        LOOT = SolmateERC721(_lootAddress);
        MLOOT = SolmateERC721(_mLootAddress);
        AGLD = SolmateERC20(_agldAddress);
        numEpochs = _numEpochs;
        epochDuration = _epochDuration;

        for (uint256 i = 1; i <= numEpochs;) {
            lootWeightsByEpoch[i] = _lootWeight;
            mLootWeightsByEpoch[i] = _mLootWeight;

            unchecked { ++i; }
        }
    }

    /*///////////////////////////////////////////////////////////////
                             ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets starting time for staking rewards. Must be at least 1 epoch
    ///         after the current time.
    /// @param _startTime The unix time to start staking rewards in seconds.
    function setStakingStartTime(uint256 _startTime) external onlyOwner {
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

        lootWeightsByEpoch[_epoch] = _lootWeight;
        mLootWeightsByEpoch[_epoch] = _mLootWeight;

        emit WeightsSet(_epoch, _lootWeight, _mLootWeight);
    }

    /// @notice Increase the internal balance of rewards. This should be called
    ///         after sending tokens to this contract.
    /// @param _amount The amount of rewards to increase.
    function notifyRewardAmount(uint256 _amount) external onlyOwner {
        if (stakingStartTime != 0) revert StakingAlreadyStarted();
        if (AGLD.balanceOf(address(this)) < _amount) revert RewardsNotReceived();

        // Proper ERC-20 implementation will cap total supply at uint256 max.
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
    function signalLootStake(uint256[] calldata _ids) external {
        _signalStake(_ids, LOOT, epochsByLootId, stakedLootIdsByEpoch, numLootStakedByEpoch);
    }

    /// @notice Stakes mLoot bags for upcoming epoch.
    /// @param _ids mLoot bags to stake.
    function signalMLootStake(uint256[] calldata _ids) external {
        _signalStake(_ids, MLOOT, epochsByMLootId, stakedMLootIdsByEpoch, numMLootStakedByEpoch);
    }

    /// @notice Stakes token IDs of a specific collection for the immediate next
    ///         epoch.
    /// @param _ids NFT token IDs to stake.
    /// @param _nftToken NFT collection being staked.
    /// @param epochsByNFTId Mapping of up-to-date epochs staked in by token ID.
    /// @param stakedNFTsByEpoch Mapping of staked NFT token IDs by epoch.
    /// @param numNFTsStakedByEpoch Mapping of number of staked NFT token IDs by epoch.
    function _signalStake(
        uint256[] calldata _ids,
        SolmateERC721 _nftToken,
        mapping(uint256 => uint256[]) storage epochsByNFTId,
        mapping(uint256 => mapping(uint256 => bool)) storage stakedNFTsByEpoch,
        mapping(uint256 => uint256) storage numNFTsStakedByEpoch
    ) internal {
        if (stakingStartTime == 0) revert StakingNotActive();
        uint256 currentEpoch = getCurrentEpoch();
        if (currentEpoch >= numEpochs) revert StakingEnded();

        uint256 signalEpoch = currentEpoch + 1;
        uint256 length = _ids.length;
        uint256 bagId;
        for (uint256 i = 0; i < length;) {
            bagId = _ids[i];
            if (_nftToken.ownerOf(bagId) != msg.sender) revert NotBagOwner();
            if (stakedNFTsByEpoch[signalEpoch][bagId]) revert BagAlreadyStaked();

            // Loot cannot overflow. mLoot unlikely to reach overflow limit.
            unchecked {
                // Increment staked count for epoch.
                ++numNFTsStakedByEpoch[signalEpoch];
            }

            // Mark NFT as staked for this epoch.
            stakedNFTsByEpoch[signalEpoch][bagId] = true;

            // Record epoch for this NFT.
            epochsByNFTId[bagId].push(signalEpoch);

            unchecked { ++i; }
        }

        if (_nftToken == LOOT) {
            emit LootBagsStaked(msg.sender, signalEpoch, _ids);
        } else {
            emit MLootBagsStaked(msg.sender, signalEpoch, _ids);
        }
    }

    /*///////////////////////////////////////////////////////////////
                             CLAIMING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims all staking rewards for specific Loot bags.
    /// @param _ids Loot bags to claim rewards for.
    function claimLootRewards(uint256[] calldata _ids) external {
        _claimRewards(_ids, LOOT, lootWeightsByEpoch, epochsByLootId, numLootStakedByEpoch);
    }

    /// @notice Claims all staking rewards for specific mLoot bags.
    /// @param _ids Loot bags to claim rewards for.
    function claimMLootRewards(uint256[] calldata _ids) external {
        _claimRewards(_ids, MLOOT, mLootWeightsByEpoch, epochsByMLootId, numMLootStakedByEpoch);
    }

    /// @notice Claims the rewards for token IDs of a specific collection.
    /// @dev    Would have liked to cache more values for looping but ran into
    ///         stack too deep error.
    /// @param _ids NFT token IDs to claim rewards for.
    /// @param _nftToken NFT collection being staked.
    /// @param nftWeights Mapping of NFT reward weights by epoch.
    /// @param epochsByNFTId Mapping of up-to-date epochs staked in by token ID.
    /// @param numNFTsStakedByEpoch Mapping of number of staked NFT token IDs by epoch.
    function _claimRewards(
        uint256[] calldata _ids,
        SolmateERC721 _nftToken,
        mapping(uint256 => uint256) storage nftWeights,
        mapping(uint256 => uint256[]) storage epochsByNFTId,
        mapping(uint256 => uint256) storage numNFTsStakedByEpoch
    ) internal {
        uint256 rewards;
        uint256 rewardPerEpoch = getTotalRewardPerEpoch();
        uint256 currentEpoch = getCurrentEpoch();

        uint256 bagId; // cache value
        uint256[] memory epochs; // cache value
        uint256 epochsLength; // cache value

        for (uint256 i = 0; i < _ids.length;) {
            bagId = _ids[i];
            if (_nftToken.ownerOf(bagId) != msg.sender) revert NotBagOwner();

            epochs = epochsByNFTId[bagId];
            epochsLength = epochs.length;

            if (epochsLength > 0) {
                for (uint256 j = 0; j < epochsLength;) {
                    if (epochs[j] < currentEpoch) {
                        // Proper ERC-20 implementation will cap total supply at uint256 max.
                        unchecked {
                            rewards += getRewardPerEpochPerBag(rewardPerEpoch, nftWeights[epochs[j]], numNFTsStakedByEpoch[epochs[j]]);
                        }
                    }

                    unchecked { ++j; }
                }

                // Clear epochs that the bag's rewards have been claimed for.
                if (epochs[epochsLength - 1] == currentEpoch) {
                    epochsByNFTId[bagId] = [currentEpoch];
                } else {
                    delete epochsByNFTId[bagId];
                }
            }

            unchecked { ++i; }
        }

        // Send rewards.
        AGLD.safeTransfer(msg.sender, rewards);

        if (_nftToken == LOOT) {
            emit LootRewardsClaimed(msg.sender, rewards, currentEpoch, _ids);
        } else {
            emit MLootRewardsClaimed(msg.sender, rewards, currentEpoch, _ids);
        }
    }

    /*///////////////////////////////////////////////////////////////
                             PUBLIC GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets the current epoch staking is in.
    /// @return currentEpoch The current epoch. 0 represents time before the first epoch.
    function getCurrentEpoch() public view returns (uint256 currentEpoch) {
        if (stakingStartTime == 0 || block.timestamp < stakingStartTime) return 0;
        currentEpoch = ((block.timestamp - stakingStartTime) / epochDuration) + 1;
    }

    /// @notice Gets the bag reward weights for an epoch.
    /// @param _epoch The epoch to get the weights for.
    /// @return lootWeight The weight for Loot bags in basis points.
    /// @return mLootWeight The weight for mLoot bags in basis points.
    function getWeightsForEpoch(
        uint256 _epoch
    ) public view returns (uint256 lootWeight, uint256 mLootWeight) {
        lootWeight = lootWeightsByEpoch[_epoch];
        mLootWeight = mLootWeightsByEpoch[_epoch];
    }

    /// @notice Gets the amount of rewards allotted per epoch.
    /// @dev The actual claimable amount may be off-by-1 due to rounding error.
    /// @return amount Amount of rewards per epoch.
    function getTotalRewardPerEpoch() public view returns (uint256 amount) {
        amount = rewardsAmount / numEpochs;
    }

    /// @notice Calculates the currently claimable rewards for a Loot bag.
    /// @dev Grab the epochs the bag was staked for and run calculation for each
    ///      epoch.
    /// @param _id The bag to calculate rewards for.
    /// @return rewards Claimable rewards for the bag.
    function getClaimableRewardsForLootBag(uint256 _id) external view returns (uint256 rewards) {
        rewards = _getClaimableRewardsForEpochs(lootWeightsByEpoch, epochsByLootId[_id], numLootStakedByEpoch);
    }

    /// @notice Calculates the currently claimable rewards for an mLoot bag.
    /// @dev Grab the epochs the bag was staked for and run calculation for each
    ///      epoch.
    /// @param _id The bag to calculate rewards for.
    /// @return rewards Claimable rewards for the bag.
    function getClaimableRewardsForMLootBag(uint256 _id) external view returns (uint256 rewards) {
        rewards = _getClaimableRewardsForEpochs(mLootWeightsByEpoch, epochsByMLootId[_id], numMLootStakedByEpoch);
    }

    /// @notice Gets the total rewards expected for Loot and mLoot for an epoch.
    /// @param _epoch The epoch to get the weights for.
    /// @return lootRewards The reward for Loot bags.
    /// @return mLootRewards The reward for mLoot bags.
    function getRewardsForEpoch(uint256 _epoch) public view returns (uint256 lootRewards, uint256 mLootRewards) {
        uint256 rewardPerEpoch = getTotalRewardPerEpoch();
        lootRewards = Math.mulDiv(rewardPerEpoch, lootWeightsByEpoch[_epoch], 1e4);
        mLootRewards = Math.mulDiv(rewardPerEpoch, mLootWeightsByEpoch[_epoch], 1e4);
    }

    /// @notice Calculates the reward given the epoch reward, reward rate, and
    ///         number of NFTs staked for the epoch.
    /// @param _epochReward Total reward for the epoch.
    /// @param _rewardWeight Reward rate for the NFT for the epoch.
    /// @param _numStakedNFTs Number of NFTs staked for the epoch.
    /// @return reward Reward for the bag.
    function getRewardPerEpochPerBag(
        uint256 _epochReward,
        uint256 _rewardWeight,
        uint256 _numStakedNFTs
    ) pure public returns(uint256 reward) {
        reward = Math.mulDiv(_epochReward, _rewardWeight, 1e4) / _numStakedNFTs;
    }

    /*///////////////////////////////////////////////////////////////
                             PRIVATE GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the currently claimable rewards for a bag that was
    ///         staked in a list of epochs. Only returns for valid epochs.
    /// @param nftWeights Mapping of NFT reward weights by epoch.
    /// @param _epochs The epochs the bag was staked in.
    /// @param numNFTsStakedByEpoch The number of NFTs staked in each epoch.
    function _getClaimableRewardsForEpochs(
        mapping(uint256 => uint256) storage nftWeights,
        uint256[] memory _epochs,
        mapping(uint256 => uint256) storage numNFTsStakedByEpoch
    ) internal view returns (uint256 rewards) {
        uint256 currentEpoch = getCurrentEpoch();
        uint256 rewardPerEpoch = getTotalRewardPerEpoch();
        uint256 epochsLength = _epochs.length;
        uint256 epoch;
        for (uint256 i = 0; i < epochsLength;) {
            epoch = _epochs[i];

            if (epoch < currentEpoch) {
                // Proper ERC-20 implementation will cap total supply at uint256 max.
                unchecked {
                    rewards += getRewardPerEpochPerBag(rewardPerEpoch, nftWeights[epoch], numNFTsStakedByEpoch[epoch]);
                }
            }

            unchecked { ++i; }
        }
    }
}
