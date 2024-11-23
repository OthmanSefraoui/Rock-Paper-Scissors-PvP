# Rock-Paper-Scissors-PvP Contracts

This repository contains the contracts used in Rock Paper Scissors PvP.

## Structure

## Smart Contract Overview: Controller

The Controller smart contract is designed for a Rock-Paper-Scissors (RPS) game on the StarkNet blockchain. It facilitates the creation, management, and resolution of battles between players, ensuring that the game mechanics are enforced securely and transparently.

### Key Components:

1. Interfaces:
   1. IControllerFunctions: Defines the functions that allow players to interact with the contract, such as submitting moves, resolving battles, and canceling battles.
   2. IControllerViews: Provides read-only functions to retrieve battle information and determine the winner based on the moves played.
2. Storage Structure:
   1. battles_storage: A mapping of battle IDs to their corresponding Battle structs, which hold details about each battle.
   2. battles_index_storage: A counter for generating unique battle IDs.
   3. eth_address: The address of the ETH token contract used for handling payoffs.
   4.timeout_delay: The time allowed for a player to reveal their move before they automatically lose.
3. Events:
   The contract emits events to notify external observers about significant actions, such as battle creation, entry, resolution, and cancellation. This allows for better tracking and transparency of game activities.
4. Constructor:
   The constructor initializes the contract with a specified timeout delay and the ETH token address, setting up the necessary parameters for the game.
5. Game Logic:
   Players can create battles by submitting a move commitment along with a payoff amount. The contract checks if the player has sufficient balance and then creates a new battle.
   Players can enter existing battles by submitting their move and matching the payoff. The contract ensures that the battle is still open and that the player has enough funds.
   The contract resolves battles based on the moves submitted by both players. It checks for timeout conditions, validates moves, and determines the winner according to the game rules (Rock beats Scissors, Scissors beats Paper, Paper beats Rock).
   In the event of a draw, the payoff is split between the players.
6. Error Handling:
   The contract includes various error messages to handle invalid operations, such as insufficient payoffs, invalid moves, and attempts to cancel battles that have already started.
   
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
