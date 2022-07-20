import { BigNumber, Contract } from 'ethers'
import { expandTo18Decimals } from './utilities'
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { HardhatEthersHelpers } from '@nomiclabs/hardhat-ethers/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const hre: HardhatRuntimeEnvironment = require("hardhat");
const ethers: HardhatEthersHelpers = require("hardhat").ethers;

interface FactoryFixture {
  factory: Contract
}

const overrides = {
  gasLimit: 9999999
}

export async function deployFactory(feeToSetter: string): Promise<Contract> {
  const contractFactory = await ethers.getContractFactory('UniswapV2Factory');
  const contract = await contractFactory.deploy(feeToSetter);
  await contract.deployed();
  return contract;
}

export async function deployERC20(totalSupply: BigNumber): Promise<Contract> {
  const contractFactory = await ethers.getContractFactory('ERC20');
  const contract = await contractFactory.deploy(totalSupply);
  await contract.deployed();
  return contract;
}

export async function factoryFixture(wallet: SignerWithAddress): Promise<FactoryFixture> {
  const factory = await deployFactory(wallet.address)
  return { factory }
}

interface PairFixture extends FactoryFixture {
  token0: Contract
  token1: Contract
  pair: Contract
}

export async function pairFixture(wallet: SignerWithAddress): Promise<PairFixture> {
  const { factory } = await factoryFixture(wallet)

  const tokenA = await deployERC20(expandTo18Decimals(10000))
  const tokenB = await deployERC20(expandTo18Decimals(10000))

  await factory.createPair(tokenA.address, tokenB.address, overrides)
  const pairAddress = await factory.getPair(tokenA.address, tokenB.address)
  const pairArtifact = await hre.artifacts.readArtifact('UniswapV2Pair');
  const pair = new Contract(pairAddress, pairArtifact.abi, ethers.provider).connect(wallet)

  const token0Address = await pair.token0()
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  return { factory, token0, token1, pair }
}
