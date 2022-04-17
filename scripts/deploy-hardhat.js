require("dotenv").config();
const hre = require("hardhat");

const AGLDArtifact = require("../out/AdventureGold.sol/AdventureGold.json");
const MLootArtifact = require("../out/MLoot.sol/TemporalLoot.json");
const LootArtifact = require("../out/Loot.sol/Loot.json");
const LootStakingArtifact = require("../out/LootStaking.sol/LootStaking.json");

const DEPLOYMENTS = require("../deployments.json");

const provider = new hre.ethers.providers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new hre.ethers.Wallet(process.env.PRIVATE_KEY, provider);

const getStakingContract = (address) =>
  new hre.ethers.Contract(address, LootStakingArtifact.abi, wallet);

const AGLD = new hre.ethers.Contract(
  "0xf02b847FF664072c0241AA8dB32998Bbc51Bd984",
  AGLDArtifact.abi,
  wallet
);
const AGLD_AMOUNT = 100000;

const deployStaking = async () => {
  const LootStaking = await hre.ethers.getContractFactory("LootStaking");
  console.log("Deploying LootStaking...");
  const staking = await LootStaking.connect(wallet).deploy(
    288,
    600,
    9975,
    25,
    DEPLOYMENTS.rinkeby.loot,
    DEPLOYMENTS.rinkeby.mLoot,
    DEPLOYMENTS.rinkeby.AGLD
  );
  await staking.deployed();
  console.log("Staking deployed to:", staking.address);
  return staking;
};

const sendAGLD = async (stakingAddr) => {
  await AGLD.transfer(
    stakingAddr,
    hre.ethers.utils.parseUnits(`${AGLD_AMOUNT}`, 18),
    {
      gasLimit: 1000000,
    }
  );
  console.log(`Sent ${AGLD_AMOUNT} AGLD to staking contract`);
};

const notifyAGLD = async (stakingAddr) => {
  const staking = getStakingContract(stakingAddr);

  await staking.notifyRewardAmount(
    hre.ethers.utils.parseUnits(`${AGLD_AMOUNT}`, 18),
    {
      gasLimit: 1000000,
    }
  );
  console.log(`Notified ${AGLD_AMOUNT} AGLD reward`);
};

const setStartTime = async (stakingAddr) => {
  const staking = getStakingContract(stakingAddr);

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

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  const staking = await deployStaking();
  await sendAGLD(staking.address);
  await notifyAGLD(staking.address);
  await setStartTime(staking.address);
  // await initializeStaking("0xCB23cAc357aa3395321cbF90eD0Cf4573a35682A");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
