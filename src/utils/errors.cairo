/// Error types for Zcash light client operations

#[derive(Drop, Serde, Debug)]
pub enum ZcashError {
    /// Network errors (server unreachable, timeout, etc.)
    NetworkError: ByteArray,

    /// Cryptographic errors (invalid key, signature failure, etc.)
    CryptoError: ByteArray,

    /// Database errors (corruption, IO failure, etc.)
    DatabaseError: ByteArray,

    /// Synchronization errors (reorg detected, invalid block, etc.)
    SyncError: ByteArray,

    /// Validation errors (invalid transaction, proof verification failed, etc.)
    ValidationError: ByteArray,

    /// General errors
    Other: ByteArray,
}

pub trait ZcashErrorTrait {
    fn message(self: @ZcashError) -> ByteArray;
}

impl ZcashErrorImpl of ZcashErrorTrait {
    fn message(self: @ZcashError) -> ByteArray {
        match self {
            ZcashError::NetworkError(msg) => msg.clone(),
            ZcashError::CryptoError(msg) => msg.clone(),
            ZcashError::DatabaseError(msg) => msg.clone(),
            ZcashError::SyncError(msg) => msg.clone(),
            ZcashError::ValidationError(msg) => msg.clone(),
            ZcashError::Other(msg) => msg.clone(),
        }
    }
}
