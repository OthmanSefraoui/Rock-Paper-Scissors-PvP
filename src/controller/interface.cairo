use starknet::ContractAddress;
use rps_pvp::battle::{Battle};

#[starknet::interface]
pub trait IController<TContractState> {
    ///Externals
    /// Submit move commitment.
    fn submit_move_commitment(ref self: TContractState, commitment: felt252, payoff: u256);
    /// Resolve battle.
    fn resolve_battle(ref self: TContractState, battle_id: u32, move: u8, secret: felt252);
    fn cancel_battle(ref self: TContractState, battle_id: u32);
    fn enter_battle(ref self: TContractState, battle_id: u32, move: u8);
    /// Views
    fn get_battle(self: @TContractState, battle_id: u32) -> Battle;
    fn get_winner(self: @TContractState, move_p1: u8, move_p2: u8) -> u8;
    fn get_battles_index(self: @TContractState) -> u32;
}
