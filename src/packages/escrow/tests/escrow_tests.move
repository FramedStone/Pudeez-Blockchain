#[test_only]
module escrow::escrow_tests;

use escrow::lock::{Self, Locked, Key};
use escrow::owned;
use escrow::shared;
use sui::test_scenario::{Self as ts, Scenario};
use sui::coin::{Self, Coin};
use sui::sui::SUI;

// === Test Constants ===
const ALICE: address = @0xA;
const BOB: address = @0xB;
const CUSTODIAN: address = @0xC;
const DIANE: address = @0xD;

// === Helper Functions ===

#[test_only]
fun test_coin(ts: &mut Scenario): Coin<SUI> {
    coin::mint_for_testing<SUI>(42, ts.ctx())
}

#[test_only]
fun test_coin_with_value(ts: &mut Scenario, value: u64): Coin<SUI> {
    coin::mint_for_testing<SUI>(value, ts.ctx())
}

// === Lock Module Tests ===

#[test]
fun test_lock_unlock_basic() {
    let mut ts = ts::begin(@0xA);
    let coin = test_coin(&mut ts);

    let (lock, key) = lock::lock(coin, ts.ctx());
    let coin = lock.unlock(key);

    coin.burn_for_testing();
    ts.end();
}

#[test]
#[expected_failure(abort_code = lock::ELockKeyMismatch)]
fun test_lock_key_mismatch() {
    let mut ts = ts::begin(@0xA);
    let coin = test_coin(&mut ts);
    let another_coin = test_coin(&mut ts);
    
    let (l, _k) = lock::lock(coin, ts.ctx());
    let (_l, k) = lock::lock(another_coin, ts.ctx());

    let _coin = l.unlock(k);
    abort 1337
}

#[test]
fun test_lock_with_different_object_types() {
    let mut ts = ts::begin(@0xA);
    
    // Test with coin
    let coin = test_coin(&mut ts);
    let (lock1, key1) = lock::lock(coin, ts.ctx());
    let coin = lock1.unlock(key1);
    coin.burn_for_testing();
    
    // Test with another coin of different value
    let coin2 = test_coin_with_value(&mut ts, 100);
    let (lock2, key2) = lock::lock(coin2, ts.ctx());
    let coin2 = lock2.unlock(key2);
    coin2.burn_for_testing();
    
    ts.end();
}

#[test]
fun test_multiple_locks() {
    let mut ts = ts::begin(@0xA);
    
    let coin1 = test_coin_with_value(&mut ts, 10);
    let coin2 = test_coin_with_value(&mut ts, 20);
    let coin3 = test_coin_with_value(&mut ts, 30);
    
    let (lock1, key1) = lock::lock(coin1, ts.ctx());
    let (lock2, key2) = lock::lock(coin2, ts.ctx());
    let (lock3, key3) = lock::lock(coin3, ts.ctx());
    
    // Unlock in different order
    let coin3 = lock3.unlock(key3);
    let coin1 = lock1.unlock(key1);
    let coin2 = lock2.unlock(key2);
    
    coin1.burn_for_testing();
    coin2.burn_for_testing();
    coin3.burn_for_testing();
    
    ts.end();
}

// === Owned Module Tests ===

#[test]
fun test_owned_escrow_successful_swap() {
    let mut ts = ts::begin(@0x0);

    // Alice locks the object they want to trade
    let (i1, ik1) = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, ALICE);
        transfer::public_transfer(k, ALICE);
        (cid, kid)
    };

    // Bob locks their object as well
    let (i2, ik2) = {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        (cid, kid)
    };

    // Alice gives the custodian their object to hold in escrow
    {
        ts.next_tx(ALICE);
        let k1: Key = ts.take_from_sender();
        let l1: Locked<Coin<SUI>> = ts.take_from_sender();
        owned::create(k1, l1, ik2, BOB, CUSTODIAN, ts.ctx());
    };

    // Bob does the same
    {
        ts.next_tx(BOB);
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        owned::create(k2, l2, ik1, ALICE, CUSTODIAN, ts.ctx());
    };

    // The custodian makes the swap
    {
        ts.next_tx(CUSTODIAN);
        owned::swap<Coin<SUI>, Coin<SUI>>(
            ts.take_from_sender(),
            ts.take_from_sender()
        );
    };

    // Commit effects from the swap
    ts.next_tx(@0x0);

    // Alice gets the object from Bob
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(ALICE, i2);
        ts::return_to_address(ALICE, c);
    };

    // Bob gets the object from Alice
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(BOB, i1);
        ts::return_to_address(BOB, c);
    };

    ts.end();
}

#[test]
#[expected_failure(abort_code = owned::EMismatchedSenderRecipient)]
fun test_owned_escrow_mismatch_sender() {
    let mut ts = ts::begin(@0x0);

    let ik1 = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, ALICE);
        transfer::public_transfer(k, ALICE);
        kid
    };

    let ik2 = {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        kid
    };

    // Alice wants to trade with Bob
    {
        ts.next_tx(ALICE);
        let k1: Key = ts.take_from_sender();
        let l1: Locked<Coin<SUI>> = ts.take_from_sender();
        owned::create(k1, l1, ik2, BOB, CUSTODIAN, ts.ctx());
    };

    // But Bob wants to trade with Diane
    {
        ts.next_tx(BOB);
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        owned::create(k2, l2, ik1, DIANE, CUSTODIAN, ts.ctx());
    };

    // When the custodian tries to match up the swap, it will fail
    {
        ts.next_tx(CUSTODIAN);
        owned::swap<Coin<SUI>, Coin<SUI>>(
            ts.take_from_sender(),
            ts.take_from_sender()
        );
    };

    abort 1337
}

#[test]
#[expected_failure(abort_code = owned::EMismatchedExchangeObject)]
fun test_owned_escrow_mismatch_object() {
    let mut ts = ts::begin(@0x0);

    let ik1 = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, ALICE);
        transfer::public_transfer(k, ALICE);
        kid
    };

    let (_i2, _ik2) = {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        (cid, kid)
    };

    // Alice wants to trade with Bob, but Alice has asked for an
    // object (via its `exchange_key`) that Bob has not put up for
    // the swap
    {
        ts.next_tx(ALICE);
        let k1: Key = ts.take_from_sender();
        let l1: Locked<Coin<SUI>> = ts.take_from_sender();
        owned::create(k1, l1, object::id_from_address(@0x999), BOB, CUSTODIAN, ts.ctx());
    };

    {
        ts.next_tx(BOB);
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        owned::create(k2, l2, ik1, ALICE, CUSTODIAN, ts.ctx());
    };

    // When the custodian tries to match up the swap, it will fail
    {
        ts.next_tx(CUSTODIAN);
        owned::swap<Coin<SUI>, Coin<SUI>>(
            ts.take_from_sender(),
            ts.take_from_sender()
        );
    };

    abort 1337
}

#[test]
fun test_owned_escrow_return_to_sender() {
    let mut ts = ts::begin(@0x0);

    // Alice locks the object they want to trade
    let cid = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        let (l, k) = lock::lock(c, ts.ctx());
        transfer::public_transfer(l, ALICE);
        transfer::public_transfer(k, ALICE);
        cid
    };

    // Alice creates escrow
    {
        ts.next_tx(ALICE);
        let k1: Key = ts.take_from_sender();
        let l1: Locked<Coin<SUI>> = ts.take_from_sender();
        owned::create(k1, l1, object::id_from_address(@0x999), BOB, CUSTODIAN, ts.ctx());
    };

    // Custodian sends it back
    {
        ts.next_tx(CUSTODIAN);
        owned::return_to_sender<Coin<SUI>>(ts.take_from_sender());
    };

    ts.next_tx(@0x0);

    // Alice can then access it
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(ALICE, cid);
        ts::return_to_address(ALICE, c);
    };

    ts.end();
}

#[test]
#[expected_failure(abort_code = owned::EMismatchedExchangeObject)]
fun test_owned_escrow_object_tamper() {
    let mut ts = ts::begin(@0x0);

    // Alice locks the object they want to trade
    let ik1 = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, ALICE);
        transfer::public_transfer(k, ALICE);
        kid
    };

    // Bob locks their object as well
    let ik2 = {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        kid
    };

    // Alice gives the custodian their object to hold in escrow
    {
        ts.next_tx(ALICE);
        let k1: Key = ts.take_from_sender();
        let l1: Locked<Coin<SUI>> = ts.take_from_sender();
        owned::create(k1, l1, ik2, BOB, CUSTODIAN, ts.ctx());
    };

    // Bob has a change of heart, so they unlock the object and tamper
    // with it
    {
        ts.next_tx(BOB);
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        let c = l2.unlock(k2);
        
        // Re-lock with new key (tampering)
        let (new_l, new_k) = lock::lock(c, ts.ctx());
        owned::create(new_k, new_l, ik1, ALICE, CUSTODIAN, ts.ctx());
    };

    // When the Custodian makes the swap, it detects Bob's nefarious
    // behaviour
    {
        ts.next_tx(CUSTODIAN);
        owned::swap<Coin<SUI>, Coin<SUI>>(
            ts.take_from_sender(),
            ts.take_from_sender()
        );
    };

    abort 1337
}

// === Shared Module Tests ===

#[test]
fun test_shared_escrow_successful_swap() {
    let mut ts = ts::begin(@0x0);

    // Bob locks the object they want to trade
    let (i2, ik2) = {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        (cid, kid)
    };

    // Alice creates a public Escrow holding the object they are willing to
    // share, and the object they want from Bob
    let i1 = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        shared::create(c, ik2, BOB, ts.ctx());
        cid
    };

    // Bob responds by offering their object, and gets Alice's object in
    // return
    {
        ts.next_tx(BOB);
        let escrow: shared::Escrow<Coin<SUI>> = ts.take_shared();
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        let c = escrow.swap(k2, l2, ts.ctx());

        transfer::public_transfer(c, BOB);
    };

    // Commit effects from the swap
    ts.next_tx(@0x0);

    // Alice gets the object from Bob
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(ALICE, i2);
        ts::return_to_address(ALICE, c);
    };

    // Bob gets the object from Alice
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(BOB, i1);
        ts::return_to_address(BOB, c);
    };

    ts.end();
}

#[test]
#[expected_failure(abort_code = shared::EMismatchedSenderRecipient)]
fun test_shared_escrow_mismatch_sender() {
    let mut ts = ts::begin(@0x0);

    let ik2 = {
        ts.next_tx(DIANE);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, DIANE);
        transfer::public_transfer(k, DIANE);
        kid
    };

    // Alice wants to trade with Bob
    {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        shared::create(c, ik2, BOB, ts.ctx());
    };

    // But Diane is the one who attempts the swap
    {
        ts.next_tx(DIANE);
        let escrow: shared::Escrow<Coin<SUI>> = ts.take_shared();
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        let c = escrow.swap(k2, l2, ts.ctx());

        transfer::public_transfer(c, DIANE);
    };

    abort 1337
}

#[test]
#[expected_failure(abort_code = shared::EMismatchedExchangeObject)]
fun test_shared_escrow_mismatch_object() {
    let mut ts = ts::begin(@0x0);

    {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
    };

    // Alice wants to trade with Bob, but Alice has asked for an object (via
    // its `exchange_key`) that Bob has not put up for the swap
    {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        shared::create(c, cid, BOB, ts.ctx());
    };

    // When Bob tries to complete the swap, it will fail, because they
    // cannot meet Alice's requirements
    {
        ts.next_tx(BOB);
        let escrow: shared::Escrow<Coin<SUI>> = ts.take_shared();
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        let c = escrow.swap(k2, l2, ts.ctx());

        transfer::public_transfer(c, BOB);
    };

    abort 1337
}

#[test]
#[expected_failure(abort_code = shared::EMismatchedExchangeObject)]
fun test_shared_escrow_object_tamper() {
    let mut ts = ts::begin(@0x0);

    // Bob locks their object
    let ik2 = {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        kid
    };

    // Alice sets up the escrow
    {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        shared::create(c, ik2, BOB, ts.ctx());
    };

    // Bob has a change of heart, so they unlock the object and tamper with
    // it before initiating the swap, but it won't be possible for Bob to
    // hide their tampering
    {
        ts.next_tx(BOB);
        let escrow: shared::Escrow<Coin<SUI>> = ts.take_shared();
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        
        // Tamper with the object
        let c = l2.unlock(k2);
        let (new_l, new_k) = lock::lock(c, ts.ctx());
        
        let c = escrow.swap(new_k, new_l, ts.ctx());
        transfer::public_transfer(c, BOB);
    };

    abort 1337
}

#[test]
fun test_shared_escrow_return_to_sender() {
    let mut ts = ts::begin(@0x0);

    // Alice puts up the object they want to trade
    let cid = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        shared::create(c, object::id_from_address(@0x999), BOB, ts.ctx());
        cid
    };

    // ...but has a change of heart and takes it back
    {
        ts.next_tx(ALICE);
        let escrow: shared::Escrow<Coin<SUI>> = ts.take_shared();
        let c = escrow.return_to_sender(ts.ctx());
        transfer::public_transfer(c, ALICE);
    };

    ts.next_tx(@0x0);

    // Alice can then access it
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(ALICE, cid);
        ts::return_to_address(ALICE, c);
    };

    ts.end();
}

#[test]
#[expected_failure]
fun test_shared_escrow_return_to_sender_failed_swap() {
    let mut ts = ts::begin(@0x0);

    // Bob locks their object
    let ik2 = {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        kid
    };

    // Alice creates a public Escrow holding the object they are willing to
    // share, and the object they want from Bob
    {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        shared::create(c, ik2, BOB, ts.ctx());
    };

    // ...but then has a change of heart
    {
        ts.next_tx(ALICE);
        let escrow: shared::Escrow<Coin<SUI>> = ts.take_shared();
        let c = escrow.return_to_sender(ts.ctx());
        transfer::public_transfer(c, ALICE);
    };

    // Bob's attempt to complete the swap will now fail
    {
        ts.next_tx(BOB);
        let escrow: shared::Escrow<Coin<SUI>> = ts.take_shared();
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        let c = escrow.swap(k2, l2, ts.ctx());

        transfer::public_transfer(c, BOB);
    };

    abort 1337
}

// === Complex Integration Tests ===

#[test]
fun test_multiple_escrows_different_types() {
    let mut ts = ts::begin(@0x0);

    // Test multiple escrows running in parallel
    let (i1a, ik1a) = {
        ts.next_tx(ALICE);
        let c = test_coin_with_value(&mut ts, 100);
        let cid = object::id(&c);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, ALICE);
        transfer::public_transfer(k, ALICE);
        (cid, kid)
    };

    let (i2a, ik2a) = {
        ts.next_tx(BOB);
        let c = test_coin_with_value(&mut ts, 200);
        let cid = object::id(&c);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        (cid, kid)
    };

    // Alice creates owned escrow
    {
        ts.next_tx(ALICE);
        let k1: Key = ts.take_from_sender();
        let l1: Locked<Coin<SUI>> = ts.take_from_sender();
        owned::create(k1, l1, ik2a, BOB, CUSTODIAN, ts.ctx());
    };

    // Bob creates owned escrow
    {
        ts.next_tx(BOB);
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        owned::create(k2, l2, ik1a, ALICE, CUSTODIAN, ts.ctx());
    };

    // Custodian executes swap
    {
        ts.next_tx(CUSTODIAN);
        owned::swap<Coin<SUI>, Coin<SUI>>(
            ts.take_from_sender(),
            ts.take_from_sender()
        );
    };

    ts.next_tx(@0x0);

    // Verify correct objects were swapped
    {
        let c1: Coin<SUI> = ts.take_from_address_by_id(ALICE, i2a);
        assert!(coin::value(&c1) == 200, 0);
        ts::return_to_address(ALICE, c1);
    };

    {
        let c2: Coin<SUI> = ts.take_from_address_by_id(BOB, i1a);
        assert!(coin::value(&c2) == 100, 1);
        ts::return_to_address(BOB, c2);
    };

    ts.end();
}

#[test]
fun test_mixed_escrow_types() {
    let mut ts = ts::begin(@0x0);

    // Test both owned and shared escrows in sequence
    let (i2, ik2) = {
        ts.next_tx(BOB);
        let c = test_coin_with_value(&mut ts, 75);
        let cid = object::id(&c);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        (cid, kid)
    };

    // Alice creates shared escrow
    let i1 = {
        ts.next_tx(ALICE);
        let c = test_coin_with_value(&mut ts, 25);
        let cid = object::id(&c);
        shared::create(c, ik2, BOB, ts.ctx());
        cid
    };

    // Bob completes the shared escrow swap
    {
        ts.next_tx(BOB);
        let escrow: shared::Escrow<Coin<SUI>> = ts.take_shared();
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        let c = escrow.swap(k2, l2, ts.ctx());

        transfer::public_transfer(c, BOB);
    };

    ts.next_tx(@0x0);

    // Verify the shared escrow swap worked
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(ALICE, i2);
        assert!(coin::value(&c) == 75, 0);
        ts::return_to_address(ALICE, c);
    };

    {
        let c: Coin<SUI> = ts.take_from_address_by_id(BOB, i1);
        assert!(coin::value(&c) == 25, 1);
        ts::return_to_address(BOB, c);
    };

    ts.end();
}