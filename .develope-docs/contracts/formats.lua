return {
  contract_version = "0.1.0-readiness.1",
  decision_refs = { "D-003", "D-023", "D-052", "D-053", "D-059", "D-068", "D-070" },

  utf8 = {
    canonical = "strict-Unicode-scalar-sequence",
    accepted_widths = { 1, 2, 3, 4 },
    reject = {
      "overlong", "truncated", "isolated-continuation", "surrogate",
      "above-U+10FFFF", "invalid-leading-byte",
    },
    replacement_on_error = false,
    normalization = "none-preserve-exact-scalar-sequence",
    nul_is_valid_scalar_but_not_text_carrier = true,
  },

  sha256 = {
    algorithm = "SHA-256",
    full_digest = "32-raw-bytes-or-64-lowercase-hex-by-schema",
    context_hash = {
      input = "exact-UTF-8-bytes-of-LogicalPath",
      extraction = "first-8-digest-bytes-in-network-order",
      output = "16-uppercase-hex",
      input_selector_accepts = "exactly-16-case-insensitive-hex-normalized-uppercase",
      aliases_after_path_change = false,
    },
    domain_separation = "ASCII-domain-id+NUL+canonical-bytes",
    implementation = "bundled-yaca-native-streaming-with-independent-fixture-oracle",
  },

  json = {
    profile = "RFC-8259-strict-subset",
    encoding = "strict-utf8",
    bom = "reject",
    top_level = { "object", "array" },
    duplicate_object_key = "error-before-schema-use",
    unknown_object_key = "schema-owned-error-or-profile-explicit-ignore",
    number = {
      grammar = "RFC-8259",
      non_finite = "reject",
      negative_zero = "preserve-lexeme-until-schema-conversion",
      exponent = "preserve-lexeme-until-schema-conversion",
      conversion = "schema-validates-range-before-integer-or-number-allocation",
    },
    strings = {
      unescaped_control = "reject",
      escape_set = { '"', "\\", "/", "b", "f", "n", "r", "t", "uXXXX" },
      surrogate_escape = "only-valid-high+low-pair",
    },
    writer = {
      encoding = "utf-8-no-bom",
      object_key_order = "lexicographic-by-UTF-8-bytes",
      insignificant_whitespace = "none",
      escape = "required-only-with-lowercase-u-hex",
    },
    limits_source = "release-manifest",
  },

  sse = {
    input = "raw-response-bytes-after-HTTP-content-decoding",
    line_endings = { "LF", "CRLF", "CR" },
    leading_utf8_bom = "reject",
    fields = { "event", "data", "id", "retry" },
    unknown_field = "ignore-per-SSE-but-never-canonicalize",
    comment_line = "ignore",
    multi_data = "join-with-single-LF",
    empty_line = "dispatch-event",
    eof_with_unterminated_event = "protocol-error-incomplete",
    id_effect = "diagnostic-only-no-resume",
    retry_effect = "ignored-never-overrides-yaca-retry-snapshot",
    done_sentinel = "adapter-profile-owned-exact-bytes",
    limits_source = "release-manifest",
  },

  xml = {
    parser = "LuaExpat-1.5.2+Expat-2.8.2-SAX",
    structure = "context.rng+context.lua",
    dtd = "hard-reject-registered-callback",
    entity_declaration = "hard-reject",
    external_entity = "hard-reject-without-open",
    xinclude = "schema-unknown-element",
    text_representation = "XML-1.0-safe-and-CR-free-strict-UTF-8",
    base64_representation = "RFC-4648-standard-padded",
    binary_is_typed_only = true,
    missing_and_present_empty_are_distinct = true,
    normalization = "none",
    limits_source = "release-manifest",
  },

  ini = {
    owner = "config.lua.ini_grammar",
    duplicate_section = "merge-only-if-every-physical-key-remains-unique-otherwise-error",
    duplicate_key = "error",
    unknown_section = "error",
    unknown_key = "error",
    semantic_writer = "canonical-section-and-field-order-from-config.lua",
    concrete_preservation = "preserve-unmodified-lines-comments-and-line-ending-when-safe",
  },
}
