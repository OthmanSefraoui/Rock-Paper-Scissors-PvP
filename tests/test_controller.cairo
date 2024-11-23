use openzeppelin_token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use starknet::{ContractAddress, contract_address_const};
use snforge_std::{
    declare, ContractClassTrait, start_cheat_caller_address, EventSpy, ContractClass, CheatSpan,
    DeclareResultTrait, stop_cheat_caller_address, spy_events, EventSpyAssertionsTrait, store, load,
    map_entry_address, start_cheat_block_timestamp, stop_cheat_block_timestamp
};
use rps_pvp::controller::interface::IControllerDispatcher;
use rps_pvp::controller::interface::IControllerDispatcherTrait;
use rps_pvp::controller::controller::Controller;
use rps_pvp::battle::Battle;
fn deploy_eth() -> (ERC20ABIDispatcher, ContractAddress) {
    deploy_eth_with_owner()
}

fn deploy_eth_with_owner() -> (ERC20ABIDispatcher, ContractAddress) {
    let token = declare("ERC20").unwrap().contract_class();
    let mut calldata = ArrayTrait::new();
    let recipient = contract_address_const::<'recipient'>();
    calldata.append(100000000000000000000);
    calldata.append(0);
    calldata.append(recipient.into());
    let (address, _) = token.deploy(@calldata).unwrap();
    let dispatcher = ERC20ABIDispatcher { contract_address: address, };
    (dispatcher, address)
}

// @returns (controller, eth)
fn setup() -> (IControllerDispatcher, ERC20ABIDispatcher,) {
    let (eth, eth_address) = deploy_eth();

    let mut controller_calldata = ArrayTrait::new();
    controller_calldata.append(12000_u64.into());
    controller_calldata.append(eth_address.into());
    let controller = declare("Controller").unwrap().contract_class();
    let (controller_address, _) = controller.deploy(@controller_calldata).unwrap();
    let controller = IControllerDispatcher { contract_address: controller_address };

    (controller, eth)
}

#[test]
fn test_submit_move_commitment() {
    // Set up the environment with a controller and ETH
    let (controller, eth) = setup();
    // Define the recipient and player addresses
    let recipient = contract_address_const::<'recipient'>();
    let player = contract_address_const::<'player'>();
    // Set the payoff amount and commitment
    let payoff_amount: u256 = 5500000000000000000;
    let commitment = 1416164405029674324331909544155980085306730986792554086473471855678221018328;
    let old_index = controller.get_battles_index();
    // Start cheating with the ETH contract address as the caller and the recipient as the address
    start_cheat_caller_address(eth.contract_address, recipient);
    // Transfer the payoff amount to the player
    eth.transfer(player, payoff_amount);
    stop_cheat_caller_address(eth.contract_address);
    // Start cheating with the ETH contract address as the caller and the player as the address
    start_cheat_caller_address(eth.contract_address, player);
    // Get the player's old balance
    let player_old_balance = eth.balanceOf(player);
    // Approve the controller to spend the payoff amount
    eth.approve(controller.contract_address, payoff_amount);
    stop_cheat_caller_address(eth.contract_address);
    // Start cheating with the controller contract address as the caller and the player as the
    // address
    start_cheat_caller_address(controller.contract_address, player);
    // Spy on events
    let mut spy = spy_events();
    // Submit the move commitment
    controller.submit_move_commitment(commitment, payoff_amount);
    stop_cheat_caller_address(controller.contract_address);
    // Get the battle details
    let battle = controller.get_battle(1);
    // Assert the battle details are correct
    assert(battle.owner == player, 'Invalid owner');
    assert(battle.payoff == payoff_amount, 'Invalid payoff');
    assert(battle.commitment == commitment, 'Invalid commitment');
    assert(battle.start_date == 0, 'Invalid start date');
    assert(battle.opponent == contract_address_const::<0>(), 'Invalid opponent');
    assert(battle.opponent_move == 0, 'Invalid opponent move');
    // Assert the battle index is incremented correctly
    assert(controller.get_battles_index() == 1 + old_index, 'Invalid index');
    // Expect the BattleCreated event to be emitted
    spy
        .assert_emitted(
            @array![
                (
                    controller.contract_address,
                    Controller::Event::BattleCreated(
                        Controller::BattleCreated {
                            battle_id: 1, owner: player, payoff: payoff_amount
                        }
                    )
                )
            ]
        );
}

#[test]
#[should_panic(expected: 'Invalid payoff amount')]
fn test_cannot_submit_zero_payoff() {
    // Set up the environment with a controller and ETH
    let (controller, eth) = setup();
    // Define the player address
    let player = contract_address_const::<'player'>();
    // Set the commitment
    let commitment = 1416164405029674324331909544155980085306730986792554086473471855678221018328;

    // Start cheating with the controller contract address as the caller and the player as the
    // address
    start_cheat_caller_address(controller.contract_address, player);

    // Try to submit with zero payoff, which should panic
    controller.submit_move_commitment(commitment, 0);
}

#[test]
#[should_panic(expected: 'Insufficient payoff')]
fn test_cannot_submit_without_sufficient_balance() {
    // Set up the environment with a controller and ETH
    let (controller, eth) = setup();
    // Define the player address
    let player = contract_address_const::<'player'>();
    // Set the payoff amount and commitment
    let payoff_amount: u256 = 5500000000000000000;
    let commitment = 1416164405029674324331909544155980085306730986792554086473471855678221018328;

    // Start cheating with the controller contract address as the caller and the player as the
    // address
    start_cheat_caller_address(controller.contract_address, player);

    // Don't transfer any tokens to the player
    // Try to submit without sufficient balance, which should panic
    controller.submit_move_commitment(commitment, payoff_amount);
}

#[test]
#[should_panic(expected: 'ERC20: insufficient balance')]
fn test_cannot_submit_without_approval() {
    // Set up the environment with a controller and ETH
    let (controller, eth) = setup();
    // Define the player address
    let player = contract_address_const::<'player'>();
    // Set the payoff amount and commitment
    let payoff_amount: u256 = 5500000000000000000;
    let commitment = 1416164405029674324331909544155980085306730986792554086473471855678221018328;

    // Transfer tokens to the player but don't approve the controller to spend them
    start_cheat_caller_address(eth.contract_address, player);
    eth.transfer(player, payoff_amount);
    stop_cheat_caller_address(eth.contract_address);

    // Start cheating with the controller contract address as the caller and the player as the
    // address
    start_cheat_caller_address(controller.contract_address, player);

    // Try to submit without approval, which should panic
    controller.submit_move_commitment(commitment, payoff_amount);
}

#[test]
fn test_cancel_battle_success() {
    // Setup
    let (controller, eth) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let player = contract_address_const::<'player'>();
    let payoff_amount: u256 = 5500000000000000000;
    let commitment = 1416164405029674324331909544155980085306730986792554086473471855678221018328;

    // Create a battle first
    // Start cheating with the ETH contract address as the caller and the recipient as the address
    start_cheat_caller_address(eth.contract_address, recipient);
    // Transfer the payoff amount to the player
    eth.transfer(player, payoff_amount);
    stop_cheat_caller_address(eth.contract_address);
    start_cheat_caller_address(eth.contract_address, player);
    eth.approve(controller.contract_address, payoff_amount);
    stop_cheat_caller_address(eth.contract_address);
    start_cheat_caller_address(controller.contract_address, player);
    controller.submit_move_commitment(commitment, payoff_amount);
    // Store initial balance
    let initial_balance = eth.balanceOf(player);
    // Spy on events
    let mut spy = spy_events();
    // Cancel the battle
    controller.cancel_battle(1);
    stop_cheat_caller_address(controller.contract_address);

    // Verify battle was cleared
    let battle = controller.get_battle(1);
    assert(battle.payoff == 0, 'Battle not cleared');
    assert(battle.owner == contract_address_const::<0>(), 'Owner not cleared');
    assert(battle.commitment == 0, 'Commitment not cleared');
    // Verify refund
    let final_balance = eth.balanceOf(player);
    assert(final_balance == initial_balance + payoff_amount, 'Refund not processed');
    // Expect the BattleCancelled event to be emitted
    spy
        .assert_emitted(
            @array![
                (
                    controller.contract_address,
                    Controller::Event::BattleCancelled(
                        Controller::BattleCancelled { battle_id: 1, owner: player }
                    )
                )
            ]
        );
}

#[test]
#[should_panic(expected: 'Only battle owner')]
fn test_cannot_cancel_others_battle() {
    // Setup
    let (controller, eth) = setup();
    let player = contract_address_const::<'player'>();
    let other_player = contract_address_const::<'other_player'>();
    let payoff_amount: u256 = 5500000000000000000;
    let commitment = 1416164405029674324331909544155980085306730986792554086473471855678221018328;
    let recipient = contract_address_const::<'recipient'>();
    // Create a mock battle
    let mocked_battle = Battle {
        owner: player,
        opponent: contract_address_const::<0>(),
        commitment: commitment,
        payoff: payoff_amount,
        start_date: 0,
        opponent_move: 0
    };
    store(
        controller.contract_address,
        map_entry_address(
            selector!("battles_storage"), // Providing variable name
            array![1].span(), // Providing mapping key
        ),
        mocked_battle.into()
    );

    // Try to cancel with different address
    start_cheat_caller_address(controller.contract_address, other_player);
    controller.cancel_battle(1);
}

#[test]
#[should_panic(expected: 'Already started')]
fn test_cannot_cancel_started_battle() {
    // Setup
    let (controller, eth) = setup();
    let player = contract_address_const::<'player'>();
    let opponent = contract_address_const::<'opponent'>();
    let payoff_amount: u256 = 5500000000000000000;
    let commitment = 1416164405029674324331909544155980085306730986792554086473471855678221018328;

    // Mock battle
    let mocked_battle = Battle {
        owner: player,
        opponent: contract_address_const::<'player2'>(),
        commitment: commitment,
        payoff: payoff_amount,
        start_date: 111111,
        opponent_move: 1
    };
    store(
        controller.contract_address,
        map_entry_address(
            selector!("battles_storage"), // Providing variable name
            array![1].span(), // Providing mapping key
        ),
        mocked_battle.into()
    );

    // Try to cancel after battle started
    start_cheat_caller_address(controller.contract_address, player);
    controller.cancel_battle(1);
}

#[test]
fn test_enter_battle_success() {
    let (controller, eth) = setup();
    let player = contract_address_const::<'player'>();
    let opponent = contract_address_const::<'opponent'>();
    let payoff_amount: u256 = 5500000000000000000;
    let commitment = 1416164405029674324331909544155980085306730986792554086473471855678221018328;
    let recipient = contract_address_const::<'recipient'>();
    // Mock initial battle
    let mocked_battle = Battle {
        owner: player,
        opponent: contract_address_const::<0>(),
        commitment: commitment,
        payoff: payoff_amount,
        start_date: 0,
        opponent_move: 0
    };
    store(
        controller.contract_address,
        map_entry_address(selector!("battles_storage"), array![1].span(),),
        mocked_battle.into()
    );

    // Setup opponent
    start_cheat_caller_address(eth.contract_address, recipient);
    eth.transfer(opponent, payoff_amount);
    stop_cheat_caller_address(eth.contract_address);
    start_cheat_caller_address(eth.contract_address, opponent);
    eth.approve(controller.contract_address, payoff_amount);
    stop_cheat_caller_address(eth.contract_address);

    let timestamp = 1234567;
    start_cheat_block_timestamp(controller.contract_address, timestamp);

    // Enter battle
    start_cheat_caller_address(controller.contract_address, opponent);
    let mut spy = spy_events();
    controller.enter_battle(1, 1); // Enter with Rock
    stop_cheat_block_timestamp(controller.contract_address);
    stop_cheat_caller_address(controller.contract_address);
    // Verify battle state
    let battle = controller.get_battle(1);
    assert(battle.opponent == opponent, 'Wrong opponent');
    assert(battle.opponent_move == 1, 'Wrong move');
    assert(battle.start_date == timestamp, 'Wrong start date');
    spy
        .assert_emitted(
            @array![
                (
                    controller.contract_address,
                    Controller::Event::BattleEntered(
                        Controller::BattleEntered { battle_id: 1, opponent: opponent, move_: 1 }
                    )
                )
            ]
        );
}

#[test]
#[should_panic(expected: 'Invalid move')]
fn test_cannot_enter_with_invalid_move() {
    let (controller, eth) = setup();
    let player = contract_address_const::<'player'>();
    let opponent = contract_address_const::<'opponent'>();
    let payoff_amount: u256 = 5500000000000000000;

    // Mock initial battle
    let mocked_battle = Battle {
        owner: player,
        opponent: contract_address_const::<0>(),
        commitment: 123,
        payoff: payoff_amount,
        start_date: 0,
        opponent_move: 0
    };
    store(
        controller.contract_address,
        map_entry_address(selector!("battles_storage"), array![1].span(),),
        mocked_battle.into()
    );

    start_cheat_caller_address(controller.contract_address, opponent);
    controller.enter_battle(1, 4); // Invalid move
}

#[test]
#[should_panic(expected: 'Battle does not exist')]
fn test_cannot_enter_nonexistent_battle() {
    let (controller, eth) = setup();
    let opponent = contract_address_const::<'opponent'>();

    start_cheat_caller_address(controller.contract_address, opponent);
    controller.enter_battle(1, 1);
}

#[test]
#[should_panic(expected: 'Already started')]
fn test_cannot_enter_started_battle() {
    let (controller, eth) = setup();
    let player = contract_address_const::<'player'>();
    let opponent = contract_address_const::<'opponent'>();
    let payoff_amount: u256 = 5500000000000000000;

    // Mock started battle
    let mocked_battle = Battle {
        owner: player,
        opponent: contract_address_const::<'other_player'>(),
        commitment: 123,
        payoff: payoff_amount,
        start_date: 1000,
        opponent_move: 1
    };
    store(
        controller.contract_address,
        map_entry_address(selector!("battles_storage"), array![1].span(),),
        mocked_battle.into()
    );

    start_cheat_caller_address(controller.contract_address, opponent);
    controller.enter_battle(1, 1);
}

#[test]
#[should_panic(expected: 'Insufficient payoff')]
fn test_cannot_enter_without_sufficient_balance() {
    let (controller, eth) = setup();
    let player = contract_address_const::<'player'>();
    let opponent = contract_address_const::<'opponent'>();
    let payoff_amount: u256 = 5500000000000000000;

    // Mock battle
    let mocked_battle = Battle {
        owner: player,
        opponent: contract_address_const::<0>(),
        commitment: 123,
        payoff: payoff_amount,
        start_date: 0,
        opponent_move: 0
    };
    store(
        controller.contract_address,
        map_entry_address(selector!("battles_storage"), array![1].span(),),
        mocked_battle.into()
    );

    // Don't transfer any tokens to opponent
    start_cheat_caller_address(controller.contract_address, opponent);
    controller.enter_battle(1, 1);
}
