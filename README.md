# Rock-Paper-Scissors-PvP Contracts

This repository contains the contracts used in Rock Paper Scissors PvP.

## Structure

### Contracts

- [**Controller**](src/controller/controller.cairo): The Controller contract is the entry point for the game. It handles creation, entry and resolution of battles

### Tests

The [tests](tests) directory contains the tests for all the contracts. The tests are written using [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/index.html), a testing framework for Cairo and Starknet contracts.

## 🛠️ Build

To build the project, run:

```bash
scarb build
```

## 🧪 Test

To test the project, you can run the tests using:

```bash
snforge test
```
