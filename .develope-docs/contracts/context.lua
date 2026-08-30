local function event(id, required, optional, barrier)
  return {
    id = id,
    required = required or {},
    optional = optional or {},
    barrier = barrier,
  }
end

return {
  contract_version = "0.1.0-readiness.1",
  schema_version = "0.1.0",
  public_api = false,
  decision_refs = { "D-022", "D-023", "D-040", "D-041", "D-053", "D-063", "D-068" },

  file_roles = {
    official = "{Name}.xml",
    temp = "{Name}.xml.yaca-tmp-{nonce}",
    previous_valid = "{Name}.xml.yaca-prev",
    writer_lock = "{Name}.xml.yaca-lock",
  },
  catalog_candidates = { "official" },

  document = {
    root = "YacaContext",
    root_attributes = { "schemaVersion", "generation" },
    ordered_children = { "Header", "Session", "Facts", "ModelView" },
    header_required = { "Name", "CreatedAt", "UpdatedAt" },
    header_optional = { "AutoRenameDisabled", "NamingWaterline", "AutoNameBaseline" },
    session_required = { "CurrentModel", "CurrentPermission", "DoubleCheckOverride", "DoubleCheckGoalOverride", "ContextPrompt" },
    facts_child = "Event",
    model_view_required = { "ActiveManifest" },
    model_view_optional_repeated = { "CompactionRecord" },
  },

  local_ids = {
    "eventSeq",
    "turnId",
    "requestId",
    "attemptId",
    "messageId",
    "toolCallId",
    "operationId",
    "approvalId",
    "reviewId",
    "compactionId",
    "queueItemId",
  },

  event_base = {
    required = { "seq", "type", "at" },
    optional = { "turnId" },
    ordering = "seq-starts-at-1-and-increments-by-1",
    payload_carrier = "Field",
    payload_contract = "event_types.required-and-optional",
  },

  event_types = {
    event("turn_started", { "kind", "configGeneration", "modelSnapshot", "permissionSnapshot", "promptSnapshot", "toolRegistrySnapshot" }, { "runtimeSnapshot", "contextDocumentGeneration", "queueItemId", "continuesResponseId", "supersedesResponseId" }, "after-admission-before-model"),
    event("user_message", { "messageId", "text", "source" }, { "replyToMessageId" }, "before-model-request"),
    event("queue_item", { "queueItemId", "displayId", "action", "text" }, { "beforeQueueItemId", "sideId", "reason" }, "before-queue-report-or-consume"),
    event("model_request", { "requestId", "purpose", "viewManifestRef" }, { "attemptId" }, "request-intent"),
    event("model_message", { "messageId", "requestId", "role", "status", "body" }, { "representation", "rawBytes", "digest" }, "before-interpretation"),
    event("model_control", { "requestId", "control", "payload" }, {}, "before-interpretation"),
    event("model_yield", { "requestId", "messageId" }, {}, "before-waiting-user"),
    event("tool_call", { "toolCallId", "requestId", "name", "canonicalArguments" }, { "providerCallId" }, "before-dispatch"),
    event("permission_decision", { "toolCallId", "capabilities", "decision", "profileSnapshot" }, {}, "before-side-effect"),
    event("approval", { "approvalId", "toolCallId", "decision", "snapshotDigest" }, { "operationId" }, "before-side-effect"),
    event("operation_intent", { "operationId", "toolCallId", "kind", "targetIdentity", "expectedDigest" }, {}, "before-side-effect"),
    event("operation_result", { "operationId", "status", "evidence" }, { "errorId" }, "before-next-model-request"),
    event("tool_result", { "toolCallId", "status", "body", "truncated" }, { "rawBytes", "digest", "errorId" }, "before-next-model-request"),
    event("action_review", { "reviewId", "toolCallId", "verdict", "bindingDigest" }, { "reason" }, "before-verdict-effect"),
    event("termination_review", { "reviewId", "requestId", "verdict", "bindingDigest" }, { "gap", "reason" }, "before-verdict-effect"),
    event("turn_ended", { "outcome" }, { "reason", "errorId" }, "before-external-report"),
    event("cancel", { "targetKind", "targetId", "reason" }, { "result" }, "cancel-fact"),
    event("steer", { "messageId", "targetTurnId", "summary" }, { "sideId" }, "before-steered-request"),
    event("compaction", { "compactionId", "sourceFirstSeq", "sourceLastSeq", "sourceDigest", "status" }, { "summary", "errorId", "sourceEventCount", "summaryDigest", "manifestDigest", "builderAlgorithm", "modelSnapshot", "promptSnapshot", "viewContextGeneration" }, "before-view-publish"),
    event("model_view_published", { "manifestDigest", "firstEventSeq", "lastEventSeq" }, { "replacesManifestDigest", "compactionId", "viewContextGeneration" }, "before-model-use"),
    event("session_override", { "name", "oldValueDigest", "newValueDigest" }, { "effectiveAt" }, "before-next-turn"),
    event("rename", { "oldName", "newName", "manual", "autoRenameDisabled" }, { "oldLogicalPath", "newLogicalPath" }, "same-publish-as-path-change"),
    event("rebind", { "oldLogicalPath", "newLogicalPath", "oldRootIdentity", "newRootIdentity" }, {}, "same-recoverable-transaction-as-move"),
    event("auto_name", { "requestId", "status", "waterline", "baseline" }, { "candidateName", "adopted", "errorId" }, "naming-fact"),
    event("config_generation_ref", { "publicDigest" }, {}, "may-be-folded-into-turn-started"),
    event("warning", { "errorId", "summary" }, { "causeId" }, "diagnostic-fact"),
    event("unknown_side_effect", { "operationId", "reason", "requiredAction" }, {}, "blocks-auto-continue"),
    event("import_mapping", { "sourceSchema", "modelMappings", "permissionMappings", "decision" }, { "notes" }, "audit-only"),
  },

  field_representations = { "text", "base64" },
  operation_result_statuses = { "ok", "error", "cancelled", "unknown", "skipped" },
  tool_result_statuses = { "ok", "error", "cancelled", "unknown", "skipped" },
  model_message_statuses = { "complete", "interrupted" },
  turn_outcomes_from_runtime = true,
  controls_from_model = true,
  purposes_from_model = true,

  invariants = {
    workspace_root_element = false,
    secret_elements = false,
    facts_are_only_business_truth = true,
    transient_delta_events_are_durable = false,
    accepted_tool_call_has_exactly_one_tool_result = true,
    operation_intent_without_result_recovers_as_unknown = true,
    unknown_operation_auto_replay = false,
    model_view_mismatch = "discard-view-and-rebuild-from-facts",
    first_message_before_model_request = true,
    sidecars_are_long_term_facts = false,
    dtd = false,
    external_entities = false,
    xinclude_network = false,
  },

  commit = {
    states = { "AcquireLock", "WriteTemp", "FlushCloseTemp", "ValidateTemp", "PublishReplace", "ConfirmPublished", "CleanupAux", "ReleaseLock" },
    source_generation_required = true,
    full_stream_rewrite = true,
    temp_revalidated_from_start = true,
    publish = "target-proven-atomic-replace-or-two-generation-protocol",
    proof_required = { "TP-008", "TP-011" },
  },

  resource_limits = {
    source = "versioned-release-manifest",
    proof_required = { "TP-009", "TP-010" },
    dimensions = { "total-bytes", "depth", "elements", "attributes-per-element", "text-node-bytes", "event-count", "tool-result-bytes" },
    hard_limit_behavior = "fail-stop-readonly-export-and-new-context-handoff-prompt",
  },

  forbidden_elements = {
    "WorkspaceRoot", "WorkspaceRoots", "ContextId", "Key", "Authorization", "ApprovalGrant",
    "Wal", "Archive", "Trash", "Undo", "Backup", "Restore", "Branch",
  },
}
