/// Balance tracking with multiple categories for better UX
/// Based on Swift SDK's WalletSummary structure

/// Zatoshi - the base unit of Zcash (1 ZEC = 100,000,000 zatoshi)
#[derive(Drop, Copy, Serde, PartialEq, Debug)]
pub struct Zatoshi {
    pub value: u64,
}

pub trait ZatoshiTrait {
    fn zero() -> Zatoshi;
    fn from_u64(value: u64) -> Zatoshi;
    fn add(self: Zatoshi, other: Zatoshi) -> Zatoshi;
    fn sub(self: Zatoshi, other: Zatoshi) -> Option<Zatoshi>;
    fn is_positive(self: @Zatoshi) -> bool;
}

impl ZatoshiImpl of ZatoshiTrait {
    fn zero() -> Zatoshi {
        Zatoshi { value: 0 }
    }

    fn from_u64(value: u64) -> Zatoshi {
        Zatoshi { value }
    }

    fn add(self: Zatoshi, other: Zatoshi) -> Zatoshi {
        Zatoshi { value: self.value + other.value }
    }

    fn sub(self: Zatoshi, other: Zatoshi) -> Option<Zatoshi> {
        if self.value >= other.value {
            Option::Some(Zatoshi { value: self.value - other.value })
        } else {
            Option::None
        }
    }

    fn is_positive(self: @Zatoshi) -> bool {
        *self.value > 0
    }
}

/// Balance for a single shielded pool (Sapling or Orchard)
/// Four categories enable showing spendable funds during sync
#[derive(Drop, Copy, Serde, Debug)]
pub struct PoolBalance {
    /// Funds that can be spent immediately
    /// These have been verified and have sufficient confirmations
    pub spendable_value: Zatoshi,

    /// Change from recent transactions awaiting confirmation
    pub change_pending_confirmation: Zatoshi,

    /// Funds that need more confirmations before becoming spendable
    pub value_pending_spendability: Zatoshi,

    /// Total balance (sum of all categories)
    pub total: Zatoshi,
}

pub trait PoolBalanceTrait {
    fn zero() -> PoolBalance;
    fn calculate_total(self: @PoolBalance) -> Zatoshi;
    fn has_spendable_funds(self: @PoolBalance) -> bool;
    fn pending_balance(self: @PoolBalance) -> Zatoshi;
}

impl PoolBalanceImpl of PoolBalanceTrait {
    fn zero() -> PoolBalance {
        PoolBalance {
            spendable_value: ZatoshiTrait::zero(),
            change_pending_confirmation: ZatoshiTrait::zero(),
            value_pending_spendability: ZatoshiTrait::zero(),
            total: ZatoshiTrait::zero(),
        }
    }

    /// Calculate total from components
    fn calculate_total(self: @PoolBalance) -> Zatoshi {
        self.spendable_value.add(*self.change_pending_confirmation)
            .add(*self.value_pending_spendability)
    }

    /// Check if any funds are available for spending
    fn has_spendable_funds(self: @PoolBalance) -> bool {
        self.spendable_value.is_positive()
    }

    /// Get pending balance (not yet spendable)
    fn pending_balance(self: @PoolBalance) -> Zatoshi {
        self.change_pending_confirmation.add(*self.value_pending_spendability)
    }
}

/// Complete account balance across all pools
#[derive(Drop, Copy, Serde, Debug)]
pub struct AccountBalance {
    /// Sapling shielded pool balance
    pub sapling_balance: PoolBalance,

    /// Orchard shielded pool balance
    pub orchard_balance: PoolBalance,

    /// Transparent (unshielded) balance
    pub unshielded: Zatoshi,

    /// Temporary balance for unresolved states during scanning
    pub awaiting_resolution: Zatoshi,
}

pub trait AccountBalanceTrait {
    fn zero() -> AccountBalance;
    fn total_spendable(self: @AccountBalance) -> Zatoshi;
    fn total_balance(self: @AccountBalance) -> Zatoshi;
    fn total_pending(self: @AccountBalance) -> Zatoshi;
    fn can_spend(self: @AccountBalance) -> bool;
}

impl AccountBalanceImpl of AccountBalanceTrait {
    fn zero() -> AccountBalance {
        AccountBalance {
            sapling_balance: PoolBalanceTrait::zero(),
            orchard_balance: PoolBalanceTrait::zero(),
            unshielded: ZatoshiTrait::zero(),
            awaiting_resolution: ZatoshiTrait::zero(),
        }
    }

    /// Get total spendable across all pools
    fn total_spendable(self: @AccountBalance) -> Zatoshi {
        self.sapling_balance.spendable_value
            .add(*self.orchard_balance.spendable_value)
            .add(*self.unshielded)
    }

    /// Get total balance across all pools
    fn total_balance(self: @AccountBalance) -> Zatoshi {
        self.sapling_balance.total
            .add(*self.orchard_balance.total)
            .add(*self.unshielded)
            .add(*self.awaiting_resolution)
    }

    /// Get total pending balance
    fn total_pending(self: @AccountBalance) -> Zatoshi {
        self.sapling_balance.pending_balance()
            .add(self.orchard_balance.pending_balance())
            .add(*self.awaiting_resolution)
    }

    /// Check if wallet has any spendable funds
    fn can_spend(self: @AccountBalance) -> bool {
        self.total_spendable().is_positive()
    }
}

/// Wallet summary with scanning progress
#[derive(Drop, Serde, Debug)]
pub struct WalletSummary {
    /// Account balances
    pub account_balance: AccountBalance,

    /// Chain tip height when summary was created
    pub chain_tip_height: u64,

    /// Last fully scanned height
    pub fully_scanned_height: u64,

    /// Scan progress (numerator/denominator for percentage)
    pub scan_progress: ProgressReport,

    /// Recovery progress for spend-before-sync
    pub recovery_progress: Option<ProgressReport>,

    /// Next priority range to scan
    pub next_scan_range: Option<super::scan_range::ScanRange>,
}

/// Progress tracking for dual progress bars
#[derive(Drop, Copy, Serde, Debug)]
pub struct ProgressReport {
    /// Progress numerator (blocks completed)
    pub numerator: u64,

    /// Progress denominator (total blocks)
    pub denominator: u64,

    /// Whether scanning is complete
    pub is_complete: bool,
}

pub trait ProgressReportTrait {
    fn percentage(self: @ProgressReport) -> u32;
    fn combine_with(self: @ProgressReport, other: @ProgressReport) -> ProgressReport;
}

impl ProgressReportImpl of ProgressReportTrait {
    /// Calculate percentage (0.0 to 1.0)
    fn percentage(self: @ProgressReport) -> u32 {
        if *self.denominator == 0 {
            0
        } else {
            // Return percentage as integer (0-100)
            let pct = (*self.numerator * 100) / *self.denominator;
            if pct > 100 {
                100
            } else {
                pct.try_into().unwrap()
            }
        }
    }

    /// Combine scan and recovery progress
    fn combine_with(self: @ProgressReport, other: @ProgressReport) -> ProgressReport {
        ProgressReport {
            numerator: *self.numerator + *other.numerator,
            denominator: *self.denominator + *other.denominator,
            is_complete: *self.is_complete && *other.is_complete,
        }
    }
}