// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Steam game asset escrow module for peer-to-peer trading
/// This module facilitates secure trading of Steam game assets using Sui tokens
/// It uses the existing lock mechanism for secure asset handling
module escrow::steam_escrow;

use escrow::lock::{Self, Locked, Key};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::event;

/// Steam Asset metadata structure
public struct SteamAsset has store, copy, drop {
    asset_id: vector<u8>,
    asset_name: vector<u8>, 
    asset_amount: u64,
    app_id: vector<u8>,
    icon_url: vector<u8>,
}

/// Steam Escrow object for game asset trading
public struct SteamEscrow has key, store {
    id: UID,
    /// Buyer's wallet address (with zkLogin support)
    buyer: address,
    /// Seller's wallet address (with zkLogin support) 
    seller: address,
    /// Initial item count on seller
    initial_seller_item_count: u8,
    /// Initial item count on buyer
    initial_buyer_item_count: u8,
    // Buyer's trade URL
    trade_url: vector<u8>,
    /// Steam asset being traded
    asset: SteamAsset,
    /// Price in Sui tokens
    price: u64,
    /// Payment deposited flag
    payment_deposited: bool,
    /// Transfer status - true if asset transferred to buyer, false otherwise
    is_transfered: bool,
    /// Escrow state tracking
    state: u8, // 0: initialized, 1: deposited, 2: buyer_url_submitted, 3: seller_url_submitted, 4: completed/cancelled
}

// === Error codes ===
const EInvalidCaller: u64 = 0;
const EInvalidState: u64 = 1;
const EInsufficientPayment: u64 = 2;
const ETransferNotCompleted: u64 = 4;
const ETransferAlreadyCompleted: u64 = 5;

// === State constants ===
const STATE_INITIALIZED: u8 = 0;
const STATE_DEPOSITED: u8 = 1;
const STATE_COMPLETED: u8 = 4;

// === Public Functions ===

/// Initialize a new Steam escrow
/// Only the buyer can call this function
public fun create_escrow(
    buyer: address,
    seller: address,
    asset_id: vector<u8>,
    asset_name: vector<u8>,
    asset_amount: u64,
    app_id: vector<u8>,
    icon_url: vector<u8>,
    trade_url: vector<u8>,
    initial_seller_item_count: u8,
    initial_buyer_item_count: u8,
    price: u64,
    ctx: &mut TxContext
): SteamEscrow {
    // TODO: Call checkStatus to verify seller still has the asset
    // This should validate steamID, appID, contextID via external API
    
    let asset = SteamAsset {
        asset_id,
        asset_name,
        asset_amount,
        app_id,
        icon_url,
    };

    let escrow = SteamEscrow {
        id: object::new(ctx),
        buyer,
        seller,
        asset,
        initial_seller_item_count,
        initial_buyer_item_count,
        trade_url,
        price,
        payment_deposited: false,
        is_transfered: false,
        state: STATE_INITIALIZED,
    };

    event::emit(EscrowInitialized {
        escrow_id: object::id(&escrow),
        buyer,
        seller,
        asset_id,
        asset_name,
        app_id,
        icon_url,
        trade_url,
        price,
    });

    escrow
}

/// Buyer deposits Sui payment into escrow
/// Returns both the locked payment and key for later claim/cancel operations
public fun deposit(
    escrow: &mut SteamEscrow,
    payment: Coin<SUI>,
    ctx: &mut TxContext
): (Locked<Coin<SUI>>, Key) {
    // Verify caller is the buyer
    assert!(ctx.sender() == escrow.buyer, EInvalidCaller);
    
    // Verify escrow is in initialized state
    assert!(escrow.state == STATE_INITIALIZED, EInvalidState);
    
    // Verify payment amount matches price
    assert!(coin::value(&payment) >= escrow.price, EInsufficientPayment);

    // Lock the paymentThe swap function checks that senders and recipients match and that each party wants the object that the other party is offering, by comparing their respective key IDs. If the custodian tried to match together two unrelated escrow requests to swap
    let (locked_payment, key) = lock::lock(payment, ctx);
    
    escrow.payment_deposited = true;
    escrow.state = STATE_DEPOSITED;

    event::emit(PaymentDeposited {
        escrow_id: object::id(escrow),
        buyer: escrow.buyer,
        amount: escrow.price,
    });

    (locked_payment, key)
}


/// Seller claims the payment after successful transfer
public fun claim(
    escrow: &mut SteamEscrow,
    locked_payment: Locked<Coin<SUI>>,
    payment_key: Key,
    is_transfered: bool,
    ctx: &TxContext
): Coin<SUI> {
    // Verify caller is the seller
    assert!(ctx.sender() == escrow.seller, EInvalidCaller);
    
    // Update transfer status (this will be handled by backend)
    escrow.is_transfered = is_transfered;
    
    // Verify transfer was completed
    assert!(escrow.is_transfered, ETransferNotCompleted);

    // Unlock the payment
    let payment = lock::unlock(locked_payment, payment_key);
    
    escrow.state = STATE_COMPLETED;

    event::emit(PaymentClaimed {
        escrow_id: object::id(escrow),
        seller: escrow.seller,
        amount: coin::value(&payment),
    });

    payment
}

/// Buyer cancels the escrow and gets refund
public fun cancel(
    escrow: &mut SteamEscrow,
    locked_payment: Locked<Coin<SUI>>,
    payment_key: Key,
    is_transfered: bool,
    ctx: &TxContext
): Coin<SUI> {
    // Verify caller is the buyer
    assert!(ctx.sender() == escrow.buyer, EInvalidCaller);
    
    // Update transfer status (this will be handled by backend)
    escrow.is_transfered = is_transfered;
    
    // Verify transfer was NOT completed
    assert!(!escrow.is_transfered, ETransferAlreadyCompleted);

    // Unlock the payment for refund
    let payment = lock::unlock(locked_payment, payment_key);
    
    escrow.state = STATE_COMPLETED;

    event::emit(EscrowCancelled {
        escrow_id: object::id(escrow),
        buyer: escrow.buyer,
        refund_amount: coin::value(&payment),
    });

    payment
}

// === View Functions ===

/// Get escrow details
public fun get_escrow_info(escrow: &SteamEscrow): (address, address, SteamAsset, u64, u8, bool) {
    (escrow.buyer, escrow.seller, escrow.asset, escrow.price, escrow.state, escrow.is_transfered)
}

/// Get current state
public fun get_state(escrow: &SteamEscrow): u8 {
    escrow.state
}

// === Events ===

public struct EscrowInitialized has copy, drop {
    escrow_id: ID,
    buyer: address,
    seller: address,
    asset_id: vector<u8>,
    asset_name: vector<u8>,
    app_id: vector<u8>,
    icon_url: vector<u8>,
    trade_url: vector<u8>,
    price: u64,
}

public struct PaymentDeposited has copy, drop {
    escrow_id: ID,
    buyer: address,
    amount: u64,
}
public struct PaymentClaimed has copy, drop {
    escrow_id: ID,
    seller: address,
    amount: u64,
}

public struct EscrowCancelled has copy, drop {
    escrow_id: ID,
    buyer: address,
    refund_amount: u64,
}

// === Test-only functions ===
#[test_only]
public fun destroy_escrow_for_testing(escrow: SteamEscrow, _ctx: &mut TxContext) {
    let SteamEscrow { 
        id, 
        buyer: _, 
        seller: _, 
        asset: _, 
        price: _, 
        payment_deposited: _, 
        is_transfered: _, 
        state: _ 
    } = escrow;
    
    object::delete(id);
}
