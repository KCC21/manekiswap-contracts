import { ethers, upgrades } from "hardhat";
import { ManekiToken } from "../src/typechain";

import { expect, use } from "chai";
import { BN, expectEvent, expectRevert } from "@openzeppelin/test-helpers";
import { accounts, contract } from "@openzeppelin/test-environment";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "@ethersproject/bignumber";

describe("Token", async function () {
  let token: ManekiToken;
  let owner: SignerWithAddress;
  let admin: SignerWithAddress;
  let user: SignerWithAddress;
  let miner: SignerWithAddress;
  let burner: SignerWithAddress;

  beforeEach(async function () {
    [owner, admin, user, miner, burner] = await ethers.getSigners();
    let factory = (await ethers.getContractFactory("ManekiToken"));
    let cap = ethers.utils.parseEther('30000000');
    token = await upgrades.deployProxy(factory, [cap], { initializer: 'initialize(uint256 cap_)' }) as ManekiToken;
    await token.deployed();
  });

  it("Can not mint more than cap", async function () {
    let mintValue = ethers.utils.parseEther('31000000');
    expectRevert(
      token.mint(burner.address, mintValue),
      'ERC20Capped: cap exceeded'
    );
  });

  it("miner to burner 100 token", async function () {
    let mintValue = ethers.utils.parseEther('100');
    await token.mint(burner.address, mintValue);
    let burnerBalance = await token.balanceOf(burner.address);
    expect(burnerBalance.eq(mintValue), "Equal mint value").true;
  })

  it("burner can burn 90 token", async function () {
    let mintValue = ethers.utils.parseEther('100');
    await token.mint(burner.address, mintValue);


    let burnerContract = token.connect(burner);
    await burnerContract.burn(ethers.utils.parseEther('90'));

    let burnerBalance = await token.balanceOf(burner.address);
    expect(burnerBalance.eq(ethers.utils.parseEther('10')), "Equal mint value").true;
  })
});