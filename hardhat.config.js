// Compiler settings are published verbatim so that anyone can reproduce the
// deployed bytecode exactly:
//   - solc 0.8.24
//   - viaIR enabled
//   - optimizer enabled with 1 run
//   - metadata hash disabled (bytecodeHash: "none")
// Any change to these settings (or to the source bytes) will produce a
// different bytecode than the one deployed on-chain.
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 1,
      },
      metadata: {
        bytecodeHash: "none",
      },
    },
  },
};
