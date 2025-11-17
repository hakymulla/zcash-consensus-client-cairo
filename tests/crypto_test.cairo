// /// Comprehensive tests for cryptographic primitives
// /// Tests Pedersen, Blake2b, Note Encryption, and Nullifiers

// #[cfg(test)]
// mod pedersen_tests {
//     use zcash_light_client::crypto::pedersen::{
//         hash_pedersen, merkle_hash,
//         NoteCommitment, NoteCommitmentTrait,
//         IncrementalMerkleTree, IncrementalMerkleTreeTrait
//     };

//     /// Test basic Pedersen hash
//     #[test]
//     fn test_pedersen_hash() {
//         let h1 = hash_pedersen(0x123456, 0x789abc);
//         let h2 = hash_pedersen(0x123456, 0x789abc);
//         let h3 = hash_pedersen(0x789abc, 0x123456);

//         assert(h1 == h2, 'Same inputs same output');
//         assert(h1 != h3, 'Different inputs different output');
//         assert(h1 != 0, 'Hash not zero');
//     }

//     /// Test note commitment
//     #[test]
//     fn test_note_commitment() {
//         let commitment = NoteCommitment::commit(
//             1000000, // value in zatoshi
//             0xaaaaaa, // recipient
//             0xbbbbbb, // rho
//             0xcccccc  // rcm
//         );

//         assert(commitment.value != 0, 'Commitment not zero');

//         // Same inputs should produce same commitment
//         let commitment2 = NoteCommitment::commit(1000000, 0xaaaaaa, 0xbbbbbb, 0xcccccc);
//         assert(commitment.value == commitment2.value, 'Same commitment');

//         // Different value should produce different commitment
//         let commitment3 = NoteCommitment::commit(2000000, 0xaaaaaa, 0xbbbbbb, 0xcccccc);
//         assert(commitment.value != commitment3.value, 'Different commitment');
//     }

//     /// Test commitment verification
//     #[test]
//     fn test_commitment_verification() {
//         let commitment = NoteCommitment::commit(5000000, 0x111111, 0x222222, 0x333333);

//         assert(commitment.verify(commitment.value), 'Should verify');
//         assert(!commitment.verify(0xffffff), 'Wrong value should fail');
//     }

//     /// Test merkle tree operations
//     #[test]
//     fn test_incremental_merkle_tree() {
//         let mut tree = IncrementalMerkleTree::new(32);

//         assert(tree.root == 0, 'Initial root is zero');
//         assert(tree.frontier.is_empty(), 'Initial frontier empty');

//         // Add commitments
//         tree.append(0xaaaaaa);
//         assert(tree.root != 0, 'Root updated after append');

//         tree.append(0xbbbbbb);
//         let root_after_2 = tree.root;

//         tree.append(0xcccccc);
//         let root_after_3 = tree.root;

//         assert(root_after_2 != root_after_3, 'Root changes with new leaf');
//     }

//     /// Test merkle witness generation
//     #[test]
//     fn test_merkle_witness() {
//         let mut tree = IncrementalMerkleTree::new(32);

//         tree.append(0x111111);
//         tree.append(0x222222);
//         tree.append(0x333333);

//         let witness = tree.witness(1); // Get witness for position 1
//         assert(!witness.is_empty(), 'Witness not empty');
//     }

//     /// Test merkle hash consistency
//     #[test]
//     fn test_merkle_hash_consistency() {
//         let h1 = merkle_hash(0xaaa, 0xbbb);
//         let h2 = merkle_hash(0xaaa, 0xbbb);
//         let h3 = merkle_hash(0xbbb, 0xaaa);

//         assert(h1 == h2, 'Consistent hashing');
//         assert(h1 != h3, 'Order matters');
//     }
// }

// #[cfg(test)]
// mod blake2b_tests {
//     use zcash_light_client::crypto::blake2b::{
//         Blake2b, Blake2bTrait,
//         blake2b, blake2b_personal,
//         BLAKE2B_OUTBYTES
//     };

//     /// Test Blake2b initialization
//     #[test]
//     fn test_blake2b_init() {
//         let hasher = Blake2b::new(64);
//         assert(hasher.outlen == 64, 'Output length set');
//         assert(hasher.buffer.is_empty(), 'Buffer initially empty');
//     }

//     /// Test Blake2b hash of empty input
//     #[test]
//     fn test_blake2b_empty() {
//         let empty = ArrayTrait::new();
//         let hash = blake2b(@empty, 32);

//         assert(hash.len() == 32, 'Correct output length');
//         assert(hash[0] != 0 || hash[1] != 0, 'Hash not all zeros');
//     }

//     /// Test Blake2b with data
//     #[test]
//     fn test_blake2b_data() {
//         let mut data = ArrayTrait::new();
//         data.append(0x01);
//         data.append(0x02);
//         data.append(0x03);
//         data.append(0x04);

//         let hash1 = blake2b(@data, 64);
//         let hash2 = blake2b(@data, 64);

//         assert(hash1.len() == 64, 'Correct length');

//         // Same input same output
//         let mut i = 0;
//         loop {
//             if i >= hash1.len() {
//                 break;
//             }
//             assert(hash1[i] == hash2[i], 'Consistent hashing');
//             i += 1;
//         };
//     }

//     /// Test Blake2b personal for Zcash KDF
//     #[test]
//     fn test_blake2b_personal() {
//         let mut data = ArrayTrait::new();
//         data.append(0xaa);
//         data.append(0xbb);

//         let hash = blake2b_personal(@data, @"Zcash_SaplingKDF", 32);
//         assert(hash.len() == 32, 'Correct KDF output length');

//         // Different personalization should give different output
//         let hash2 = blake2b_personal(@data, @"Different", 32);
//         assert(hash[0] != hash2[0] || hash[1] != hash2[1], 'Personal affects output');
//     }

//     /// Test Blake2b incremental hashing
//     #[test]
//     fn test_blake2b_incremental() {
//         let mut hasher = Blake2b::new(32);

//         let mut data1 = ArrayTrait::new();
//         data1.append(0x11);
//         data1.append(0x22);
//         hasher.update(@data1);

//         let mut data2 = ArrayTrait::new();
//         data2.append(0x33);
//         data2.append(0x44);
//         hasher.update(@data2);

//         let result = hasher.finalize();
//         assert(result.len() == 32, 'Correct output length');
//     }
// }

// #[cfg(test)]
// mod note_encryption_tests {
//     use zcash_light_client::crypto::note_encryption::{
//         IncomingViewingKey, DecryptedNote,
//         ka_agree_ephemeral, kdf_sapling,
//         trial_decrypt_compact_output
//     };
//     use zcash_light_client::types::compact_block::{CompactOutput, COMPACT_NOTE_SIZE};

//     /// Test key agreement
//     #[test]
//     fn test_key_agreement() {
//         let epk = 0x123456789;
//         let ivk = 0xabcdef012;

//         let secret1 = ka_agree_ephemeral(epk, ivk);
//         let secret2 = ka_agree_ephemeral(epk, ivk);

//         assert(secret1 == secret2, 'Consistent key agreement');
//         assert(secret1 != 0, 'Secret not zero');

//         // Different keys different secret
//         let secret3 = ka_agree_ephemeral(epk, 0xffffff);
//         assert(secret1 != secret3, 'Different key different secret');
//     }

//     /// Test KDF for Sapling
//     #[test]
//     fn test_kdf_sapling() {
//         let shared_secret = 0xaaaaaa;
//         let epk = 0xbbbbbb;

//         let key = kdf_sapling(shared_secret, epk);
//         assert(key.len() == 32, 'KDF output 32 bytes');

//         // Consistent derivation
//         let key2 = kdf_sapling(shared_secret, epk);
//         assert(key[0] == key2[0], 'Consistent KDF');
//     }

//     /// Test trial decryption failure (wrong key)
//     #[test]
//     fn test_trial_decrypt_wrong_key() {
//         let mut ciphertext = ArrayTrait::new();
//         let mut i = 0;
//         loop {
//             if i >= COMPACT_NOTE_SIZE {
//                 break;
//             }
//             ciphertext.append(i.try_into().unwrap());
//             i += 1;
//         };

//         let output = CompactOutput {
//             cmu: 0x111111,
//             epk: 0x222222,
//             ciphertext: ciphertext,
//         };

//         let wrong_ivk = IncomingViewingKey { key: 0xffffff };
//         let result = trial_decrypt_compact_output(@output, @wrong_ivk, 1000);

//         // Should fail with wrong key (commitment won't match)
//         assert(result.is_none(), 'Wrong key should fail');
//     }

//     /// Test successful decryption simulation
//     #[test]
//     fn test_trial_decrypt_structure() {
//         // This tests the structure, not actual cryptography
//         // Real test would need proper test vectors

//         let ivk = IncomingViewingKey { key: 0xabcdef };

//         // Create a properly sized ciphertext
//         let mut ciphertext = ArrayTrait::new();
//         let mut i = 0;
//         loop {
//             if i >= COMPACT_NOTE_SIZE {
//                 break;
//             }
//             ciphertext.append(0);
//             i += 1;
//         };

//         let output = CompactOutput {
//             cmu: 0x123456,
//             epk: 0x789abc,
//             ciphertext: ciphertext,
//         };

//         let result = trial_decrypt_compact_output(@output, @ivk, 2000);

//         // Structure test - would need real crypto for actual decryption
//         match result {
//             Option::Some(note) => {
//                 assert(note.position == 2000, 'Position preserved');
//             },
//             Option::None => {
//                 // Expected in this test without real crypto
//             }
//         }
//     }
// }

// #[cfg(test)]
// mod nullifier_tests {
//     use zcash_light_client::crypto::nullifier::{
//         Nullifier, NullifierKey, NullifierSet, NullifierCache,
//         NullifierTrait, NullifierSetTrait, NullifierCacheTrait
//     };

//     /// Test nullifier derivation
//     #[test]
//     fn test_nullifier_derive() {
//         let nk = NullifierKey { nk: 0xaaaaaa };
//         let rho = 0xbbbbbb;
//         let position = 1234;

//         let nf1 = Nullifier::derive(@nk, rho, position);
//         let nf2 = Nullifier::derive(@nk, rho, position);

//         assert(nf1.value == nf2.value, 'Consistent derivation');
//         assert(nf1.value != 0, 'Nullifier not zero');

//         // Different position different nullifier
//         let nf3 = Nullifier::derive(@nk, rho, 5678);
//         assert(nf1.value != nf3.value, 'Position affects nullifier');
//     }

//     /// Test nullifier equality
//     #[test]
//     fn test_nullifier_equality() {
//         let nf1 = Nullifier { value: 0x123456 };
//         let nf2 = Nullifier { value: 0x123456 };
//         let nf3 = Nullifier { value: 0x789abc };

//         assert(nf1.equals(@nf2), 'Same value equal');
//         assert(!nf1.equals(@nf3), 'Different value not equal');
//     }

//     /// Test nullifier set
//     #[test]
//     fn test_nullifier_set() {
//         let mut set = NullifierSet::new();
//         assert(set.len() == 0, 'Initially empty');

//         let nf1 = Nullifier { value: 0xaaa };
//         let nf2 = Nullifier { value: 0xbbb };

//         assert(set.insert(nf1), 'First insert succeeds');
//         assert(set.len() == 1, 'Size increased');
//         assert(set.contains(@nf1), 'Contains inserted');

//         assert(set.insert(nf2), 'Second insert succeeds');
//         assert(set.len() == 2, 'Size increased again');

//         // Duplicate insert should fail
//         assert(!set.insert(nf1), 'Duplicate insert fails');
//         assert(set.len() == 2, 'Size unchanged');
//     }

//     /// Test nullifier cache
//     #[test]
//     fn test_nullifier_cache() {
//         let mut cache = NullifierCache::new(100);

//         let nf1 = Nullifier { value: 0x111 };
//         let nf2 = Nullifier { value: 0x222 };

//         cache.add(nf1, 1000);
//         cache.add(nf2, 1001);

//         assert(cache.contains(@nf1), 'Cache contains nf1');
//         assert(cache.contains(@nf2), 'Cache contains nf2');

//         let nf3 = Nullifier { value: 0x333 };
//         assert(!cache.contains(@nf3), 'Does not contain nf3');
//     }

//     /// Test cache clearing
//     #[test]
//     fn test_cache_clear() {
//         let mut cache = NullifierCache::new(50);

//         let nf = Nullifier { value: 0xaaa };
//         cache.add(nf, 900);

//         assert(cache.contains(@nf), 'Contains before clear');

//         cache.clear_before(1000);
//         assert(!cache.contains(@nf), 'Cleared after height');
//     }

//     /// Test merkle root update
//     #[test]
//     fn test_nullifier_set_merkle_root() {
//         let mut set = NullifierSet::new();
//         assert(set.merkle_root == 0, 'Initial root zero');

//         let nf = Nullifier { value: 0xfedcba };
//         set.insert(nf);

//         assert(set.merkle_root != 0, 'Root updated after insert');

//         let old_root = set.merkle_root;
//         let nf2 = Nullifier { value: 0xabcdef };
//         set.insert(nf2);

//         assert(set.merkle_root != old_root, 'Root changes with new nullifier');
//     }
// }