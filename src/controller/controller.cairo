use starknet::ContractAddress;
use rps_pvp::battle::{Battle};
#[starknet::interface]
pub trait IControllerFunctions<TContractState> {
    /// Submit move commitment.
    fn submit_move_commitment(ref self: TContractState, commitment: felt252, payoff: u256);
    /// Resolve battle.
    fn resolve_battle(ref self: TContractState, battle_id: u32, move: u8, secret: felt252);
    fn cancel_battle(ref self: TContractState, battle_id: u32);
    fn enter_battle(ref self: TContractState, battle_id: u32, move: u8);
}

#[starknet::interface]
pub trait IControllerViews<TContractState> {
    fn get_battle(self: @TContractState, battle_id: u32) -> Battle;
    fn get_winner(self: @TContractState, move_p1: u8, move_p2: u8) -> u8;
    fn get_battles_index(self: @TContractState) -> u32;
}

#[starknet::contract]
pub mod Controller {
    use starknet::storage::StorageMapReadAccess;
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address, get_block_info,
        contract_address_const
    };
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map
    };
    use core::array::ArrayTrait;
    use core::poseidon::poseidon_hash_span;
    use openzeppelin_token::erc20::interface::{IERC20, ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use rps_pvp::battle::{Battle};
    #[storage]
    struct Storage {
        battles_storage: Map::<u32, Battle>,
        battles_index_storage: u32,
        eth_address: ContractAddress,
        timeout_delay: u64
    }
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        BattleCreated: BattleCreated,
        BattleEntered: BattleEntered,
        BattleResolved: BattleResolved,
        BattleCancelled: BattleCancelled
    }

    #[derive(Drop, starknet::Event)]
    pub struct BattleCreated {
        #[key]
        pub battle_id: u32,
        pub owner: ContractAddress,
        pub payoff: u256
    }

    #[derive(Drop, starknet::Event)]
    pub struct BattleEntered {
        #[key]
        pub battle_id: u32,
        pub opponent: ContractAddress,
        pub move_: u8
    }

    #[derive(Drop, starknet::Event)]
    pub struct BattleResolved {
        #[key]
        pub battle_id: u32,
        pub winner: ContractAddress,
        pub payoff: u256
    }

    #[derive(Drop, starknet::Event)]
    pub struct BattleCancelled {
        #[key]
        pub battle_id: u32,
        pub owner: ContractAddress
    }

    pub const ERROR_INVALID_PAYOFF: felt252 = 'Invalid payoff amount';
    const ERROR_INSUFFICIENT_PAYOFF: felt252 = 'Insufficient payoff';
    const ERROR_ONLY_BATTLE_OWNER: felt252 = 'Only battle owner';
    const ERROR_ALREADY_STARTED: felt252 = 'Already started';
    const ERROR_INVALID_MOVE: felt252 = 'Invalid move';
    const ERROR_INVALID_COMMITMENT: felt252 = 'Invalid commitment';
    const ERROR_BATTLE_NOT_FOUND: felt252 = 'Battle does not exist';

    #[constructor]
    /// @notice Initializes the controller with the provided timeout delay and ETH address
    /// @param timeout_delay: timeout delay
    /// @param eth_address: ETH token address
    fn constructor(ref self: ContractState, timeout_delay: u64, eth_address: ContractAddress) {
        // Set the timeout delay
        self.timeout_delay.write(timeout_delay);
        // Set the ETH address for payoff
        self.eth_address.write(eth_address);
    }

    //
    // Views
    //
    #[abi(embed_v0)]
    impl ControllerViewsImpl of super::IControllerViews<ContractState> {
        fn get_battle(self: @ContractState, battle_id: u32) -> Battle {
            self.battles_storage.read(battle_id)
        }

        fn get_winner(self: @ContractState, move_p1: u8, move_p2: u8) -> u8 {
            // If moves are equal, it's a draw
            if move_p1 == move_p2 {
                return 0_u8;
            }

            // Rock = 1, Paper = 2, Scissors = 3
            // Check winning conditions for Player 1
            if ((move_p1 == 1_u8 && move_p2 == 3_u8)
                || // Rock beats Scissors
                 (move_p1 == 2_u8 && move_p2 == 1_u8)
                || // Paper beats Rock
                (move_p1 == 3_u8 && move_p2 == 2_u8) // Scissors beats Paper
                ) {
                return 1_u8; // Player 1 wins
            }

            // If not a draw and Player 1 didn't win, then Player 2 wins
            2_u8 // Player 2 wins
        }

        fn get_battles_index(self: @ContractState) -> u32 {
            self.battles_index_storage.read()
        }
    }

    #[abi(embed_v0)]
    impl ControllerFunctionsImpl of super::IControllerFunctions<ContractState> {
        fn submit_move_commitment(ref self: ContractState, commitment: felt252, payoff: u256) {
            assert(payoff > 0, ERROR_INVALID_PAYOFF);
            let caller = get_caller_address();
            let eth_token_dispatcher = ERC20ABIDispatcher {
                contract_address: self.eth_address.read()
            };
            // Check if the caller has sufficient balance
            let caller_balance = eth_token_dispatcher.balanceOf(caller);
            assert(!(caller_balance < payoff), ERROR_INSUFFICIENT_PAYOFF);
            eth_token_dispatcher.transferFrom(caller, get_contract_address(), payoff);
            let battle_id = self.battles_index_storage.read() + 1;
            self.battles_index_storage.write(battle_id);
            let battle = Battle {
                owner: caller,
                opponent: contract_address_const::<0>(),
                commitment: commitment,
                payoff: payoff,
                start_date: 0,
                opponent_move: 0
            };
            self.battles_storage.entry((battle_id)).write(battle);
            self.emit(Event::BattleCreated(BattleCreated { battle_id, owner: caller, payoff }));
        }

        fn cancel_battle(ref self: ContractState, battle_id: u32) {
            let caller = get_caller_address();
            let battle = self.battles_storage.read(battle_id);
            // Validate caller is battle owner
            assert(caller == battle.owner, ERROR_ONLY_BATTLE_OWNER);
            // Validate battle is still in open state
            assert(battle.start_date == 0, ERROR_ALREADY_STARTED);
            // Cache payoff before clearing storage
            let payoff = battle.payoff;
            // Clear battle storage
            self.battles_storage.entry((battle_id)).write(Default::default());
            let eth_token_dispatcher = ERC20ABIDispatcher {
                contract_address: self.eth_address.read()
            };
            // Process refund
            eth_token_dispatcher.transfer(caller, payoff);
            self.emit(Event::BattleCancelled(BattleCancelled { battle_id, owner: caller, }));
        }

        fn enter_battle(ref self: ContractState, battle_id: u32, move: u8) {
            // Validate move
            assert(move >= 1 && move <= 3, ERROR_INVALID_MOVE);
            let caller = get_caller_address();
            let battle = self.battles_storage.read(battle_id);
            // Validate battle exists and is in correct state
            assert(battle.start_date == 0, ERROR_ALREADY_STARTED);
            assert(battle.payoff != 0, ERROR_BATTLE_NOT_FOUND);
            let eth_token_dispatcher = ERC20ABIDispatcher {
                contract_address: self.eth_address.read()
            };
            // Check if the caller has sufficient balance
            let caller_balance = eth_token_dispatcher.balanceOf(caller);
            assert(!(caller_balance < battle.payoff), ERROR_INSUFFICIENT_PAYOFF);
            // Process payment
            eth_token_dispatcher.transferFrom(caller, get_contract_address(), battle.payoff);
            // Update battle state
            self
                .battles_storage
                .entry((battle_id))
                .write(
                    Battle {
                        owner: battle.owner,
                        opponent: caller,
                        commitment: battle.commitment,
                        payoff: battle.payoff,
                        start_date: get_block_info().unbox().block_timestamp,
                        opponent_move: move
                    }
                );
            // Emit event
            self
                .emit(
                    Event::BattleEntered(BattleEntered { battle_id, opponent: caller, move_: move })
                );
        }

        fn resolve_battle(ref self: ContractState, battle_id: u32, move: u8, secret: felt252) {
            let battle = self.battles_storage.read(battle_id);
            let eth_token_dispatcher = ERC20ABIDispatcher {
                contract_address: self.eth_address.read()
            };
            let opponent = battle.opponent;
            let payoff = battle.payoff;
            let owner = battle.owner;
            assert(payoff != 0, ERROR_BATTLE_NOT_FOUND);
            if (battle.start_date
                + self.timeout_delay.read() > get_block_info().unbox().block_timestamp) {
                // Opponent win without verifying moves
                self.battles_storage.entry((battle_id)).write(Default::default());
                eth_token_dispatcher.transfer(opponent, payoff * 2);
                self
                    .emit(
                        Event::BattleResolved(
                            BattleResolved {
                                battle_id: battle_id, winner: opponent, payoff: payoff * 2
                            }
                        )
                    )
            } else {
                assert(move >= 1 && move <= 3, ERROR_INVALID_MOVE);
                let move_: felt252 = move.into();
                let mut hash_data: Array<felt252> = ArrayTrait::new();
                Serde::serialize(@move_, ref hash_data);
                Serde::serialize(@secret, ref hash_data);
                let commitment = poseidon_hash_span(hash_data.span());
                assert(commitment == battle.commitment, ERROR_INVALID_COMMITMENT);
                let winner = self.get_winner(move, battle.opponent_move);
                self.battles_storage.entry((battle_id)).write(Default::default());
                // Handle payouts based on winner
                match winner {
                    0 => { // Draw - split the pot
                        let split_amount = payoff;
                        eth_token_dispatcher
                            .transfer( owner, split_amount);
                        eth_token_dispatcher
                            .transfer(opponent, split_amount);
                        self
                            .emit(
                                Event::BattleResolved(
                                    BattleResolved {
                                        battle_id: battle_id, winner: opponent, payoff: payoff
                                    }
                                )
                            );
                        self
                            .emit(
                                Event::BattleResolved(
                                    BattleResolved {
                                        battle_id: battle_id, winner: owner, payoff: payoff
                                    }
                                )
                            );
                    },
                    1 => { // Player 1 (caller) wins
                        eth_token_dispatcher
                            .transfer(owner, payoff * 2);
                        self
                            .emit(
                                Event::BattleResolved(
                                    BattleResolved {
                                        battle_id: battle_id, winner: owner, payoff: payoff * 2
                                    }
                                )
                            );
                    },
                    2 => { // Player 2 (opponent) wins
                        eth_token_dispatcher
                            .transfer(opponent, payoff * 2);
                        self
                            .emit(
                                Event::BattleResolved(
                                    BattleResolved {
                                        battle_id: battle_id, winner: opponent, payoff: payoff * 2
                                    }
                                )
                            );
                    },
                    _ => { panic!("Invalid winner result") }
                };
            }
        }
    }
}