#[test_only]
module escrow::steam_escrow_tests;

use escrow::steam_escrow::{Self, SteamEscrow};
use sui::test_scenario::{Self as ts, Scenario};
use sui::coin::{Self, Coin};
use sui::sui::SUI;

// === Test Constants ===
const BUYER: address = @0xA;
const SELLER: address = @0xB;
const WRONG_USER: address = @0xC;

// === Helper Functions ===

#[test_only]
fun test_coin(ts: &mut Scenario, value: u64): Coin<SUI> {
    coin::mint_for_testing<SUI>(value, ts.ctx())
}

#[test_only]
fun create_test_escrow(ts: &mut Scenario): SteamEscrow {
    steam_escrow::create_escrow(
        BUYER,
        SELLER,
        b"asset_123",
        b"AK-47 Redline",
        1,
        1000, // 1000 SUI price
        ts.ctx()
    )
}

// === Basic Flow Tests ===

#[test]
fun test_successful_complete_flow() {
    let mut ts = ts::begin(@0x0);
    
    // Initialize escrow
    ts.next_tx(BUYER);
    let mut escrow = create_test_escrow(&mut ts);
    
    // Buyer deposits payment
    ts.next_tx(BUYER);
    let payment = test_coin(&mut ts, 1000);
    let (locked_payment, payment_key) = steam_escrow::deposit(&mut escrow, payment, ts.ctx());
    
    // Buyer uploads trade URL
    ts.next_tx(BUYER);
    steam_escrow::upload_trade_url_buyer(&mut escrow, b"https://steamcommunity.com/tradeoffer/new/?partner=123", ts.ctx());
    
    // Seller uploads trade URL
    ts.next_tx(SELLER);
    steam_escrow::upload_trade_url_seller(&mut escrow, b"https://steamcommunity.com/tradeoffer/new/?partner=456", ts.ctx());
    
    // Seller claims payment (transfer completed)
    ts.next_tx(SELLER);
    let claimed_payment = steam_escrow::claim(&mut escrow, locked_payment, payment_key, true, ts.ctx());
    
    // Verify payment amount
    assert!(coin::value(&claimed_payment) == 1000, 0);
    
    // Verify final state
    let (buyer, seller, _asset, price, state, is_transfered) = steam_escrow::get_escrow_info(&escrow);
    assert!(buyer == BUYER, 1);
    assert!(seller == SELLER, 2);
    assert!(price == 1000, 3);
    assert!(state == 4, 4); // STATE_COMPLETED
    assert!(is_transfered == true, 5);
    
    // Cleanup
    coin::burn_for_testing(claimed_payment);
    steam_escrow::destroy_escrow_for_testing(escrow, ts.ctx());
    ts.end();
}

#[test]
fun test_successful_cancel_flow() {
    let mut ts = ts::begin(@0x0);
    
    // Initialize and deposit
    ts.next_tx(BUYER);
    let mut escrow = create_test_escrow(&mut ts);
    let payment = test_coin(&mut ts, 1000);
    let (locked_payment, payment_key) = steam_escrow::deposit(&mut escrow, payment, ts.ctx());
    
    // Buyer cancels (transfer not completed)
    ts.next_tx(BUYER);
    let refunded_payment = steam_escrow::cancel(&mut escrow, locked_payment, payment_key, false, ts.ctx());
    
    // Verify refund amount
    assert!(coin::value(&refunded_payment) == 1000, 0);
    
    // Verify final state
    let (_, _, _, _, state, is_transfered) = steam_escrow::get_escrow_info(&escrow);
    assert!(state == 4, 1); // STATE_COMPLETED
    assert!(is_transfered == false, 2);
    
    // Cleanup
    coin::burn_for_testing(refunded_payment);
    steam_escrow::destroy_escrow_for_testing(escrow, ts.ctx());
    ts.end();
}

// === Error Tests ===

#[test]
#[expected_failure(abort_code = steam_escrow::EInvalidCaller)]
fun test_deposit_wrong_caller() {
    let mut ts = ts::begin(@0x0);
    
    ts.next_tx(BUYER);
    let mut escrow = create_test_escrow(&mut ts);
    
    // Wrong user tries to deposit
    ts.next_tx(WRONG_USER);
    let payment = test_coin(&mut ts, 1000);
    let (_locked, _key) = steam_escrow::deposit(&mut escrow, payment, ts.ctx());
    
    abort 1337
}

#[test]
#[expected_failure(abort_code = steam_escrow::EInsufficientPayment)]
fun test_deposit_insufficient_payment() {
    let mut ts = ts::begin(@0x0);
    
    ts.next_tx(BUYER);
    let mut escrow = create_test_escrow(&mut ts);
    
    // Buyer deposits insufficient amount
    ts.next_tx(BUYER);
    let payment = test_coin(&mut ts, 500); // Less than required 1000
    let (_locked, _key) = steam_escrow::deposit(&mut escrow, payment, ts.ctx());
    
    abort 1337
}

#[test]
#[expected_failure(abort_code = steam_escrow::EInvalidState)]
fun test_buyer_url_before_deposit() {
    let mut ts = ts::begin(@0x0);
    
    ts.next_tx(BUYER);
    let mut escrow = create_test_escrow(&mut ts);
    
    // Buyer tries to upload URL before depositing
    ts.next_tx(BUYER);
    steam_escrow::upload_trade_url_buyer(&mut escrow, b"test_url", ts.ctx());
    
    abort 1337
}

#[test]
#[expected_failure(abort_code = steam_escrow::EAlreadySubmittedURL)]
fun test_buyer_double_url_submission() {
    let mut ts = ts::begin(@0x0);
    
    ts.next_tx(BUYER);
    let mut escrow = create_test_escrow(&mut ts);
    let payment = test_coin(&mut ts, 1000);
    let (_locked_payment, _payment_key) = steam_escrow::deposit(&mut escrow, payment, ts.ctx());
    
    // Buyer uploads URL first time
    ts.next_tx(BUYER);
    steam_escrow::upload_trade_url_buyer(&mut escrow, b"first_url", ts.ctx());
    
    // Buyer tries to upload URL again
    ts.next_tx(BUYER);
    steam_escrow::upload_trade_url_buyer(&mut escrow, b"second_url", ts.ctx());
    
    abort 1337
}

#[test]
#[expected_failure(abort_code = steam_escrow::EInvalidState)]
fun test_seller_url_before_buyer_url() {
    let mut ts = ts::begin(@0x0);
    
    ts.next_tx(BUYER);
    let mut escrow = create_test_escrow(&mut ts);
    let payment = test_coin(&mut ts, 1000);
    let (_locked_payment, _payment_key) = steam_escrow::deposit(&mut escrow, payment, ts.ctx());
    
    // Seller tries to upload URL before buyer
    ts.next_tx(SELLER);
    steam_escrow::upload_trade_url_seller(&mut escrow, b"seller_url", ts.ctx());
    
    abort 1337
}

#[test]
#[expected_failure(abort_code = steam_escrow::EInvalidCaller)]
fun test_claim_wrong_caller() {
    let mut ts = ts::begin(@0x0);
    
    ts.next_tx(BUYER);
    let mut escrow = create_test_escrow(&mut ts);
    let payment = test_coin(&mut ts, 1000);
    let (locked_payment, payment_key) = steam_escrow::deposit(&mut escrow, payment, ts.ctx());
    
    steam_escrow::upload_trade_url_buyer(&mut escrow, b"buyer_url", ts.ctx());
    
    ts.next_tx(SELLER);
    steam_escrow::upload_trade_url_seller(&mut escrow, b"seller_url", ts.ctx());
    
    // Wrong user tries to claim
    ts.next_tx(WRONG_USER);
    let _payment = steam_escrow::claim(&mut escrow, locked_payment, payment_key, true, ts.ctx());
    
    abort 1337
}

#[test]
#[expected_failure(abort_code = steam_escrow::ETransferNotCompleted)]
fun test_claim_transfer_not_completed() {
    let mut ts = ts::begin(@0x0);
    
    ts.next_tx(BUYER);
    let mut escrow = create_test_escrow(&mut ts);
    let payment = test_coin(&mut ts, 1000);
    let (locked_payment, payment_key) = steam_escrow::deposit(&mut escrow, payment, ts.ctx());
    
    steam_escrow::upload_trade_url_buyer(&mut escrow, b"buyer_url", ts.ctx());
    
    ts.next_tx(SELLER);
    steam_escrow::upload_trade_url_seller(&mut escrow, b"seller_url", ts.ctx());
    
    // Seller tries to claim when transfer not completed
    ts.next_tx(SELLER);
    let _payment = steam_escrow::claim(&mut escrow, locked_payment, payment_key, false, ts.ctx()); // is_transfered = false
    
    abort 1337
}

#[test]
#[expected_failure(abort_code = steam_escrow::ETransferAlreadyCompleted)]
fun test_cancel_transfer_already_completed() {
    let mut ts = ts::begin(@0x0);
    
    ts.next_tx(BUYER);
    let mut escrow = create_test_escrow(&mut ts);
    let payment = test_coin(&mut ts, 1000);
    let (locked_payment, payment_key) = steam_escrow::deposit(&mut escrow, payment, ts.ctx());
    
    // Buyer tries to cancel when transfer is completed
    ts.next_tx(BUYER);
    let _payment = steam_escrow::cancel(&mut escrow, locked_payment, payment_key, true, ts.ctx()); // is_transfered = true
    
    abort 1337
}

// === View Function Tests ===

#[test]
fun test_view_functions() {
    let mut ts = ts::begin(@0x0);
    
    ts.next_tx(BUYER);
    let mut escrow = create_test_escrow(&mut ts);
    
    // Test initial state
    assert!(!steam_escrow::has_buyer_trade_url(&escrow), 0);
    assert!(!steam_escrow::has_seller_trade_url(&escrow), 1);
    assert!(steam_escrow::get_state(&escrow) == 0, 2); // STATE_INITIALIZED
    
    // After deposit
    let payment = test_coin(&mut ts, 1000);
    let (locked_payment, payment_key) = steam_escrow::deposit(&mut escrow, payment, ts.ctx());
    assert!(steam_escrow::get_state(&escrow) == 1, 3); // STATE_DEPOSITED
    
    // After buyer URL
    steam_escrow::upload_trade_url_buyer(&mut escrow, b"buyer_url", ts.ctx());
    assert!(steam_escrow::has_buyer_trade_url(&escrow), 4);
    assert!(steam_escrow::get_state(&escrow) == 2, 5); // STATE_BUYER_URL_SUBMITTED
    
    // After seller URL
    ts.next_tx(SELLER);
    steam_escrow::upload_trade_url_seller(&mut escrow, b"seller_url", ts.ctx());
    assert!(steam_escrow::has_seller_trade_url(&escrow), 6);
    assert!(steam_escrow::get_state(&escrow) == 3, 7); // STATE_SELLER_URL_SUBMITTED
    
    // Test escrow info
    let (buyer, seller, _asset, price, state, is_transfered) = steam_escrow::get_escrow_info(&escrow);
    assert!(buyer == BUYER, 8);
    assert!(seller == SELLER, 9);
    assert!(price == 1000, 10);
    assert!(state == 3, 11);
    assert!(!is_transfered, 12);
    
    // Clean up by canceling the escrow (since transfer = false)
    ts.next_tx(BUYER);
    let refund = steam_escrow::cancel(&mut escrow, locked_payment, payment_key, false, ts.ctx());
    coin::burn_for_testing(refund);
    
    // Cleanup
    steam_escrow::destroy_escrow_for_testing(escrow, ts.ctx());
    ts.end();
}
