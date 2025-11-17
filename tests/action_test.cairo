/// Tests for Action system and ActionContext
/// Tests the action trait, context management, and state transitions

#[cfg(test)]
mod action_tests {
    use zcash_light_client::state::action::{
        ActionContext, ActionContextTrait, ActionResult,
        SyncControlData, ProcessorEvent, SyncProgressEvent
    };
    use zcash_light_client::state::processor_state::CBPState;
    use zcash_light_client::types::scan_range::{ScanRange, ScanPriority};
    use zcash_light_client::types::compact_block::BlockHeight;

    /// Test action context initialization
    #[test]
    fn test_context_initialization() {
        let context = ActionContext::new(CBPState::Idle);

        assert(context.state == CBPState::Idle, 'Initial state set');
        assert(context.prev_state.is_none(), 'No previous state');
        assert(context.processed_height == 0, 'Zero processed height');
        assert(context.total_blocks_to_process == 0, 'Zero total blocks');
        assert(context.scan_ranges.is_empty(), 'Empty scan ranges');
        assert(context.error.is_none(), 'No error initially');
    }

    /// Test state update tracking
    #[test]
    fn test_state_update() {
        let mut context = ActionContext::new(CBPState::Idle);

        context.update_state(CBPState::ValidateServer);
        assert(context.state == CBPState::ValidateServer, 'State updated');
        assert(context.prev_state == Option::Some(CBPState::Idle), 'Previous tracked');

        context.update_state(CBPState::UpdateChainTip);
        assert(context.state == CBPState::UpdateChainTip, 'State updated again');
        assert(context.prev_state == Option::Some(CBPState::ValidateServer), 'Previous updated');
    }

    /// Test sync control data
    #[test]
    fn test_sync_control_data() {
        let mut context = ActionContext::new(CBPState::Idle);

        context.sync_control_data = SyncControlData {
            latest_block_height: 2_500_000,
            latest_scanned_height: Option::Some(2_499_000),
            first_unenhanced_height: Option::Some(2_498_000),
        };

        assert(context.sync_control_data.latest_block_height == 2_500_000, 'Height set');
        assert(
            context.sync_control_data.latest_scanned_height == Option::Some(2_499_000),
            'Scanned height set'
        );
    }

    /// Test chain tip update timing
    #[test]
    fn test_should_update_chain_tip() {
        let mut context = ActionContext::new(CBPState::UpdateChainTip);
        context.last_chain_tip_update_time = 1000;

        // Should not update immediately
        assert(!context.should_update_chain_tip(1010), 'Too soon to update');

        // Should update after 30 seconds
        assert(context.should_update_chain_tip(1031), 'Time to update');
        assert(context.should_update_chain_tip(2000), 'Way past update time');
    }

    /// Test scan range management
    #[test]
    fn test_scan_range_queue() {
        let mut context = ActionContext::new(CBPState::ProcessSuggestedScanRanges);

        // Add scan ranges with different priorities
        context.scan_ranges.append(ScanRange::new(1000, 2000, ScanPriority::Historic));
        context.scan_ranges.append(ScanRange::new(2000, 3000, ScanPriority::FoundNote));
        context.scan_ranges.append(ScanRange::new(3000, 4000, ScanPriority::ChainTip));

        assert(context.scan_ranges.len() == 3, 'Three ranges added');

        // Get next range (FIFO order in this simple implementation)
        let next = context.next_scan_range();
        assert(next.is_some(), 'Should have next range');

        match next {
            Option::Some(range) => {
                assert(range.start_height == 1000, 'First range returned');
                assert(range.priority == ScanPriority::Historic, 'Correct priority');
            },
            Option::None => {
                assert(false, 'Should not be none');
            }
        }

        assert(context.scan_ranges.len() == 2, 'One range removed');
    }

    /// Test sync progress calculation
    #[test]
    fn test_sync_progress() {
        let mut context = ActionContext::new(CBPState::Scan);

        context.total_blocks_to_process = 1000;
        context.processed_height = 0;
        assert(context.sync_progress() == 0, '0% progress');

        context.processed_height = 250;
        assert(context.sync_progress() == 25, '25% progress');

        context.processed_height = 500;
        assert(context.sync_progress() == 50, '50% progress');

        context.processed_height = 1000;
        assert(context.sync_progress() == 100, '100% progress');

        // Test overflow protection
        context.processed_height = 1500;
        assert(context.sync_progress() == 100, 'Capped at 100%');
    }

    /// Test error handling in context
    #[test]
    fn test_error_context() {
        let mut context = ActionContext::new(CBPState::Download);

        assert(context.error.is_none(), 'No error initially');

        context.error = Option::Some("Network connection failed");
        context.update_state(CBPState::Failed);

        assert(context.state == CBPState::Failed, 'Failed state');
        assert(context.error.is_some(), 'Error stored');
    }

    /// Test processing heights tracking
    #[test]
    fn test_height_tracking() {
        let mut context = ActionContext::new(CBPState::Scan);

        context.last_scanned_height = Option::Some(1000);
        context.last_downloaded_height = Option::Some(1100);
        context.last_enhanced_height = Option::Some(900);

        assert(context.last_downloaded_height > context.last_scanned_height, 'Download ahead');
        assert(context.last_scanned_height > context.last_enhanced_height, 'Scan ahead of enhance');
    }

    /// Test rewind request
    #[test]
    fn test_rewind_request() {
        let mut context = ActionContext::new(CBPState::Scan);

        assert(context.requested_rewind_height.is_none(), 'No rewind initially');

        // Request rewind to specific height
        context.requested_rewind_height = Option::Some(2_400_000);
        context.update_state(CBPState::Rewind);

        assert(context.state == CBPState::Rewind, 'Rewind state');
        assert(context.requested_rewind_height == Option::Some(2_400_000), 'Rewind height set');
    }
}

#[cfg(test)]
mod action_result_tests {
    use zcash_light_client::state::action::{ActionResult, ActionContext};
    use zcash_light_client::state::processor_state::CBPState;

    /// Test continue result
    #[test]
    fn test_action_continue() {
        let context = ActionContext::new(CBPState::ValidateServer);

        let result = ActionResult::Continue(context);
        match result {
            ActionResult::Continue(ctx) => {
                assert(ctx.state == CBPState::ValidateServer, 'Context preserved');
            },
            _ => {
                assert(false, 'Wrong result type');
            }
        }
    }

    /// Test stop result
    #[test]
    fn test_action_stop() {
        let mut context = ActionContext::new(CBPState::Download);
        context.update_state(CBPState::Stopped);

        let result = ActionResult::Stop(context);
        match result {
            ActionResult::Stop(ctx) => {
                assert(ctx.state == CBPState::Stopped, 'Stopped state');
            },
            _ => {
                assert(false, 'Wrong result type');
            }
        }
    }

    /// Test failed result
    #[test]
    fn test_action_failed() {
        let mut context = ActionContext::new(CBPState::Scan);
        context.update_state(CBPState::Failed);

        let error_msg = "Database corruption detected";
        let result = ActionResult::Failed((context, error_msg));

        match result {
            ActionResult::Failed((ctx, msg)) => {
                assert(ctx.state == CBPState::Failed, 'Failed state');
                assert(msg == error_msg, 'Error message preserved');
            },
            _ => {
                assert(false, 'Wrong result type');
            }
        }
    }
}

#[cfg(test)]
mod processor_event_tests {
    use zcash_light_client::state::action::{
        ProcessorEvent, SyncProgressEvent, FoundTransactionsEvent
    };

    /// Test sync progress event
    #[test]
    fn test_sync_progress_event() {
        let event = ProcessorEvent::SyncProgress(SyncProgressEvent {
            progress: 75,
            current_height: 2_450_000,
            target_height: 2_500_000,
            scan_progress_numerator: 750,
            scan_progress_denominator: 1000,
        });

        match event {
            ProcessorEvent::SyncProgress(progress) => {
                assert(progress.progress == 75, 'Progress value');
                assert(progress.current_height == 2_450_000, 'Current height');
                assert(progress.target_height == 2_500_000, 'Target height');
            },
            _ => {
                assert(false, 'Wrong event type');
            }
        }
    }

    /// Test found transactions event
    #[test]
    fn test_found_transactions_event() {
        let mut tx_ids = ArrayTrait::new();
        tx_ids.append(0xaaaaaa);
        tx_ids.append(0xbbbbbb);

        let event = ProcessorEvent::FoundTransactions(FoundTransactionsEvent {
            height: 2_450_000,
            tx_ids: tx_ids,
            notes_found: 5,
        });

        match event {
            ProcessorEvent::FoundTransactions(found) => {
                assert(found.height == 2_450_000, 'Block height');
                assert(found.tx_ids.len() == 2, 'Two transactions');
                assert(found.notes_found == 5, 'Five notes found');
            },
            _ => {
                assert(false, 'Wrong event type');
            }
        }
    }

    /// Test terminal events
    #[test]
    fn test_terminal_events() {
        let finished = ProcessorEvent::Finished(2_500_000);
        match finished {
            ProcessorEvent::Finished(height) => {
                assert(height == 2_500_000, 'Finished height');
            },
            _ => {
                assert(false, 'Wrong type');
            }
        }

        let failed = ProcessorEvent::Failed("Connection timeout");
        match failed {
            ProcessorEvent::Failed(msg) => {
                assert(msg == "Connection timeout", 'Error message');
            },
            _ => {
                assert(false, 'Wrong type');
            }
        }

        let stopped = ProcessorEvent::Stopped;
        match stopped {
            ProcessorEvent::Stopped => {
                // Success
            },
            _ => {
                assert(false, 'Wrong type');
            }
        }
    }
}