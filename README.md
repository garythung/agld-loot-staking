# AGLD staking rewards for Loot

🚨 This repo is still a work-in-progress. Comments, feedback, questions, etc. are welcomed and encouraged.

## What is this?

[Loot](https://etherscan.io/address/0xff9c1b15b16263c61d017ee9f65c50e4ae0113d7) and [mLoot](https://etherscan.io/address/0x1dfe7ca09e99d10835bf73044a23b73fc20623df) holders can stake their bags to earn [$AGLD](https://etherscan.io/token/0x32353a6c91143bfd6c7d363b546e62a9a2489a20) rewards.

Staking is non-custodial and requires a signal transaction before each epoch commences. Rewards for an epoch are claimable after the epoch elapses.

**Staking claims are tied to bags not owners.** If you transfer your bag that has been staked, the new owner may claim your rewards.

The total staking rewards is set to distribute evenly over each epoch. The share of rewards per epoch for Loot and mLoot is based on the ratio of their floor market caps to total Loot and mLoot floor market caps.

The admin is expected to update the weights for each upcoming epoch. In the case that that fails, every epoch weight has already been initialized to the first weights.

See [AGLD tokenomics discussion](https://loot-talk.com/t/adventure-gold-tokenomics-proposal-v1/1156) for exact details.

## How it works (staker)

You must signal your stake for the upcoming epoch during the current epoch. You cannot stake for the current epoch.

The diagram below illustrates the epoch timeline.
```
epoch 0 start = signal period for epoch 1 begins
epoch 1 start = stakingStartTime

0                 1                 2                 3
|-----------------|-----------------|-----------------|---
stake for 1
                  stake for 2
                                    stake for 3
```

1. For an upcoming epoch, signal your stake for your Loot or mLoot bags.
2. Once the epoch ends, you are entitled to claim your rewards for your bag. When you claim, you claim for all epochs you are entitled to.

## How it works (deployer)


1. Deploy the contract.
2. Send AGLD to the Staking contract.
3. From the owner account, call `notifyRewardAmount()` with the amount of AGLD sent (full number, not parsed number).

## Resources

- [Loot staking tweet chain](https://twitter.com/WillPapper/status/1467357820399980546)
- [AGLD tokenomics discussion](https://loot-talk.com/t/adventure-gold-tokenomics-proposal-v1/1156)
