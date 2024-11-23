use starknet::{ContractAddress, contract_address_const};

/// Represents a battle
#[derive(Copy, Drop, starknet::Store, Serde, Default)]
pub struct Battle {
    pub owner: ContractAddress, // Owner of the battle
    pub opponent: ContractAddress,
    pub commitment: felt252,
    pub payoff: u256,
    pub start_date: u64,
    pub opponent_move: u8, //1 = Rock, 2 = Paper, 3 = Scissors
}

impl BattleIntoSpan of Into<Battle, Span<felt252>> {
    fn into(self: Battle) -> Span<felt252> {
        let mut serialized_struct: Array<felt252> = array![];
        self.serialize(ref serialized_struct);
        serialized_struct.span()
    }
}

/// Implements the Default trait for ContractAddress
impl ContractAddressDefault of Default<ContractAddress> {
    /// Returns the default value for ContractAddress (address 0)
    #[inline(always)]
    fn default() -> ContractAddress {
        contract_address_const::<0>()
    }
}
