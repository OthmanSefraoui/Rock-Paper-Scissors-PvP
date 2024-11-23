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
    let initial_balance = eth.balanceOf(opponent);
    controller.enter_battle(1, 1); // Enter with Rock
    stop_cheat_block_timestamp(controller.contract_address);
    stop_cheat_caller_address(controller.contract_address);
    // Verify battle state
    let battle = controller.get_battle(1);
    assert(battle.opponent == opponent, 'Wrong opponent');
    assert(battle.opponent_move == 1, 'Wrong move');
    assert(battle.start_date == timestamp, 'Wrong start date');
    // Verify payment was processed
    let final_balance = eth.balanceOf(opponent);
    assert(final_balance == initial_balance - payoff_amount, 'Payment not processed');
    let contract_balance = eth.balanceOf(controller.contract_address);
    assert(contract_balance == payoff_amount, 'Contract balance wrong');

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

#[test]
fn test_get_winner_success() {
    let (controller, eth) = setup();
    // Test all possible draw scenarios
    assert(controller.get_winner(1_u8, 1_u8) == 0_u8, 'Rock-Rock');
    assert(controller.get_winner(2_u8, 2_u8) == 0_u8, 'Paper-Paper');
    assert(controller.get_winner(3_u8, 3_u8) == 0_u8, 'Scissors-Scissors');
    // Test all scenarios where Player 1 should win
    assert(controller.get_winner(1_u8, 3_u8) == 1_u8, 'Rock beat Scissors');
    assert(controller.get_winner(2_u8, 1_u8) == 1_u8, 'Paper beat Rock');
    assert(controller.get_winner(3_u8, 2_u8) == 1_u8, 'Scissors beat Paper');
    // Test all scenarios where Player 2 should win
    assert(controller.get_winner(3_u8, 1_u8) == 2_u8, 'Rock beat Scissors');
    assert(controller.get_winner(1_u8, 2_u8) == 2_u8, 'Paper beat Rock');
    assert(controller.get_winner(2_u8, 3_u8) == 2_u8, 'Scissors beat Paper');
}

#[test]
#[should_panic(expected: 'Invalid move')]
fn test_get_winner_with_invalid_moves() {
    let (controller, eth) = setup();
    controller.get_winner(0_u8, 1_u8);
}

#[test]
fn test_resolve_battle_timeout() {
    // Setup
    let (controller, eth) = setup();
    let owner = contract_address_const::<'owner'>();
    let opponent = contract_address_const::<'opponent'>();
    let payoff_amount: u256 = 5500000000000000000;
    let commitment = 1416164405029674324331909544155980085306730986792554086473471855678221018328;
    let recipient = contract_address_const::<'recipient'>();
    // Mock battle with expired timeout
    let start_time = 100000;
    let timeout_delay = 12000_u64; // 1 hour
    let current_time = start_time + timeout_delay + 1; // Just past timeout
    // Start cheating with the ETH contract address as the caller and the recipient as the address
    start_cheat_caller_address(eth.contract_address, recipient);
    // Transfer the payoffs to the controller
    eth.transfer(controller.contract_address, payoff_amount * 2);
    stop_cheat_caller_address(eth.contract_address);
    let mocked_battle = Battle {
        owner: owner,
        opponent: opponent,
        commitment: commitment,
        payoff: payoff_amount,
        start_date: start_time,
        opponent_move: 2
    };

    store(
        controller.contract_address,
        map_entry_address(selector!("battles_storage"), array![1].span()),
        mocked_battle.into()
    );
    // Set block timestamp
    start_cheat_block_timestamp(controller.contract_address, current_time);
    // Try to resolve
    let mut spy = spy_events();
    start_cheat_caller_address(controller.contract_address, owner);
    controller.resolve_battle(1, 1, 12345); // Move and secret don't matter in timeout
    stop_cheat_caller_address(controller.contract_address);
    stop_cheat_block_timestamp(controller.contract_address,);
    // Verify opponent received funds
    let opponent_balance = eth.balanceOf(opponent);
    assert(opponent_balance == payoff_amount * 2, 'Wrong timeout payout');
    // Verify battle was cleared
    let battle = controller.get_battle(1);
    assert(battle.payoff == 0, 'Battle not cleared');
    assert(battle.owner == contract_address_const::<0>(), 'Owner not cleared');
    assert(battle.commitment == 0, 'Commitment not cleared');
    // Verify event emission
    spy
        .assert_emitted(
            @array![
                (
                    controller.contract_address,
                    Controller::Event::BattleResolved(
                        Controller::BattleResolved {
                            battle_id: 1, winner: opponent, payoff: payoff_amount * 2
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_resolve_battle_draw() {
    let (controller, eth) = setup();
    let owner = contract_address_const::<'owner'>();
    let opponent = contract_address_const::<'opponent'>();
    let payoff_amount: u256 = 5500000000000000000;
    let recipient = contract_address_const::<'recipient'>();
    // Start cheating with the ETH contract address as the caller and the recipient as the address
    start_cheat_caller_address(eth.contract_address, recipient);
    // Transfer the payoffs to the controller
    eth.transfer(controller.contract_address, payoff_amount * 2);
    stop_cheat_caller_address(eth.contract_address);
    // Both players choose Rock (1)
    let move_num: u8 = 1;
    let secret: felt252 = 12345;
    //commitment generated using python script (poseidon hash)
    let commitment = 739725270007697963362708211148095784907140316322117362604841719456368453247;

    let mocked_battle = Battle {
        owner, opponent, commitment, payoff: payoff_amount, start_date: 11111111, opponent_move: 1
    };

    store(
        controller.contract_address,
        map_entry_address(selector!("battles_storage"), array![1].span()),
        mocked_battle.into()
    );

    let mut spy = spy_events();
    start_cheat_caller_address(controller.contract_address, owner);
    controller.resolve_battle(1, move_num, secret);
    stop_cheat_caller_address(controller.contract_address);
    // Verify split payout
    let owner_balance = eth.balanceOf(owner);
    let opponent_balance = eth.balanceOf(opponent);
    assert(owner_balance == payoff_amount, 'Wrong owner split');
    assert(opponent_balance == payoff_amount, 'Wrong opponent split');
    // Verify battle was cleared
    let battle = controller.get_battle(1);
    assert(battle.payoff == 0, 'Battle not cleared');
    assert(battle.owner == contract_address_const::<0>(), 'Owner not cleared');
    assert(battle.commitment == 0, 'Commitment not cleared');
    // Verify events
    spy
        .assert_emitted(
            @array![
                (
                    controller.contract_address,
                    Controller::Event::BattleResolved(
                        Controller::BattleResolved {
                            battle_id: 1, winner: opponent, payoff: payoff_amount
                        }
                    )
                ),
                (
                    controller.contract_address,
                    Controller::Event::BattleResolved(
                        Controller::BattleResolved {
                            battle_id: 1, winner: owner, payoff: payoff_amount
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_resolve_battle_owner_wins() {
    let (controller, eth) = setup();
    let owner = contract_address_const::<'owner'>();
    let opponent = contract_address_const::<'opponent'>();
    let payoff_amount: u256 = 5500000000000000000;
    let recipient = contract_address_const::<'recipient'>();
    // Start cheating with the ETH contract address as the caller and the recipient as the address
    start_cheat_caller_address(eth.contract_address, recipient);
    // Transfer the payoffs to the controller
    eth.transfer(controller.contract_address, payoff_amount * 2);
    stop_cheat_caller_address(eth.contract_address);
    // Owner plays Rock (1), Opponent plays Scissors (3)
    let move_num: u8 = 1;
    let secret: felt252 = 12345;
    let commitment = 739725270007697963362708211148095784907140316322117362604841719456368453247;

    let mocked_battle = Battle {
        owner, opponent, commitment, payoff: payoff_amount, start_date: 11111111, opponent_move: 3
    };

    store(
        controller.contract_address,
        map_entry_address(selector!("battles_storage"), array![1].span()),
        mocked_battle.into()
    );

    let mut spy = spy_events();
    start_cheat_caller_address(controller.contract_address, owner);
    controller.resolve_battle(1, move_num, secret);
    stop_cheat_caller_address(controller.contract_address);
    // Verify winner payout
    let owner_balance = eth.balanceOf(owner);
    assert(owner_balance == payoff_amount * 2, 'Wrong winner payout');
    // Verify battle was cleared
    let battle = controller.get_battle(1);
    assert(battle.payoff == 0, 'Battle not cleared');
    assert(battle.owner == contract_address_const::<0>(), 'Owner not cleared');
    assert(battle.commitment == 0, 'Commitment not cleared');
    // Verify event
    spy
        .assert_emitted(
            @array![
                (
                    controller.contract_address,
                    Controller::Event::BattleResolved(
                        Controller::BattleResolved {
                            battle_id: 1, winner: owner, payoff: payoff_amount * 2
                        }
                    )
                )
            ]
        );
}

#[test]
fn test_resolve_battle_owner_loose() {
    let (controller, eth) = setup();
    let owner = contract_address_const::<'owner'>();
    let opponent = contract_address_const::<'opponent'>();
    let payoff_amount: u256 = 5500000000000000000;
    let recipient = contract_address_const::<'recipient'>();
    // Start cheating with the ETH contract address as the caller and the recipient as the address
    start_cheat_caller_address(eth.contract_address, recipient);
    // Transfer the payoffs to the controller
    eth.transfer(controller.contract_address, payoff_amount * 2);
    stop_cheat_caller_address(eth.contract_address);
    // Owner plays Rock (1), Opponent plays Scissors (3)
    let move_num: u8 = 1;
    let secret: felt252 = 12345;
    let commitment = 739725270007697963362708211148095784907140316322117362604841719456368453247;

    let mocked_battle = Battle {
        owner, opponent, commitment, payoff: payoff_amount, start_date: 11111111, opponent_move: 2
    };

    store(
        controller.contract_address,
        map_entry_address(selector!("battles_storage"), array![1].span()),
        mocked_battle.into()
    );

    let mut spy = spy_events();
    start_cheat_caller_address(controller.contract_address, owner);
    controller.resolve_battle(1, move_num, secret);
    stop_cheat_caller_address(controller.contract_address);
    // Verify winner payout
    let opponent_balance = eth.balanceOf(opponent);
    assert(opponent_balance == payoff_amount * 2, 'Wrong winner payout');
    // Verify battle was cleared
    let battle = controller.get_battle(1);
    assert(battle.payoff == 0, 'Battle not cleared');
    assert(battle.owner == contract_address_const::<0>(), 'Owner not cleared');
    assert(battle.commitment == 0, 'Commitment not cleared');
    // Verify event
    spy
        .assert_emitted(
            @array![
                (
                    controller.contract_address,
                    Controller::Event::BattleResolved(
                        Controller::BattleResolved {
                            battle_id: 1, winner: opponent, payoff: payoff_amount * 2
                        }
                    )
                )
            ]
        );
}

#[test]
#[should_panic(expected: 'Invalid move')]
fn test_resolve_battle_invalid_move() {
    let (controller, _) = setup();
    let owner = contract_address_const::<'owner'>();
    let opponent = contract_address_const::<'opponent'>();
    let payoff_amount: u256 = 5500000000000000000;

    let mocked_battle = Battle {
        owner,
        opponent,
        commitment: 123456, // Doesn't matter for this test
        payoff: payoff_amount,
        start_date: 1111111,
        opponent_move: 1
    };

    store(
        controller.contract_address,
        map_entry_address(selector!("battles_storage"), array![1].span()),
        mocked_battle.into()
    );

    start_cheat_caller_address(controller.contract_address, owner);
    controller.resolve_battle(1, 4, 12345); // Move 4 is invalid
}

#[test]
#[should_panic(expected: 'Invalid commitment')]
fn test_resolve_battle_invalid_commitment() {
    let (controller, _) = setup();
    let owner = contract_address_const::<'owner'>();
    let opponent = contract_address_const::<'opponent'>();
    let payoff_amount: u256 = 5500000000000000000;

    let mocked_battle = Battle {
        owner,
        opponent,
        commitment: 123456,
        payoff: payoff_amount,
        start_date: 11111111,
        opponent_move: 1
    };

    store(
        controller.contract_address,
        map_entry_address(selector!("battles_storage"), array![1].span()),
        mocked_battle.into()
    );

    start_cheat_caller_address(controller.contract_address, owner);
    controller.resolve_battle(1, 1, 99999); // Wrong secret leads to invalid commitment
}
