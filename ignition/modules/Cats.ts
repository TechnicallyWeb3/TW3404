import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("Cats", (m) => {
  const cats = m.contract("ERC420", []);

  const result = m.staticCall(cats, "logBaseScale", ['1000000000000000000', 10]);
  console.log(result);

  return { cats };
});