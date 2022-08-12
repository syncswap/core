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
  const contractFactory = await ethers.getContractFactory('SyncSwapFactory');
  const contract = await contractFactory.deploy(feeToSetter);
  await contract.deployed();
  return contract;
}

export async function deployPairERC20(totalSupply: BigNumber): Promise<Contract> {
  const contractFactory = await ethers.getContractFactory('PairERC20');
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

  const tokenA = await deployPairERC20(expandTo18Decimals(10000))
  const tokenB = await deployPairERC20(expandTo18Decimals(10000))

  await factory.createPair(tokenA.address, tokenB.address, overrides)
  const pairAddress = await factory.getPair(tokenA.address, tokenB.address)
  const pairArtifact = await hre.artifacts.readArtifact('SyncSwapPair');
  const pair = new Contract(pairAddress, pairArtifact.abi, ethers.provider).connect(wallet)

  const token0Address = await pair.token0()
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  return { factory, token0, token1, pair }
}

interface V2Fixture {
  token0: Contract
  token1: Contract
  WETH: Contract
  WETHPartner: Contract
  factory: Contract
  router: Contract
  routerEventEmitter: Contract
  pair: Contract
  WETHPair: Contract
}

export async function deployERC20(totalSupply: BigNumber): Promise<Contract> {
  const contractFactory = await ethers.getContractFactory('ERC20');
  const contract = await contractFactory.deploy(totalSupply);
  await contract.deployed();
  return contract;
}

export async function deployDeflatingERC20(totalSupply: BigNumber): Promise<Contract> {
  const contractFactory = await ethers.getContractFactory('DeflatingERC20');
  const contract = await contractFactory.deploy(totalSupply);
  await contract.deployed();
  return contract;
}

export async function deployWETH9(): Promise<Contract> {
  const contractFactory = await ethers.getContractFactory('WETH9');
  const contract = await contractFactory.deploy();
  await contract.deployed();
  return contract;
}

export async function deployRouter(factory: string, WETH: string): Promise<Contract> {
  const contractFactory = await ethers.getContractFactory('SyncSwapRouter');
  const contract = await contractFactory.deploy(factory, WETH);
  await contract.deployed();
  return contract;
}

export async function deployRouterEventEmitter(factory: string, WETH: string): Promise<Contract> {
  const contractFactory = await ethers.getContractFactory('RouterEventEmitter');
  const contract = await contractFactory.deploy(factory, WETH);
  await contract.deployed();
  return contract;
}

export async function v2Fixture(): Promise<V2Fixture> {
  const accounts = await ethers.getSigners()
  const wallet = accounts[0];

  // deploy tokens
  const tokenA = await deployERC20(expandTo18Decimals(10000))
  const tokenB = await deployERC20(expandTo18Decimals(10000))
  const WETH = await deployWETH9()
  const WETHPartner = await deployERC20(expandTo18Decimals(10000))

  // deploy V2
  const factory = await deployFactory(wallet.address)

  // deploy routers
  const router = await deployRouter(factory.address, WETH.address)

  // event emitter for testing
  const routerEventEmitter = await deployRouterEventEmitter(factory.address, WETH.address)

  // initialize V2
  await factory.createPair(tokenA.address, tokenB.address)
  const pairAddress = await factory.getPair(tokenA.address, tokenB.address)
  const pairArtifact = await hre.artifacts.readArtifact('SyncSwapPair');
  const pair = new Contract(pairAddress, pairArtifact.abi, ethers.provider).connect(wallet)

  const token0Address = await pair.token0()
  const token0 = tokenA.address.toLowerCase() === token0Address.toLowerCase() ? tokenA : tokenB
  const token1 = tokenA.address.toLowerCase() === token0Address.toLowerCase() ? tokenB : tokenA

  await factory.createPair(WETH.address, WETHPartner.address)
  const WETHPairAddress = await factory.getPair(WETH.address, WETHPartner.address)
  const WETHPair = new Contract(WETHPairAddress, pairArtifact.abi, ethers.provider).connect(wallet)

  return {
    token0,
    token1,
    WETH,
    WETHPartner,
    factory,
    router,
    routerEventEmitter,
    pair,
    WETHPair
  }
}