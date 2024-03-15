import {
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

const testValue = 0;
const testBase = 10;

describe("String", function () {

  async function deployCats() {
      const Cats = await ethers.getContractFactory("ERC420");
      const cats = await Cats.deploy("A", "A", "A", 10);

      return cats;

  }

  describe("Deployment", function () {
      it("Log result", async function () {
          const cats = await loadFixture(deployCats);
          console.log("Deployed")

          let tx = await cats.logBaseScale(testValue, testBase);
          console.log(tx);

          

      });

  });
  
});