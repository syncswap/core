import chai, { expect } from 'chai'
import { BigNumber, Contract } from 'ethers'
import { solidity } from 'ethereum-waffle'
import { expandTo18Decimals, getCreate2Address } from './shared/utilities'
import { deployERC20, factoryFixture } from './shared/fixtures'
import { zeroAddress } from 'ethereumjs-util'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

const hre: HardhatRuntimeEnvironment = require('hardhat');
const ethers = require("hardhat").ethers;

chai.use(solidity)

/*
const TEST_ADDRESSES: [string, string] = [
  '0x1000000000000000000000000000000000000000',
  '0x2000000000000000000000000000000000000000'
]
*/

describe('SyncSwapFactory', () => {
  let wallet: SignerWithAddress
  let other: SignerWithAddress
  let TEST_ADDRESSES: [string, string] = ['', '']
  before(async () => {
    const accounts = await ethers.getSigners();
    wallet = accounts[0]
    other = accounts[1]
    TEST_ADDRESSES[0] = (await deployERC20(expandTo18Decimals(10000))).address;
    TEST_ADDRESSES[1] = (await deployERC20(expandTo18Decimals(10000))).address;
  })

  let factory: Contract
  beforeEach(async () => {
    const accounts = await ethers.getSigners();
    const fixture = await factoryFixture(accounts[0]);
    factory = fixture.factory
  })

  /*
  it('INIT_CODE_PAIR_HASH', async () => {
    expect(await factory.INIT_CODE_PAIR_HASH()).to.eq('0x0a44d25bd998b8cce3bec356e00044787b55feabe1b89cb62eba44ef25855128')
  })
  */

  it('feeTo, feeToSetter, allPairsLength', async () => {
    expect(await factory.feeTo()).to.eq(zeroAddress())
    expect(await factory.feeToSetter()).to.eq(wallet.address)
    expect(await factory.allPairsLength()).to.eq(0)
  })

  async function createPair(tokens: [string, string]) {
    const pairArtifact = await hre.artifacts.readArtifact('SyncSwapPair');
    const create2Address = getCreate2Address(factory.address, tokens, pairArtifact.bytecode)
    const [token0, token1] = Number(TEST_ADDRESSES[0]) < Number(TEST_ADDRESSES[1]) ? TEST_ADDRESSES : [TEST_ADDRESSES[1], TEST_ADDRESSES[0]];
    await expect(factory.createPair(...tokens))
      .to.emit(factory, 'PairCreated')
      .withArgs(token0, token1, create2Address, BigNumber.from(1))

    await expect(factory.createPair(...tokens)).to.be.reverted // UniswapV2: PAIR_EXISTS
    await expect(factory.createPair(...tokens.slice().reverse())).to.be.reverted // UniswapV2: PAIR_EXISTS
    expect(await factory.getPair(...tokens)).to.eq(create2Address)
    expect(await factory.getPair(...tokens.slice().reverse())).to.eq(create2Address)
    expect(await factory.allPairs(0)).to.eq(create2Address)
    expect(await factory.allPairsLength()).to.eq(1)

    const pair = new Contract(create2Address, pairArtifact.abi, ethers.provider)
    expect(await pair.factory()).to.eq(factory.address)
    expect(await pair.token0()).to.eq(token0)
    expect(await pair.token1()).to.eq(token1)
  }

  it('createPair', async () => {
    await createPair(TEST_ADDRESSES)
  })

  it('createPair:reverse', async () => {
    await createPair(TEST_ADDRESSES.slice().reverse() as [string, string])
  })

  it('createPair:gas', async () => {
    const tx = await factory.createPair(...TEST_ADDRESSES)
    const receipt = await tx.wait()
    expect(receipt.gasUsed).to.eq(3738730)
  })

  it('setFeeTo', async () => {
    await expect(factory.connect(other).setFeeTo(other.address)).to.be.revertedWith('F')
    await factory.setFeeTo(wallet.address)
    expect(await factory.feeTo()).to.eq(wallet.address)
  })

  it('setFeeToSetter', async () => {
    await expect(factory.connect(other).setFeeToSetter(other.address)).to.be.revertedWith('F')
    await factory.setFeeToSetter(other.address)
    expect(await factory.feeToSetter()).to.eq(other.address)
    await expect(factory.setFeeToSetter(wallet.address)).to.be.revertedWith('F')
  })
})
