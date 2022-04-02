import ethers from "ethers";
import { wallet, deployContract } from "./helpers.js";

import AGLDArtifact from "../out/AdventureGold.sol/AdventureGold.json" assert { type: "json" };
import MLootArtifact from "../out/MLoot.sol/TemporalLoot.json" assert { type: "json" };
import LootArtifact from "../out/Loot.sol/Loot.json" assert { type: "json" };
import LootStakingArtifact from "../out/LootStaking.sol/LootStaking.json" assert { type: "json" };

import DEPLOYMENTS from "../deployments.json" assert { type: "json" };

const deployLoot = async () => {
  const Factory = new ethers.ContractFactory(
    LootArtifact.abi,
    LootArtifact.bytecode.object,
    wallet
  );

  return await deployContract({
    name: "Loot",
    deployer: wallet,
    factory: Factory,
    args: [],
    opts: {
      gasLimit: 1000000,
    },
  });
};

const deployMLoot = async () => {
  const Factory = new ethers.ContractFactory(
    MLootArtifact.abi,
    MLootArtifact.bytecode.object,
    wallet
  );

  return await deployContract({
    name: "More Loot",
    deployer: wallet,
    factory: Factory,
    args: [],
    opts: {
      gasLimit: 1000000,
    },
  });
};

const deployAGLD = async () => {
  const Factory = new ethers.ContractFactory(
    AGLDArtifact.abi,
    AGLDArtifact.bytecode.object,
    wallet
  );

  return await deployContract({
    name: "Adventure Gold",
    deployer: wallet,
    factory: Factory,
    args: [],
    opts: {
      gasLimit: 1000000,
    },
  });
};

const deployStaking = async () => {
  const Factory = new ethers.ContractFactory(
    LootStakingArtifact.abi,
    LootStakingArtifact.bytecode.object,
    wallet
  );

  // num epochs: 288
  // epoch duration: 600 seconds = 10 min
  // 288 * 10 = 2880 minutes => 2 days
  // loot weight: 99.75%
  // mloot weight: 0.25%

  // 10 minute epoch duration for 2 days

  return await deployContract({
    name: "LootStaking",
    deployer: wallet,
    factory: Factory,
    args: [
      288,
      600,
      9975,
      25,
      DEPLOYMENTS.rinkeby.loot,
      DEPLOYMENTS.rinkeby.mLoot,
      DEPLOYMENTS.rinkeby.AGLD,
    ],
    opts: {
      gasLimit: 1000000,
    },
  });
};

const initializeStaking = async (stakingAddr) => {
  const staking = new ethers.Contract(
    stakingAddr,
    LootStakingArtifact.abi,
    wallet
  );
  const agld = new ethers.Contract(
    "0xf02b847FF664072c0241AA8dB32998Bbc51Bd984",
    AGLDArtifact.abi,
    wallet
  );

  // send AGLD
  await agld.transfer(stakingAddr, ethers.utils.parseUnits("100000", 18));
  console.log("Sent 100000 AGLD to staking contract");

  // notify AGLD received
  await staking.notifyRewardAmount(ethers.utils.parseUnits("100000", 18));
  console.log("Notified 100000 AGLD reward");

  // set staking start
  const startTimeUnixSeconds = parseInt(Date.now() / 1000) + 900;
  await staking.setStakingStartTime(startTimeUnixSeconds, {
    gasLimit: 1000000,
  });
  console.log(
    `Set staking start time to ${new Date(
      startTimeUnixSeconds * 1000
    ).toString()}`
  );
};

const main = async () => {
  // const loot = await deployLoot();
  // const mLoot = await deployMLoot();
  // const agld = await deployAGLD();
  const staking = await deployStaking();
  await initializeStaking(staking.address);
  // await initializeStaking("0x3380B98Da3Ca8515994BB3A279d60C554F11dD17");
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
